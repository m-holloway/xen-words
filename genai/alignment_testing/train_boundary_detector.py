#!/usr/bin/env python3
"""
Train a small neural network to detect word boundaries in real-time.
Uses Whisper as ground truth "teacher" and creates a fast "student" model.

Approach: Knowledge Distillation
- Teacher: Whisper (accurate but slow)
- Student: Small CNN (fast but needs training)
- Task: Predict word boundaries from audio features

This can run in real-time on mobile devices via TensorFlow Lite.
"""

import numpy as np
import librosa
import json
from pathlib import Path
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
import matplotlib.pyplot as plt


def extract_features(audio, sr=16000, frame_ms=32, hop_ms=16):
    """
    Extract MFCC features from audio.
    
    Args:
        audio: Audio samples
        sr: Sample rate
        frame_ms: Frame size in milliseconds
        hop_ms: Hop size in milliseconds
    
    Returns:
        MFCCs of shape (n_frames, n_mfcc)
    """
    n_fft = int(sr * frame_ms / 1000)
    hop_length = int(sr * hop_ms / 1000)
    
    # Extract 13 MFCC coefficients (standard for speech)
    mfccs = librosa.feature.mfcc(
        y=audio,
        sr=sr,
        n_mfcc=13,
        n_fft=n_fft,
        hop_length=hop_length
    )
    
    # Transpose to (n_frames, n_mfcc)
    return mfccs.T


