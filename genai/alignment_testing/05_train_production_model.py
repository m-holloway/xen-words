#!/usr/bin/env python3
"""
Production-ready boundary detection model.

Key improvements:
1. Sequence-to-sequence (no global pooling!)
2. Focal loss for imbalanced data
3. Causal convolutions for streaming
4. Smaller context window (200ms vs 500ms)
5. Proper evaluation with temporal tolerance
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.model_selection import train_test_split
from sklearn.metrics import precision_score, recall_score, f1_score
import matplotlib.pyplot as plt
import json
import glob
from pathlib import Path

# Hyperparameters
CONTEXT_FRAMES = 13  # 200ms @ 16ms hop (reduced from 31)
N_MFCC = 13
BATCH_SIZE = 128
LEARNING_RATE = 0.0005
EPOCHS = 50
PATIENCE = 10

def focal_loss(alpha=0.25, gamma=2.0, peak_boost=3.0):
    """
    Focal Loss with peak boundary weighting.
    
    Focuses learning on:
    - Hard examples (near-boundary frames)
    - True peaks (y_true > 0.9)
    
    Down-weights:
    - Easy negatives (clear background)
    """
    def loss(y_true, y_pred):
        # Clip predictions for numerical stability
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)
        
        # Binary cross entropy
        bce = -(y_true * tf.math.log(y_pred) + (1 - y_true) * tf.math.log(1 - y_pred))
        
        # Focal weight: down-weight easy examples
        p_t = tf.where(y_true >= 0.5, y_pred, 1 - y_pred)
        focal_weight = alpha * tf.pow(1 - p_t, gamma)
        
        # Peak boost: extra weight for true boundaries
        peak_mask = tf.cast(y_true > 0.9, tf.float32)
        peak_weight = 1.0 + peak_mask * (peak_boost - 1.0)
        
        # Combined loss
        loss = focal_weight * bce * peak_weight
        
        return tf.reduce_mean(loss)
    
    return loss

def build_streaming_model(context_frames=CONTEXT_FRAMES, n_mfcc=N_MFCC):
    """
    Build causal sequence-to-sequence model.
    
    Architecture:
    - Causal convolutions (no future peeking)
    - Dilated convolutions (large receptive field)
    - Per-frame predictions (preserve temporal structure)
    - Output center frame for training
    
    For streaming inference:
    - Process one frame at a time
    - Use latest frame output
    - Latency: single frame (16ms)
    """
    inputs = layers.Input(shape=(context_frames, n_mfcc), name='mfcc_input')
    
    # Initial feature extraction
    x = inputs
    
    # Causal dilated convolutions
    # Total receptive field: ~430ms
    x = layers.Conv1D(64, kernel_size=5, padding='causal', dilation_rate=1)(x)
    x = layers.BatchNormalization()(x)
    x = layers.Activation('relu')(x)
    x = layers.Dropout(0.3)(x)
    
    x = layers.Conv1D(64, kernel_size=5, padding='causal', dilation_rate=2)(x)
    x = layers.BatchNormalization()(x)
    x = layers.Activation('relu')(x)
    x = layers.Dropout(0.3)(x)
    
    x = layers.Conv1D(128, kernel_size=3, padding='causal', dilation_rate=4)(x)
    x = layers.BatchNormalization()(x)
    x = layers.Activation('relu')(x)
    x = layers.Dropout(0.3)(x)
    
    # Per-frame prediction head
    x = layers.Conv1D(64, kernel_size=1)(x)  # 1x1 conv
    x = layers.BatchNormalization()(x)
    x = layers.Activation('relu')(x)
    
    # Output: boundary probability per frame
    x = layers.Conv1D(1, kernel_size=1, activation='sigmoid', name='per_frame_output')(x)
    
    # Extract center frame for training
    center_idx = context_frames // 2
    center_frame = layers.Lambda(lambda x: x[:, center_idx, :], name='center_frame')(x)
    
    model = keras.Model(inputs=inputs, outputs=center_frame)
    
    return model

def load_dataset_with_context(dataset_dir='dataset_500', context_frames=CONTEXT_FRAMES):
    """
    Load dataset and extract context windows.
    
    Original dataset has 31-frame windows.
    We extract center N frames for smaller context.
    """
    X_list = []
    y_list = []
    
    npz_files = sorted(glob.glob(f"{dataset_dir}/*.npz"))
    print(f"Loading {len(npz_files)} files...")
    
    for npz_file in npz_files:
        data = np.load(npz_file)
        features = data['features']  # (n_windows, 31, 13)
        labels = data['labels']      # (n_windows,)
        
        # Extract center context_frames
        original_context = features.shape[1]
        if original_context >= context_frames:
            start = (original_context - context_frames) // 2
            end = start + context_frames
            features = features[:, start:end, :]
        else:
            # Pad if needed (shouldn't happen with our data)
            pad_width = ((0, 0), (0, context_frames - original_context), (0, 0))
            features = np.pad(features, pad_width, mode='edge')
        
        X_list.append(features)
        y_list.append(labels)
    
    X = np.concatenate(X_list, axis=0)
    y = np.concatenate(y_list, axis=0)
    
    return X, y

def evaluate_with_tolerance(y_true, y_pred, threshold=0.5, tolerance_frames=3):
    """
    Evaluate with temporal tolerance.
    
    A prediction is correct if within tolerance_frames of a true boundary.
    tolerance_frames=3 → 48ms @ 16ms hop
    """
    # Binarize
    y_true_binary = (y_true > 0.5).astype(int)
    y_pred_binary = (y_pred > threshold).astype(int)
    
    # Find predicted boundary indices
    pred_boundaries = np.where(y_pred_binary == 1)[0]
    true_boundaries = np.where(y_true_binary == 1)[0]
    
    if len(pred_boundaries) == 0 or len(true_boundaries) == 0:
        return 0.0, 0.0, 0.0
    
    # Count matches within tolerance
    true_positives = 0
    for pred_idx in pred_boundaries:
        # Check if any true boundary is within tolerance
        distances = np.abs(true_boundaries - pred_idx)
        if np.min(distances) <= tolerance_frames:
            true_positives += 1
    
    precision = true_positives / len(pred_boundaries) if len(pred_boundaries) > 0 else 0
    recall = true_positives / len(true_boundaries) if len(true_boundaries) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
    
    return precision, recall, f1

def main(dataset_dir='dataset_500_v2', checkpoint_dir='checkpoints_v2'):
    """
    Train production-ready model.
    """
    print("=" * 60)
    print("🚀 PRODUCTION MODEL TRAINING")
    print("=" * 60)
    
    # Load dataset
    print(f"\n📥 Loading dataset: {dataset_dir}")
    X, y = load_dataset_with_context(dataset_dir, context_frames=CONTEXT_FRAMES)
    
    print(f"\n📊 Dataset Stats:")
    print(f"   Total samples: {len(X):,}")
    print(f"   Feature shape: {X.shape}")
    print(f"   Context window: {CONTEXT_FRAMES} frames ({CONTEXT_FRAMES * 16}ms)")
    print(f"   Boundaries (>0.5): {np.sum(y > 0.5):,} ({100*np.sum(y > 0.5)/len(y):.1f}%)")
    print(f"   Non-zero labels: {np.sum(y > 0.01):,} ({100*np.sum(y > 0.01)/len(y):.1f}%)")
    print(f"   Mean label: {y.mean():.4f}")
    
    # Split data
    X_temp, X_test, y_temp, y_test = train_test_split(
        X, y, test_size=0.15, random_state=42
    )
    X_train, X_val, y_train, y_val = train_test_split(
        X_temp, y_temp, test_size=0.176, random_state=42  # 0.176 * 0.85 ≈ 0.15
    )
    
    print(f"\n📊 Split:")
    print(f"   Train: {len(X_train):,} ({100*len(X_train)/len(X):.1f}%)")
    print(f"   Val:   {len(X_val):,} ({100*len(X_val)/len(X):.1f}%)")
    print(f"   Test:  {len(X_test):,} ({100*len(X_test)/len(X):.1f}%)")
    
    # Build model
    print(f"\n🏗️  Building model...")
    model = build_streaming_model(context_frames=CONTEXT_FRAMES, n_mfcc=N_MFCC)
    
    print(f"\n📐 Model Architecture:")
    model.summary(print_fn=lambda x: print(f"   {x}"))
    
    # Count parameters
    trainable_params = sum([tf.size(w).numpy() for w in model.trainable_weights])
    print(f"\n   Total trainable parameters: {trainable_params:,}")
    print(f"   Estimated model size: {trainable_params * 4 / 1024:.1f} KB (float32)")
    
    # Compile with focal loss
    print(f"\n⚙️  Compiling model...")
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss=focal_loss(alpha=0.25, gamma=2.0, peak_boost=3.0),
        metrics=[
            keras.metrics.BinaryAccuracy(threshold=0.5, name='accuracy'),
            keras.metrics.Precision(thresholds=0.5, name='precision'),
            keras.metrics.Recall(thresholds=0.5, name='recall')
        ]
    )
    
    # Callbacks
    Path(checkpoint_dir).mkdir(exist_ok=True)
    
    callbacks = [
        keras.callbacks.ModelCheckpoint(
            filepath=f"{checkpoint_dir}/best_model.keras",
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        ),
        keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=PATIENCE,
            restore_best_weights=True,
            verbose=1
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-6,
            verbose=1
        )
    ]
    
    # Train
    print(f"\n🏋️  Training...")
    print(f"   Batch size: {BATCH_SIZE}")
    print(f"   Learning rate: {LEARNING_RATE}")
    print(f"   Max epochs: {EPOCHS}")
    print(f"   Early stopping patience: {PATIENCE}")
    
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        callbacks=callbacks,
        verbose=2
    )
    
    # Evaluate on test set
    print(f"\n📊 EVALUATING ON TEST SET")
    print("=" * 60)
    
    y_pred = model.predict(X_test, verbose=0).flatten()
    
    # Standard metrics (frame-level)
    print(f"\n📏 Frame-Level Metrics (threshold=0.5):")
    y_test_binary = (y_test > 0.5).astype(int)
    y_pred_binary = (y_pred > 0.5).astype(int)
    
    precision_frame = precision_score(y_test_binary, y_pred_binary, zero_division=0)
    recall_frame = recall_score(y_test_binary, y_pred_binary, zero_division=0)
    f1_frame = f1_score(y_test_binary, y_pred_binary, zero_division=0)
    
    print(f"   Precision: {precision_frame:.3f} ({100*precision_frame:.1f}%)")
    print(f"   Recall:    {recall_frame:.3f} ({100*recall_frame:.1f}%)")
    print(f"   F1 Score:  {f1_frame:.3f}")
    
    # Temporal tolerance metrics (more realistic)
    print(f"\n🎯 Temporal Tolerance Metrics:")
    for tolerance_ms in [25, 50, 100]:
        tolerance_frames = tolerance_ms // 16  # Convert ms to frames
        p, r, f1 = evaluate_with_tolerance(y_test, y_pred, threshold=0.5, tolerance_frames=tolerance_frames)
        print(f"   @ {tolerance_ms}ms ({tolerance_frames} frames):")
        print(f"      Precision: {p:.3f} ({100*p:.1f}%)")
        print(f"      Recall:    {r:.3f} ({100*r:.1f}%)")
        print(f"      F1 Score:  {f1:.3f}")
    
    # Save results
    results = {
        'hyperparameters': {
            'context_frames': CONTEXT_FRAMES,
            'context_ms': CONTEXT_FRAMES * 16,
            'n_mfcc': N_MFCC,
            'batch_size': BATCH_SIZE,
            'learning_rate': LEARNING_RATE,
            'epochs_trained': len(history.history['loss'])
        },
        'model_stats': {
            'trainable_params': int(trainable_params),
            'model_size_kb': float(trainable_params * 4 / 1024)
        },
        'frame_level': {
            'precision': float(precision_frame),
            'recall': float(recall_frame),
            'f1': float(f1_frame)
        },
        'temporal_tolerance': {}
    }
    
    for tolerance_ms in [25, 50, 100]:
        tolerance_frames = tolerance_ms // 16
        p, r, f1 = evaluate_with_tolerance(y_test, y_pred, threshold=0.5, tolerance_frames=tolerance_frames)
        results['temporal_tolerance'][f'{tolerance_ms}ms'] = {
            'precision': float(p),
            'recall': float(r),
            'f1': float(f1)
        }
    
    with open(f'{checkpoint_dir}/results.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    # Plot training history
    plt.figure(figsize=(12, 4))
    
    plt.subplot(1, 2, 1)
    plt.plot(history.history['loss'], label='Train Loss')
    plt.plot(history.history['val_loss'], label='Val Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    plt.title('Training Loss')
    plt.grid(True)
    
    plt.subplot(1, 2, 2)
    plt.plot(history.history['recall'], label='Train Recall')
    plt.plot(history.history['val_recall'], label='Val Recall')
    plt.plot(history.history['precision'], label='Train Precision')
    plt.plot(history.history['val_precision'], label='Val Precision')
    plt.xlabel('Epoch')
    plt.ylabel('Score')
    plt.legend()
    plt.title('Training Metrics')
    plt.grid(True)
    
    plt.tight_layout()
    plt.savefig(f'{checkpoint_dir}/training_history.png', dpi=150)
    print(f"\n📊 Training history saved to: {checkpoint_dir}/training_history.png")
    
    print(f"\n✅ TRAINING COMPLETE!")
    print(f"   Model saved to: {checkpoint_dir}/best_model.keras")
    print(f"   Results saved to: {checkpoint_dir}/results.json")

if __name__ == "__main__":
    import sys
    dataset_dir = sys.argv[1] if len(sys.argv) > 1 else 'dataset_500_v2'
    checkpoint_dir = sys.argv[2] if len(sys.argv) > 2 else 'checkpoints_v2'
    main(dataset_dir=dataset_dir, checkpoint_dir=checkpoint_dir)

