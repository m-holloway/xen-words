# Fundamental Architecture Issues

## Data Quality: ✅ GOOD
- Soft labels working correctly (σ=50ms)
- Gaussian distribution: 0.0 → 1.0 → 0.0 around boundaries
- Mean: 0.42, Std: 0.36
- Only 4/247 frames at exact 1.0 (peaks)
- 99/247 frames >0.5 (high prob zone)

## Critical Problems Found

### 1. 🚨 **Global Pooling Destroys Temporal Information**

**Current Architecture:**
```python
Conv1D → BatchNorm → Conv1D → BatchNorm → Conv1D 
    ↓
GlobalAveragePooling1D  ← 💥 DESTROYS TIME DIMENSION
    ↓
Dense → Dense → Output (single value)
```

**Problem:**
- Input: (31 frames, 64 channels) - 500ms of temporal structure
- **GlobalAveragePooling averages across ALL 31 frames**
- Output: (64,) - NO time information left!
- Model can't learn "THIS specific frame is a boundary"
- Can only learn "somewhere in this 500ms window..."

**Analogy:** 
- Like averaging 31 video frames and asking "which frame has a person?"
- You've lost ALL temporal precision!

### 2. 🚨 **MSE Loss on Soft Labels is Regression, Not Classification**

**Current Loss:**
```python
loss = mean_squared_error(predictions, soft_labels)
```

**Problem:**
- Model learns to predict AVERAGE probability
- Doesn't learn to discriminate boundaries from non-boundaries
- Just learns: "predict 0.4 everywhere, you'll be close to average!"

**Why it fails:**
- Boundary frame: label=0.9, predict=0.4 → loss=0.25
- Non-boundary: label=0.1, predict=0.4 → loss=0.09
- **Model learns to predict median value (0.4) to minimize total loss!**

### 3. 🚨 **Architecture Doesn't Match Streaming Task**

**What we need:**
```
Audio stream → [frame 0] [frame 1] [frame 2] ... [frame N]
                   ↓         ↓         ↓            ↓
Model:           [p=0.1]  [p=0.9]  [p=0.1]    [p=0.2]
                           ^ boundary detected in REAL-TIME
```

**What we have:**
```
Audio → Wait 500ms → See full window → Predict center frame
         💥 250ms latency!
```

### 4. 🚨 **Class Imbalance Not Properly Handled**

**Current approach:**
- Class weights: {0: 0.56, 1: 4.49}
- But with soft labels, there ARE no discrete classes!
- Weights are meaningless

---

## Solutions (Most to Least Impactful)

### Solution 1: **Remove Global Pooling + Use Sequence Output** 🎯

**Change architecture to:**
```python
Input: (31, 13)  # 31 frames of 13 MFCCs
    ↓
Conv1D(32, kernel=5, padding='same')  # (31, 32)
Conv1D(64, kernel=5, padding='same')  # (31, 64)
Conv1D(64, kernel=5, padding='same')  # (31, 64)
    ↓
TimeDistributed(Dense(32))            # (31, 32)
TimeDistributed(Dense(1, sigmoid))    # (31, 1)
    ↓
Take center frame: output[15]         # Single value for center frame
```

**Why this works:**
- Preserves temporal structure throughout
- Each frame gets its own embedding
- Model learns: "THIS frame is boundary, THIS frame is not"
- Still uses 500ms context for each prediction

**Expected improvement:** **10-20x better precision!**

### Solution 2: **Use Focal Loss Instead of MSE** 🎯

**Replace MSE with Focal Loss:**
```python
# Focal loss focuses on hard examples
# Down-weights easy negatives (background frames)
focal_loss(y_true, y_pred, alpha=0.25, gamma=2.0)
```

**Why this works:**
- Penalizes confident wrong predictions
- Forces model to learn boundaries, not just average
- Works GREAT with imbalanced data

**Expected improvement:** **5-10x better precision**

### Solution 3: **Tighter Soft Labels (σ=25ms)**

Already discussed - provides incremental improvement.

**Expected improvement:** **2-3x better precision**

### Solution 4: **Post-processing Peak Detection**

**Add after model inference:**
```python
from scipy.signal import find_peaks

# Model outputs: [0.1, 0.3, 0.8, 0.9, 0.7, 0.3, 0.1, ...]
peaks, _ = find_peaks(predictions, 
                      height=0.5,        # Min probability
                      distance=15)       # Min 250ms between boundaries
# peaks: [3]  ← Only the clear maximum
```

**Why this works:**
- Keeps high recall (model still detects boundaries)
- Dramatically improves precision (only take peaks)
- Fast, simple, no retraining needed

**Expected improvement:** **5-10x better precision (FREE!)**

---

## Recommendation: **Combine 1 + 2 + 4**

1. **Fix architecture** (remove global pooling) → **10x improvement**
2. **Use focal loss** → **2x additional improvement**  
3. **Add peak detection post-processing** → **2x additional improvement**

**Total expected: 40x improvement in precision!**
- Current: 2.4% precision
- After fixes: **40-60% precision** (realistic)
- Recall: 85-90% (still excellent)
- **F1: 0.50-0.60** (vs current 0.047)

---

## Quick Test: Peak Detection (No Retraining!)

Let's test Solution 4 on existing model:

```python
# Load trained model
model = keras.models.load_model('checkpoints_500/best_model.keras')

# Get predictions
predictions = model.predict(X_test)

# Current evaluation (thresholding at 0.5)
current_precision = precision_score(y_test > 0.5, predictions > 0.5)

# With peak detection
from scipy.signal import find_peaks
detected_boundaries = []
for i, pred in enumerate(predictions):
    peaks, _ = find_peaks(pred, height=0.5, distance=10)
    if len(peaks) > 0:
        detected_boundaries.append(i)

# Should see MASSIVE precision improvement!
```

This can be tested **RIGHT NOW** without any retraining!