def create_labels_from_ground_truth(audio_duration, ground_truth_timings, hop_ms=16):
    """
    Create binary labels: 1 = word boundary, 0 = within/between words.
    
    Args:
        audio_duration: Duration of audio in seconds
        ground_truth_timings: List of word timings from Whisper
        hop_ms: Hop size in milliseconds
    
    Returns:
        Binary labels array
    """
    n_frames = int(audio_duration * 1000 / hop_ms)
    labels = np.zeros(n_frames, dtype=np.float32)
    
    # Mark frames near word starts as boundaries
    boundary_window_ms = 50  # 50ms window around word start
    
    for wt in ground_truth_timings:
        start_time = wt['start']
        
        # Convert to frame index
        frame_idx = int(start_time * 1000 / hop_ms)
        
        # Mark a small window as boundary
        window_frames = int(boundary_window_ms / hop_ms)
        start_frame = max(0, frame_idx - window_frames // 2)
        end_frame = min(n_frames, frame_idx + window_frames // 2)
        
        labels[start_frame:end_frame] = 1.0
    
    return labels


def build_model(input_shape=(None, 13)):
    """
    Build a small CNN for word boundary detection.
    
    Architecture:
        Input: MFCC features (n_frames, 13)
        Conv1D layers for feature extraction
        Dense layer for classification
        Output: Binary (boundary probability)
    
    Target: <5MB model size, <10ms inference
    """
    model = keras.Sequential([
        # Input layer
        layers.Input(shape=input_shape),
        
        # Feature extraction (NO pooling to maintain sequence length)
        layers.Conv1D(32, kernel_size=3, activation='relu', padding='same'),
        layers.BatchNormalization(),
        
        layers.Conv1D(64, kernel_size=3, activation='relu', padding='same'),
        layers.BatchNormalization(),
        
        # Temporal context
        layers.Bidirectional(layers.LSTM(32, return_sequences=True)),
        
        # Classification
        layers.Dense(32, activation='relu'),
        layers.Dropout(0.3),
        layers.Dense(1, activation='sigmoid'),  # Binary output
    ])
    
    model.compile(
        optimizer='adam',
        loss='binary_crossentropy',
        metrics=['accuracy', tf.keras.metrics.Precision(), tf.keras.metrics.Recall()]
    )
    
    return model


def prepare_training_data(ground_truth_path, audio_path):
    """
    Prepare training data from ground truth and audio.
    """
    print("\n📊 Preparing Training Data...")
    print("=" * 60)
    
    # Load ground truth
    with open(ground_truth_path, 'r') as f:
        gt = json.load(f)
    
    word_timings = gt['word_timings']
    
    # Load audio
    audio, sr = librosa.load(audio_path, sr=16000)
    audio_duration = len(audio) / sr
    
    print(f"Audio duration: {audio_duration:.2f}s")
    print(f"Words: {len(word_timings)}")
    
    # Extract features
    features = extract_features(audio)
    print(f"Features shape: {features.shape}")
    
    # Create labels
    labels = create_labels_from_ground_truth(audio_duration, word_timings)
    
    # Match feature and label lengths
    min_len = min(len(features), len(labels))
    features = features[:min_len]
    labels = labels[:min_len]
    
    print(f"Labels shape: {labels.shape}")
    print(f"Boundary frames: {np.sum(labels):.0f} ({np.sum(labels)/len(labels)*100:.1f}%)")
    
    return features, labels


def train_model(features, labels, epochs=50, batch_size=32):
    """
    Train the boundary detection model.
    """
    print("\n🏋️ Training Model...")
    print("=" * 60)
    
    # Reshape for Conv1D (add batch dimension if needed)
    X = features.reshape(1, *features.shape)
    y = labels.reshape(1, *labels.shape)
    
    print(f"Training data shape: {X.shape}")
    print(f"Labels shape: {y.shape}")
    
    # Build model
    model = build_model()
    model.summary()
    
    # Calculate class weights (boundaries are rare)
    pos_weight = (len(labels) - np.sum(labels)) / np.sum(labels)
    print(f"\nClass balance:")
    print(f"  Boundary frames: {np.sum(labels):.0f}")
    print(f"  Non-boundary frames: {len(labels) - np.sum(labels):.0f}")
    print(f"  Positive class weight: {pos_weight:.2f}")
    
    # Train
    history = model.fit(
        X, y,
        epochs=epochs,
        batch_size=batch_size,
        verbose=1,
        # Note: For real training, we'd split into train/val/test
    )
    
    return model, history


def evaluate_model(model, features, labels, ground_truth_timings):
    """
    Evaluate model performance against ground truth.
    """
    print("\n📊 Evaluating Model...")
    print("=" * 60)
    
    # Reshape
    X = features.reshape(1, *features.shape)
    
    # Predict
    predictions = model.predict(X)[0]
    
    # Find predicted boundaries (peaks above threshold)
    threshold = 0.5
    predicted_boundaries = []
    
    for i in range(1, len(predictions) - 1):
        if (predictions[i] > threshold and 
            predictions[i] > predictions[i-1] and 
            predictions[i] > predictions[i+1]):
            # Local maximum above threshold = boundary
            time = i * 16 / 1000  # Convert frame to time (16ms hop)
            predicted_boundaries.append(time)
    
    print(f"Predicted boundaries: {len(predicted_boundaries)}")
    print(f"Actual words: {len(ground_truth_timings)}")
    
    # Calculate errors
    errors = []
    for wt in ground_truth_timings[:20]:  # First 20 words
        true_time = wt['start']
        
        if predicted_boundaries:
            # Find closest predicted boundary
            closest = min(predicted_boundaries, key=lambda x: abs(x - true_time))
            error = abs(closest - true_time)
            errors.append(error)
    
    if errors:
        mean_error = np.mean(errors)
        within_250ms = sum(1 for e in errors if e < 0.25) / len(errors) * 100
        within_500ms = sum(1 for e in errors if e < 0.5) / len(errors) * 100
        
        print(f"\nAccuracy Metrics:")
        print(f"  Mean Error: {mean_error:.3f}s")
        print(f"  Within 250ms: {within_250ms:.1f}%")
        print(f"  Within 500ms: {within_500ms:.1f}%")
        
        if mean_error < 0.3:
            print("\n🎉 EXCELLENT: Better than pause-based!")
        elif mean_error < 0.5:
            print("\n👍 GOOD: Comparable to pause-based")
        else:
            print("\n⚠️ FAIR: Needs more training data")
    
    return predictions, predicted_boundaries


def visualize_results(features, labels, predictions, save_path='boundary_detection_viz.png'):
    """
    Visualize features, ground truth, and predictions.
    """
    fig, axes = plt.subplots(3, 1, figsize=(14, 10))
    
    # Plot 1: MFCC features
    ax = axes[0]
    im = ax.imshow(features.T, aspect='auto', origin='lower', cmap='viridis')
    ax.set_ylabel('MFCC Coefficient')
    ax.set_title('Input Features (MFCCs)')
    plt.colorbar(im, ax=ax)
    
    # Plot 2: Ground truth labels
    ax = axes[1]
    time = np.arange(len(labels)) * 16 / 1000  # 16ms hop
    ax.plot(time, labels, 'g-', linewidth=2, label='Ground Truth')
    ax.set_ylabel('Boundary Label')
    ax.set_title('Ground Truth Word Boundaries')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    # Plot 3: Model predictions
    ax = axes[2]
    ax.plot(time, predictions.flatten(), 'b-', linewidth=2, label='Model Prediction')
    ax.axhline(0.5, color='r', linestyle='--', label='Threshold')
    ax.set_xlabel('Time (seconds)')
    ax.set_ylabel('Boundary Probability')
    ax.set_title('Model Predictions vs Threshold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    print(f"\n📊 Saved visualization to: {save_path}")
    plt.close()


def export_to_tflite(model, save_path='boundary_detector.tflite'):
    """
    Convert model to TensorFlow Lite for mobile deployment.
    """
    print("\n📦 Exporting to TensorFlow Lite...")
    print("=" * 60)
    
    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Optimize for size and latency
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]  # Use FP16 for smaller size
    
    tflite_model = converter.convert()
    
    # Save
    with open(save_path, 'wb') as f:
        f.write(tflite_model)
    
    model_size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ TFLite model saved: {save_path}")
    print(f"   Size: {model_size_mb:.2f} MB")
    
    if model_size_mb < 10:
        print("   ✅ Small enough for mobile!")
    else:
        print("   ⚠️  Consider further compression")
    
    return save_path


def main():
    """
    Proof-of-concept: Train a word boundary detector.
    """
    print("=" * 60)
    print("🧠 WORD BOUNDARY DETECTOR - TRAINING")
    print("=" * 60)
    print("\nConcept: Train a small NN to detect word boundaries")
    print("Teacher: Whisper (slow but accurate)")
    print("Student: Small CNN (fast for real-time)")
    print("Target: <5MB model, <10ms latency")
    
    # Paths
    ground_truth_file = "ground_truth_timings.json"
    audio_file = "audio/adalyn_reading_background.wav"
    
    if not Path(ground_truth_file).exists():
        print(f"\n❌ Ground truth not found: {ground_truth_file}")
        print("   Run: python get_ground_truth.py first!")
        return
    
    # Prepare data
    features, labels = prepare_training_data(ground_truth_file, audio_file)
    
    # Load ground truth for evaluation
    with open(ground_truth_file, 'r') as f:
        gt = json.load(f)
    
    # Train model
    model, history = train_model(features, labels, epochs=20)
    
    # Evaluate
    predictions, boundaries = evaluate_model(model, features, labels, gt['word_timings'])
    
    # Visualize
    visualize_results(features, labels, predictions)
    
    # Export to TFLite
    tflite_path = export_to_tflite(model)
    
    print("\n" + "=" * 60)
    print("✅ PROOF-OF-CONCEPT COMPLETE!")
    print("=" * 60)
    
    print("\n💡 Next Steps for Production:")
    print("   1. Train on larger dataset (LibriSpeech)")
    print("   2. Add background noise augmentation")
    print("   3. Use proper train/val/test split")
    print("   4. Optimize model architecture")
    print("   5. Benchmark latency on mobile device")
    print("   6. Integrate TFLite model into Flutter")
    
    print("\n📱 Flutter Integration:")
    print("   - Add tflite_flutter plugin to pubspec.yaml")
    print("   - Load model: interpreter = await Interpreter.fromAsset('boundary_detector.tflite')")
    print("   - Run inference: interpreter.run(features, output)")
    print("   - Advance word position when output > threshold")
    
    print(f"\n✅ TFLite model ready: {tflite_path}")


if __name__ == "__main__":
    main()

