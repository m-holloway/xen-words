# Speech-Text Alignment Testing Framework

## Overview

This directory contains tools for testing and optimizing speech-to-text alignment for parent reading narration. Unlike traditional STT (which transcribes unknown speech), we use **forced alignment** since we know the text in advance.

## Why Alignment vs STT?

**Our use case:**
- Parent reads a known script: "You are Adalyn, and today you went to see a glowing trail..."
- We need to track WHERE they are in real-time
- NOT what they're saying (we already know that!)

**Alignment is better because:**
- ✅ More accurate (knows expected sequence)
- ✅ More robust to background noise
- ✅ Lower latency (simpler model)
- ✅ Less computational overhead

## Approaches to Test

### 1. Forced Alignment (Gentle)
- Industry standard for audio-text alignment
- Used in subtitling, audiobooks, karaoke
- Python-based, good accuracy

### 2. Phoneme Matching + DTW
- Convert text → phoneme sequence
- Match audio phonemes to known sequence
- Dynamic Time Warping for alignment

### 3. Acoustic Feature Matching (MFCC + DTW)
- Extract Mel-Frequency Cepstral Coefficients
- Match against pre-computed MFCC of target
- Very lightweight

### 4. Hybrid VAD + Syllable Counting
- Voice Activity Detection
- Count syllables/pauses
- Heuristic word boundaries

## Directory Structure

```
alignment_testing/
├── README.md           # This file
├── requirements.txt    # Python dependencies
├── test_alignment.py   # Main testing script
├── test_audio/         # Test recordings (you provide)
│   ├── clean_reading.wav
│   ├── with_tv_background.wav
│   └── restaurant_noise.wav
├── background_noise/   # Background noise clips (you provide)
│   ├── tv_noise.wav
│   ├── restaurant.wav
│   └── conversation.wav
├── scripts/            # Known text scripts
│   └── adalyn_story.txt
└── results/            # Test results and metrics
    └── alignment_results.json
```

## Setup

```bash
cd genai/alignment_testing
pip install -r requirements.txt
```

## Usage

### 1. Provide Test Recordings

Record yourself reading the script in different conditions:
- Clean (quiet room)
- With TV in background
- In restaurant/cafe
- With conversation nearby

Save as WAV files (16kHz, mono) in `test_audio/`

### 2. Provide Background Noise

Optional: Separate noise clips for mixing tests
Save in `background_noise/`

### 3. Run Tests

```bash
# Test all approaches
python test_alignment.py --audio test_audio/clean_reading.wav

# Test with simulated background noise
python test_alignment.py --audio test_audio/clean_reading.wav --noise background_noise/tv_noise.wav --snr 10

# Batch test all recordings
python test_alignment.py --batch test_audio/
```

### 4. Analyze Results

```bash
python analyze_results.py
```

## Metrics

For each approach, we measure:
- **Accuracy**: % of words correctly aligned
- **Latency**: Time from speech to detection (ms)
- **Robustness**: Accuracy degradation with noise
- **Real-time factor**: Processing time vs audio duration
- **False positives**: Words detected incorrectly
- **False negatives**: Words missed

## Target Performance

**For production use:**
- Accuracy: >95% in clean audio, >85% with moderate noise
- Latency: <200ms from speech to UI update
- Real-time factor: <0.5 (can process 2x real-time speed)
- False positive rate: <5%

## Next Steps

1. **Collect recordings** (you)
2. **Run tests** (automated)
3. **Identify best approach** (data-driven)
4. **Port to Flutter** (implementation)
5. **Polish & deploy** (production)

## Notes

- WAV format preferred (lossless, standard)
- 16kHz sample rate (matches our STT model)
- Mono channel (easier processing)
- ~30s clips sufficient for testing

