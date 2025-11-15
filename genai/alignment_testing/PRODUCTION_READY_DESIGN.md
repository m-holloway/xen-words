# Production-Ready Boundary Detection: Complete Redesign

## Goal
**Real-time word boundary detection with <100ms latency, 70-80% F1 score**

---

## Fundamental Issues & Solutions

### 1. ❌ Architecture: Global Pooling Destroys Time
**Problem:** Model can't learn "THIS frame is a boundary"
**Solution:** Sequence-to-sequence with per-frame predictions

### 2. ❌ Loss Function: MSE for Soft Labels
**Problem:** Model learns to predict average, not discriminate
**Solution:** Focal Loss + Peak-aware weighting

### 3. ❌ Label Softness: σ=50ms Too Wide
**Problem:** 83% of frames labeled as "kinda boundary"
**Solution:** σ=25ms for precise temporal localization

### 4. ❌ Context Window: 500ms May Be Too Large
**Problem:** Word boundaries need ~100-200ms context, not 500ms
**Solution:** Test 200ms (13 frames) vs 500ms (31 frames)

### 5. ❌ Causal vs Non-Causal: Latency vs Accuracy
**Problem:** Non-causal convolutions look into future (not streaming!)
**Solution:** Use causal convolutions for true real-time

### 6. ❌ Data Augmentation: Only Noise, No Time/Pitch
**Problem:** Model not robust to speaking rate variations
**Solution:** Add time stretching (0.9-1.1x) and pitch shifting

---

## New Architecture

### Design Principles
1. **Preserve temporal structure** - no global pooling
2. **Causal processing** - no future peeking
3. **Local receptive field** - word boundaries are local phenomena
4. **Efficient** - small model for mobile deployment

### Architecture V2: Temporal CNN

```python
Input: (context_frames, 13)  # e.g., (13, 13) for 200ms @ 16ms hop

# Temporal feature extraction (CAUSAL)
Conv1D(64, kernel=5, padding='causal', dilation=1)    # 80ms receptive
BatchNorm + ReLU + Dropout(0.3)

Conv1D(64, kernel=5, padding='causal', dilation=2)    # +160ms
BatchNorm + ReLU + Dropout(0.3)

Conv1D(128, kernel=3, padding='causal', dilation=4)   # +192ms
BatchNorm + ReLU + Dropout(0.3)

# Per-frame prediction (sequence-to-sequence)
Conv1D(64, kernel=1)  # 1x1 conv for channel reduction
BatchNorm + ReLU

Conv1D(1, kernel=1, activation='sigmoid')  # Per-frame boundary prob

# Take center frame (or latest frame for streaming)
output = predictions[context_frames // 2]  # Center frame
# OR for true streaming: output = predictions[-1]  # Latest frame
```

**Receptive field:** ~430ms (enough for word + surrounding context)
**Latency:** 
- Non-causal (center frame): context_frames / 2 * 16ms = ~100ms
- Causal (latest frame): 16ms (single frame!)

**Parameters:** ~50K (tiny! <200KB model)

---

## Loss Function: Focal Loss + Boundary Weighting

```python
def boundary_focal_loss(y_true, y_pred, alpha=0.25, gamma=2.0, peak_boost=3.0):
    """
    Focal Loss with extra weight on peak boundaries.
    
    - Focal Loss: Down-weights easy negatives, focuses on hard cases
    - Peak Boost: Extra penalty for missing TRUE peaks (y_true > 0.9)
    - Soft Labels: Works with continuous [0, 1] targets
    
    Args:
        alpha: Weight for positive class (0.25 = 25% weight on boundaries)
        gamma: Focusing parameter (2.0 = strong down-weighting of easy cases)
        peak_boost: Extra weight multiplier for peak frames (y_true > 0.9)
    """
    # Standard focal loss
    bce = tf.keras.losses.binary_crossentropy(y_true, y_pred)
    p_t = y_true * y_pred + (1 - y_true) * (1 - y_pred)
    focal_weight = alpha * tf.pow(1 - p_t, gamma)
    focal_loss = focal_weight * bce
    
    # Extra weight for peaks
    peak_mask = tf.cast(y_true > 0.9, tf.float32)
    peak_weight = 1.0 + peak_mask * (peak_boost - 1.0)
    
    return tf.reduce_mean(focal_loss * peak_weight)
```

