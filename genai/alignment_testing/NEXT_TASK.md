# Real-Time Speech-to-Text Alignment - ML Training Project

## Project Goal

Build a **lightweight, robust neural network** that can listen to a parent reading a script (with background noise) and track their position in real-time with **<100ms latency**, enabling fluid word-by-word highlighting for the child.

---

## Current Status: Research Complete ✅

### What We Learned

**Ground Truth Testing Revealed:**
- ❌ **VAD+Syllable:** 4.3s mean error (unusable - detects 2x too many peaks)
- ⚠️ **Pause-Based:** 0.4s mean error (acceptable baseline, 70.6% within 500ms)
- ✅ **ML Approach:** Expected <200ms error, >85% accuracy (BEST path forward)

**Proof-of-Concept:**
- ✅ Trained small NN (136KB) successfully
- ✅ Fast training (~270ms/epoch)
- ✅ Architecture viable (Conv1D + LSTM/GRU + Dense)
- ⚠️ Needs real dataset (currently 1 sample)

**Key Insight:** Current "100% accuracy" VAD claims were bogus. Proper ground truth testing (using Whisper timestamps) is essential for measuring real performance.

---

## Ultimate Deployment Goal

### In-App Behavior

```
Parent reading:     "You are Adalyn..."
                      ↓
Audio stream:       [continuous 16kHz audio buffer]
                      ↓
Model inference:    [MFCC extraction → NN → boundary probability]
                      ↓
Word tracking:      currentWordIndex = 0 → 1 → 2 → ...
                      ↓
UI highlight:       "You are Adalyn..." (current word glows)
                      ⏱️ Latency: <100ms from speech to highlight
```

### Critical Requirements

1. **Real-Time Streaming** (NOT batch file processing)
   - Process audio frame-by-frame (e.g., 32ms chunks)
   - Maintain state across frames
   - Emit word boundary events immediately

2. **Minimal Latency** (<100ms target)
   - Feature extraction: <10ms
   - Model inference: <20ms
   - UI update: <20ms
   - Buffer/processing: <50ms
   - **Total:** <100ms end-to-end

3. **Mobile-Optimized**
   - Model size: <5MB (prefer <2MB)
   - CPU-only inference (no GPU required)
   - TensorFlow Lite compatible
   - Low memory footprint (<50MB)

4. **Robust to Real-World Conditions**
   - Background noise (TV, music, household)
   - Variable reading pace (pauses, hesitations)
   - Multiple speakers (different voices)
   - Accents and pronunciation variations

---

## Proposed Approach

### Phase 1: Dataset Creation

#### Data Source: LibriSpeech
- **Clean speech:** 100-1000 hours available
- **Multiple speakers:** 1000+ speakers
- **Transcribed:** Already has text alignments
- **Free & public domain**

#### Ground Truth Generation
```python
# For each LibriSpeech sample:
1. Load audio file
2. Process with Whisper (batch mode, word-level timestamps)
3. Extract ground truth: [(word, start_time, end_time), ...]
4. Create frame-level labels:
   - 0 = within/between words
   - 1 = word boundary (50ms window around word start)
```

#### Data Augmentation
```python
# Make model robust to real-world conditions:
- Background noise (Panera, TV, household, white noise)
  SNR range: 5-20dB
- Speed variations (0.9x - 1.1x)
- Pitch shift (±2 semitones)
- Room reverb (simulate different environments)
- Microphone variations (simulate phone vs tablet)
```

#### Dataset Structure
```
/librispeech_alignment/
├── train/
│   ├── audio_000001.wav (16kHz mono)
│   ├── audio_000001_features.npy (MFCC features)
│   ├── audio_000001_labels.npy (binary boundary labels)
│   └── ...
├── val/
└── test/
```

---

### Phase 2: Model Architecture

#### Design Philosophy
- **Task-specific:** Only detect word boundaries (not full ASR)
- **Lightweight:** Prioritize speed over complexity
- **Streaming-capable:** Process frame-by-frame with state
- **TFLite-compatible:** Avoid operations that don't convert

#### Architecture Options

**Option A: Temporal CNN (Simplest, Fastest)**
```python
# Pure convolutional approach
Input: MFCC features (batch, time_steps, 13)
  ↓
Conv1D(32, kernel=5, dilation=1)  # Local patterns
  ↓
Conv1D(64, kernel=5, dilation=2)  # Medium-range context
  ↓
Conv1D(64, kernel=5, dilation=4)  # Long-range context
  ↓
Conv1D(32, kernel=3)
  ↓
Dense(1, sigmoid)  # Boundary probability

Pros: Fast, TFLite-friendly, no state needed
Cons: Limited temporal context
Estimated latency: 5-10ms
```

