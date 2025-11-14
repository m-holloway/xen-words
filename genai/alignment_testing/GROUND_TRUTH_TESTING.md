# Ground Truth Alignment Testing

## Overview

This testing framework generates **ground truth word timings** using Whisper's word-level timestamps, then measures how accurately our VAD+Syllable alignment performs against that ground truth.

## Why This Matters

Previous testing claimed "100% accuracy" but in-app performance shows:
- False positives everywhere
- Words matching other words (0.80 quality on everything)
- Poor real-time tracking

**We need REAL metrics** to improve the algorithm.

---

## Setup

### 1. Install Dependencies

```bash
cd genai/alignment_testing
pip install -r requirements.txt
```

This will install:
- `openai-whisper` for ground truth generation
- `librosa`, `numpy`, `scipy` for audio processing
- `matplotlib` for visualization

### 2. Prepare Audio Files

Ensure you have:
```
genai/alignment_testing/
├── audio/
│   └── adalyn_reading_background.wav  # Your test recording
├── scripts/
│   └── adalyn_story.txt               # The script text
```

---

## Usage

### Step 1: Generate Ground Truth

```bash
python get_ground_truth.py
```

**What this does:**
- Loads audio file
- Uses Whisper to transcribe with word-level timestamps
- Matches transcribed words to script
- Saves timings to `ground_truth_timings.json`

**Output:**
```
🎯 GROUND TRUTH EXTRACTION
===========================================================
🎤 Loading Whisper model...
🎧 Transcribing audio: audio/adalyn_reading_background.wav

📝 Script has 26 words
   First 10: you are adalyn and today you see a glowing trail outside

✅ Extracted 24 words from audio

📊 First 10 words with timings:
   1. 'you' at 0.52s (script: you)
   2. 'are' at 1.12s (script: are)
   3. 'adalyn' at 1.48s (script: adalyn)
   ...

💾 Saved ground truth to: ground_truth_timings.json
```

### Step 2: Test Alignment Accuracy

```bash
python test_alignment_accuracy.py
```

**What this does:**
- Runs VAD+Syllable alignment on audio
- Compares estimated word times vs ground truth
- Calculates error metrics
- Generates visualization plots

**Output:**
```
🧪 Testing VAD+Syllable Alignment...
============================================================
📊 Audio: 12.5s, 26 words in script

📈 Word-by-Word Accuracy:
Word            GT Time    Est Time   Error      Latency    
-----------------------------------------------------------------
you             0.52       0.48       0.04       -0.04      ✓
are             1.12       1.15       0.03       0.03       ✓
adalyn          1.48       1.62       0.14       0.14       ✓
and             2.20       2.45       0.25       0.25       ✓
today           2.65       3.10       0.45       0.45       ✓
...

============================================================
📊 ACCURACY STATISTICS
============================================================
Mean Error: 0.285s
Median Error: 0.220s
Std Dev: 0.182s
Max Error: 0.650s

Mean Latency: 0.124s
Median Latency: 0.095s

✅ Accuracy within thresholds:
   Within 250ms: 68.2%
   Within 500ms: 91.3%
   Within 1.0s:  100.0%

📊 Saved plot to: alignment_accuracy_results.png
```

### Step 3: Analyze Results

Open `alignment_accuracy_results.png` to see:
1. **Word Position Over Time:** VAD estimate vs ground truth markers
2. **Error Per Word:** How far off each word estimate was
3. **Error Distribution:** Histogram of errors

---

## Interpreting Results

### Accuracy Grades

| Mean Error | Grade | Status |
|------------|-------|--------|
| < 300ms | 🎉 EXCELLENT | Real-time feel, acceptable |
| 300-500ms | 👍 GOOD | Usable, minor lag |
| 500ms-1s | ⚠️ FAIR | Noticeable lag, needs improvement |
| > 1s | ❌ POOR | Major issues, unusable |

### Key Metrics

- **Mean Error:** Average time difference (want < 300ms)
- **Median Error:** Middle value (less affected by outliers)
- **Std Dev:** Consistency (want low variance)
- **Latency:** Positive = late, Negative = early
  - Positive latency: System is too slow
  - Negative latency: System is too fast (rushes ahead)

### What to Look For

**🚩 Red Flags:**
- Mean error > 500ms → Too laggy
- High std dev (> 0.5s) → Inconsistent
- Positive latency > 500ms → System too slow (increase syllable ratio)
- Negative latency < -500ms → System too fast (decrease syllable ratio)

**✅ Good Signs:**
- Mean error < 300ms
- Low std dev (< 0.2s)
- Latency near 0 (within ±200ms)
- High percentage within 250ms threshold

---

## Tuning Parameters

Based on results, adjust parameters in `VadSyllableAligner`:

### If System is Too Slow (High Positive Latency)
```python
# Decrease syllables per word
self.syllables_per_word = 1.3  # Was 1.5
```

### If System is Too Fast (High Negative Latency)
```python
# Increase syllables per word
self.syllables_per_word = 1.7  # Was 1.5
```

### If High Error Variance
```python
# Adjust energy threshold
self.energy_threshold = 0.02  # Was 0.01

# Or adjust peak distance
self.min_peak_distance = 0.20  # Was 0.15
```

---

## Iterating on the Algorithm

1. **Run baseline test** (record current metrics)
2. **Adjust ONE parameter** at a time
3. **Re-run test**
4. **Compare metrics** (did error decrease?)
5. **Repeat** until satisfied

### Example Iteration Log

```
Test 1: syllables_per_word=1.5 → Mean error: 0.450s
Test 2: syllables_per_word=1.3 → Mean error: 0.320s ✓ Better!
Test 3: syllables_per_word=1.2 → Mean error: 0.380s ✗ Worse
Test 4: syllables_per_word=1.3, min_peak_distance=0.18 → Mean error: 0.290s ✓ Best!
```

---

## Comparing Multiple Methods

Want to test different alignment approaches? Modify `test_alignment_accuracy.py`:

```python
# Add more alignment methods
def test_mfcc_dtw(audio_path, ground_truth_data):
    # ... implement MFCC+DTW ...
    pass

def test_onset_detection(audio_path, ground_truth_data):
    # ... implement onset detection ...
    pass

# Compare all methods
vad_errors = test_vad_alignment(audio, gt)
mfcc_errors = test_mfcc_dtw(audio, gt)
onset_errors = test_onset_detection(audio, gt)

# Print comparison
print(f"VAD: {np.mean(vad_errors):.3f}s")
print(f"MFCC: {np.mean(mfcc_errors):.3f}s")
print(f"Onset: {np.mean(onset_errors):.3f}s")
```

---

## Next Steps

Once you achieve acceptable accuracy in Python:

1. **Port optimized parameters** to Flutter (`VoiceAlignmentTracker`)
2. **Remove broken STT anchoring** (or fix the match quality scoring)
3. **Test in-app** with real reading
4. **Iterate** based on user feedback

---

## Troubleshooting

### "Ground truth file not found"
Run `python get_ground_truth.py` first!

### "Audio file not found"
Ensure audio file is at: `audio/adalyn_reading_background.wav`

### Whisper installation issues
```bash
pip install --upgrade openai-whisper
# Or use conda:
conda install -c conda-forge openai-whisper
```

### Poor accuracy across all methods
- Check audio quality (too noisy?)
- Verify script matches audio
- Try different test recordings

---

## Files Generated

- `ground_truth_timings.json` - Word timings from Whisper
- `alignment_accuracy_results.png` - Visualization plots
- Terminal output - Detailed metrics

---

**Let's get REAL metrics and build confidence in our approach!** 🎯📊