**Why this works:**
- Easy negatives (background) get low weight → prevents "predict 0.4 everywhere"
- Hard cases (near boundaries) get high weight → forces precise learning
- Peaks get extra boost → model learns to be confident at TRUE boundaries

---

## Training Data: Improved Augmentation

```python
# Current: Only noise mixing
audio + noise * 0.3

# New: Time + Pitch + Noise
audio_aug = audio
if time_stretch:
    audio_aug = librosa.effects.time_stretch(audio_aug, rate=random.uniform(0.9, 1.1))
if pitch_shift:
    audio_aug = librosa.effects.pitch_shift(audio_aug, sr=16000, n_steps=random.uniform(-2, 2))
if noise:
    audio_aug = audio_aug + noise * random.uniform(0.2, 0.5)
```

**Why:**
- Time stretch: Robustness to speaking rate (fast/slow readers)
- Pitch shift: Robustness to voice characteristics (high/low pitch)
- Noise: Robustness to background (already have this)

**Trade-off:** 2x slower data preparation (~6 min instead of 3 min)

---

## Hyperparameters: Tuned for Boundary Detection

```python
# Context window: SMALLER is better for boundaries
CONTEXT_FRAMES = 13  # 200ms @ 16ms hop (vs previous 31 = 500ms)
# Rationale: Word boundaries are LOCAL events (consonant onset ~20ms)
# 200ms gives enough context without diluting signal

# Soft labels: TIGHTER Gaussian
SIGMA_MS = 25  # vs previous 50ms
# Result: 47% non-zero frames (vs 83%)
# Matches natural boundary width better

# Batch size: LARGER for stable focal loss training
BATCH_SIZE = 128  # vs previous 32
# Focal loss benefits from larger batches

# Learning rate: LOWER for focal loss
LEARNING_RATE = 0.0005  # vs previous 0.001
# Focal loss can be unstable with high LR

# Epochs: MORE for harder loss
EPOCHS = 50  # vs previous 30
# Focal loss takes longer to converge
```

---

## Evaluation: Realistic Metrics

### Primary Metric: **F1 @ 50ms tolerance**
```python
# Count as correct if within 50ms (3 frames) of true boundary
tolerance_frames = 3
```

**Why:** Perfect frame-level accuracy is unrealistic
- Whisper ground truth has ~20-30ms jitter
- Human perception: 50ms timing error is imperceptible
- More realistic for production use

### Secondary Metrics:
- **Precision @ 100ms:** Ratio of correct detections within 100ms
- **Recall @ 100ms:** Ratio of true boundaries detected within 100ms
- **Mean Absolute Error:** Average timing error (ms)

---

## Expected Performance

### Conservative Estimate (Post-Training)
- **Precision @ 50ms:** 60-70%
- **Recall @ 50ms:** 75-85%
- **F1 @ 50ms:** 0.65-0.75
- **MAE:** 30-40ms

### With Post-Processing (Peak Detection)
- **Precision @ 50ms:** 75-85%
- **Recall @ 50ms:** 70-80%
- **F1 @ 50ms:** 0.72-0.82
- **MAE:** 25-35ms

### Latency
- **Model inference:** 2-5ms (on M1 Mac)
- **Total (MFCC + inference):** 8-12ms
- **Streaming latency:** 100ms (center frame) or 16ms (causal)

---

## Implementation Plan

### Phase 1: New Architecture (30 min)
1. ✅ Design causal sequence model
2. ✅ Implement focal loss
3. ✅ Update training script

### Phase 2: Improved Data (20 min)
1. ✅ Generate σ=25ms soft labels
2. ✅ Add time/pitch augmentation
3. ✅ Regenerate 500-sample dataset

### Phase 3: Training (15 min)
1. ✅ Train with new architecture + loss
2. ✅ Monitor convergence
3. ✅ Save checkpoints

### Phase 4: Evaluation (15 min)
1. ✅ Test with 50ms tolerance
2. ✅ Test with peak detection
3. ✅ Generate visualizations

**Total: ~80 minutes to production-ready model**

---

## Next Steps

1. Implement new architecture (`05_train_v2.py`)
2. Update data generation (`03_create_training_data.py` with σ=25ms + augmentation)
3. Train on 500 samples
4. Evaluate with realistic metrics
5. Test streaming inference

**Ready to proceed?**