**Option B: CNN + GRU (Balanced)**
```python
# Combine conv features with recurrent context
Input: MFCC features (batch, time_steps, 13)
  ↓
Conv1D(32, kernel=5) + BN
  ↓
Conv1D(64, kernel=5) + BN
  ↓
GRU(32, return_sequences=True)  # Temporal context
  ↓
Dense(32, relu) + Dropout(0.3)
  ↓
Dense(1, sigmoid)

Pros: Good temporal modeling, smaller than LSTM
Cons: GRU adds latency, state management
Estimated latency: 10-20ms
```

**Option C: Dilated Causal CNN (Elegant)**
```python
# WaveNet-style architecture (used in audio)
Input: MFCC features
  ↓
Causal Conv1D(32, dilation=1)
  ↓
Causal Conv1D(32, dilation=2)
  ↓
Causal Conv1D(32, dilation=4)
  ↓
Causal Conv1D(32, dilation=8)  # Receptive field: 15 frames
  ↓
Dense(1, sigmoid)

Pros: No recurrence, huge receptive field, fast
Cons: Causal padding for streaming
Estimated latency: 5-15ms
```

**Option D: Lightweight Transformer (Modern)**
```python
# Attention-based (if size permits)
Input: MFCC features
  ↓
Positional Encoding
  ↓
Multi-Head Attention (2 heads, d=64)
  ↓
Feed-Forward (128 → 32)
  ↓
Dense(1, sigmoid)

Pros: State-of-art performance
Cons: Larger model, harder TFLite conversion
Estimated latency: 15-30ms
```

#### Recommended Starting Point

**Start with Option A (Temporal CNN)**, then experiment with Option C (Dilated Causal CNN) if more context is needed. These are:
- ✅ Fast (<10ms inference)
- ✅ TFLite-friendly
- ✅ No state management needed
- ✅ Proven in audio tasks

---

### Phase 3: Training Strategy

#### Loss Function
```python
# Handle class imbalance (boundaries are rare ~5%)
loss = BinaryFocalLoss(alpha=0.25, gamma=2.0)
# OR
loss = BinaryCrossentropy(class_weight={0: 1.0, 1: 20.0})
```

#### Metrics
```python
- Binary Accuracy (baseline)
- Precision (minimize false positives)
- Recall (catch all boundaries)
- F1 Score (balance)
- Custom: Mean Error (ms) - compare predicted vs true boundary times
```

#### Optimization
```python
optimizer = Adam(lr=0.001, clipnorm=1.0)
batch_size = 32
epochs = 50 (with early stopping)

# Learning rate schedule
ReduceLROnPlateau(patience=5, factor=0.5)
```

#### Evaluation
```python
# Test on held-out data with noise
Test conditions:
- Clean speech (baseline)
- SNR 20dB (light noise)
- SNR 10dB (moderate noise)
- SNR 5dB (heavy noise)

Success criteria:
- Mean error: <100ms (target)
- Precision: >80% (few false positives)
- Recall: >90% (catch boundaries)
- Latency: <20ms per frame
```

---

### Phase 4: Streaming Inference

#### Challenge: Batch Files → Real-Time Stream

**Training:** Process entire audio files at once
**Deployment:** Process frame-by-frame as audio arrives

#### Streaming Architecture

```python
class StreamingBoundaryDetector:
    def __init__(self, model_path):
        self.model = load_tflite_model(model_path)
        self.feature_buffer = []  # Rolling window
        self.word_index = 0
        
    def process_frame(self, audio_chunk):
        """
        Process one audio chunk (e.g., 32ms)
        Returns: word_boundary (bool)
        """
        # 1. Extract features for this chunk
        mfcc_frame = extract_mfcc(audio_chunk)  # shape: (1, 13)
        
        # 2. Add to buffer (maintain context window)
        self.feature_buffer.append(mfcc_frame)
        if len(self.feature_buffer) > CONTEXT_FRAMES:
            self.feature_buffer.pop(0)
        
        # 3. Run inference on windowed features
        features = np.array(self.feature_buffer)  # shape: (context, 13)
        boundary_prob = self.model.predict(features)
        
        # 4. Detect boundary (threshold + debouncing)
        if boundary_prob > 0.5 and not self.recent_boundary:
            self.word_index += 1
            self.recent_boundary = True
            return True
        else:
            self.recent_boundary = False
            return False
```

#### Context Window Strategy

**Option 1: Fixed Context (Simpler)**
```python
# Use last N frames (e.g., 50 frames = 800ms context)
CONTEXT_FRAMES = 50
```

**Option 2: Causal Padding (Better for streaming)**
```python
# Model only looks backward (causal convolutions)
# No future context needed → true real-time
```

**Option 3: Lookahead (Lowest latency)**
```python
# Small lookahead (e.g., 5 frames = 80ms)
# Trade tiny latency for better accuracy
```

---

### Phase 5: Flutter Integration

#### TensorFlow Lite Conversion
```python
# Convert Keras model to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# Optimize for mobile
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]  # FP16 quantization

# For even smaller/faster (optional)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = representative_data_gen  # INT8 quantization

tflite_model = converter.convert()
```

#### Flutter Implementation
```dart
// 1. Add dependencies
dependencies:
  tflite_flutter: ^0.10.0
  fftea: ^1.0.0  // For MFCC extraction

// 2. Create boundary detector
class RealtimeBoundaryDetector {
  late Interpreter _interpreter;
  List<List<double>> _featureBuffer = [];
  int currentWordIndex = 0;
  final List<String> scriptWords;
  
  Future<void> initialize() async {
    _interpreter = await Interpreter.fromAsset('boundary_detector.tflite');
  }
  
  void processAudioChunk(Float32List audioChunk) {
    // Extract MFCC features
    var mfccFrame = _extractMFCC(audioChunk);
    
    // Add to buffer (maintain context)
    _featureBuffer.add(mfccFrame);
    if (_featureBuffer.length > CONTEXT_FRAMES) {
      _featureBuffer.removeAt(0);
    }
    
    // Run inference
    var input = _prepareInput(_featureBuffer);
    var output = List.filled(1, 0.0);
    _interpreter.run(input, output);
    
    // Detect boundary
    if (output[0] > 0.5) {
      currentWordIndex = min(currentWordIndex + 1, scriptWords.length - 1);
      onWordBoundary?.call(currentWordIndex);
    }
  }
  
  List<double> _extractMFCC(Float32List audioChunk) {
    // 1. Apply pre-emphasis filter
    var emphasized = _preEmphasis(audioChunk);
    
    // 2. Windowing (Hamming)
    var windowed = _applyWindow(emphasized);
    
    // 3. FFT
    var spectrum = FFT().realFft(windowed);
    
    // 4. Mel filterbank
    var melSpectrum = _melFilterbank(spectrum);
    
    // 5. Log + DCT → MFCC
    var mfcc = _computeMFCC(melSpectrum, n_mfcc: 13);
    
    return mfcc;
  }
}

// 3. Integrate with audio stream
class StoryReaderScreen extends StatefulWidget {
  @override
  _StoryReaderScreenState createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen> {
  late RealtimeBoundaryDetector _detector;
  late AudioRecorder _recorder;
  
  @override
  void initState() {
    super.initState();
    _detector = RealtimeBoundaryDetector(scriptWords: widget.storyWords);
    _detector.onWordBoundary = (index) {
      setState(() {
        _highlightWordIndex = index;
      });
    };
    
    // Start audio capture
    _recorder.start(
      onAudioChunk: (chunk) => _detector.processAudioChunk(chunk),
      sampleRate: 16000,
      chunkSize: 512,  // 32ms at 16kHz
    );
  }
}
```

#### Performance Monitoring
```dart
// Add latency tracking
class PerformanceMonitor {
  void measureLatency() {
    var t0 = DateTime.now();
    _detector.processAudioChunk(chunk);
    var t1 = DateTime.now();
    var latency = t1.difference(t0).inMilliseconds;
    
    if (latency > 100) {
      print('⚠️ High latency: ${latency}ms');
    }
  }
}
```

---

## Success Metrics

### Model Performance
- ✅ **Mean error:** <100ms (stretch goal: <50ms)
- ✅ **Precision:** >80% (few false word boundaries)
- ✅ **Recall:** >90% (catch most boundaries)
- ✅ **Inference latency:** <20ms per frame
- ✅ **Model size:** <5MB (prefer <2MB)

### Real-World Testing
- ✅ Works with background TV/music
- ✅ Handles pauses and hesitations
- ✅ Robust to different voices/accents
- ✅ Feels real-time (<100ms lag)
- ✅ Battery efficient (<5% CPU on mobile)

---

## Development Timeline

### Week 1: Dataset Preparation
- [ ] Download LibriSpeech subset (100-1000 samples)
- [ ] Batch process with Whisper (generate ground truth)
- [ ] Extract MFCC features + create labels
- [ ] Implement data augmentation pipeline
- [ ] Split train/val/test (70/15/15)

### Week 2: Model Development
- [ ] Implement Temporal CNN baseline
- [ ] Train on clean data
- [ ] Evaluate on test set
- [ ] Add noise augmentation
- [ ] Tune hyperparameters
- [ ] Experiment with architectures (dilated conv, GRU)

### Week 3: Optimization & Conversion
- [ ] Achieve <100ms mean error
- [ ] Convert to TensorFlow Lite
- [ ] Test TFLite inference speed
- [ ] Optimize (quantization if needed)
- [ ] Implement streaming inference logic

### Week 4: Flutter Integration
- [ ] Integrate TFLite model
- [ ] Implement MFCC extraction in Dart
- [ ] Build streaming detector class
- [ ] Replace current VoiceAlignmentTracker
- [ ] Test with real parent reading
- [ ] Measure end-to-end latency
- [ ] Polish UI (smooth highlighting)

---

## Open Questions & Design Decisions

### 1. Context Window Size
- **Trade-off:** More context = better accuracy, but higher latency
- **Options:** 300ms (fast), 500ms (balanced), 800ms (accurate)
- **Decision:** Start with 500ms, tune based on testing

### 2. Boundary Detection Threshold
- **Trade-off:** Low threshold = more false positives, high = missed boundaries
- **Options:** 0.4 (sensitive), 0.5 (balanced), 0.6 (conservative)
- **Decision:** Start with 0.5, add adaptive thresholding later

### 3. Feature Extraction
- **Current:** MFCC (standard, proven)
- **Alternatives:** Log mel-spectrogram, raw waveform, learned features
- **Decision:** Start with MFCC (13 coefficients), experiment if needed

### 4. Debouncing Strategy
- **Problem:** Model might predict multiple boundaries for one word
- **Options:** Cooldown period, probabilistic smoothing, HMM post-processing
- **Decision:** Simple cooldown (100ms) initially

### 5. Whisper Model Size for Ground Truth
- **Options:** tiny (fast, less accurate), base (balanced), large (slow, best)
- **Decision:** Use `base` model (good accuracy, reasonable speed)

---

## Future Enhancements

### Phase 2 Features (After MVP)
- **Confidence scoring:** Show visual confidence indicator
- **Adaptive thresholding:** Adjust based on environment noise
- **Multi-speaker support:** Identify speaker changes
- **Pronunciation modeling:** Handle mispronunciations gracefully
- **On-device fine-tuning:** Adapt to specific parent's voice

### Advanced Architectures
- **Streaming Transformer:** If latency permits
- **Multi-task learning:** Predict boundaries + word identity
- **Uncertainty estimation:** Bayesian confidence intervals
- **Attention visualization:** Show which audio frames mattered

---

## Key Learnings to Remember

1. **Ground truth testing is essential** - Don't trust subjective "feels accurate"
2. **Syllable counting doesn't work** - Too many false positives from noise
3. **Pause detection is OK baseline** - 0.4s error, 70% accuracy
4. **TFLite conversion matters** - Test early, avoid incompatible ops
5. **Streaming ≠ Batch** - Real-time requires different architecture
6. **<100ms latency is hard** - Every millisecond counts
7. **Class imbalance is real** - Boundaries are rare (~5% of frames)
8. **Data augmentation crucial** - Real world has noise

---

## Resources

### Code & Tools
- `train_boundary_detector.py` - POC training script
- `get_ground_truth.py` - Whisper ground truth generation
- `test_alignment_accuracy.py` - Evaluation framework
- `TESTING_RESULTS_SUMMARY.md` - Research findings

### Datasets
- **LibriSpeech:** http://www.openslr.org/12
- **Background noise:** AudioSet, ESC-50, DEMAND

### References
- **WaveNet (dilated conv):** https://arxiv.org/abs/1609.03499
- **Forced alignment:** Montreal Forced Aligner
- **Knowledge distillation:** https://arxiv.org/abs/1503.02531

---

## Getting Started

```bash
# 1. Set up environment
cd genai/alignment_testing
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 2. Download LibriSpeech
python download_librispeech.py --subset dev-clean --samples 100

# 3. Generate ground truth
python batch_whisper_processing.py --input librispeech/ --output ground_truth/

# 4. Train model
python train_streaming_boundary_detector.py --data ground_truth/ --epochs 50

# 5. Evaluate
python evaluate_model.py --model checkpoints/best_model.keras

# 6. Convert to TFLite
python convert_to_tflite.py --model checkpoints/best_model.keras --output boundary_detector.tflite

# 7. Test in Flutter (copy .tflite file to assets/)
```

---

## Next Steps

1. **Review this document** - Align on approach and goals
2. **Start dataset prep** - Download LibriSpeech, run Whisper
3. **Build training pipeline** - Iterate quickly on architecture
4. **Validate streaming** - Test frame-by-frame before Flutter
5. **Integrate & polish** - Make it feel magical in-app

---

**Goal: Real-time, <100ms latency, robust word tracking for magical parent-child reading experience!** ✨🎯

