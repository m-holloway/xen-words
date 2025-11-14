# Quick Start Guide - Alignment Testing

## 🎯 Goal

Test lightweight alignment approaches to replace heavy STT for parent reading tracking.

## 📝 Recording Guidelines

### What to Record

**Test Audio Recordings** (save as `test_audio/*.wav`):

1. **Clean Reading** (`clean_reading.wav`)
   - Quiet room
   - Normal speaking pace
   - Read the full script once

2. **TV Background** (`with_tv.wav`)
   - TV on in background
   - Normal volume
   - Read the full script

3. **Restaurant/Cafe** (`restaurant.wav`)
   - Or record at home with conversation nearby
   - Moderate background noise
   - Read the full script

4. **Various Paces** (optional):
   - `slow_reading.wav` - Read slowly (kids might follow along)
   - `fast_reading.wav` - Read quickly
   - `with_pauses.wav` - Pause between sentences

**Background Noise Clips** (optional, save as `background_noise/*.wav`):
- `tv_noise.wav` - 30s of TV audio
- `restaurant.wav` - 30s of restaurant ambiance
- `conversation.wav` - 30s of background conversation

### Recording Settings

- **Format:** WAV (uncompressed)
- **Sample Rate:** 16000 Hz (16 kHz)
- **Channels:** Mono
- **Bit Depth:** 16-bit PCM

### How to Record (macOS/iOS)

**Option 1: QuickTime Player (Mac)**
```bash
# 1. Open QuickTime Player
# 2. File → New Audio Recording
# 3. Click record, read script, stop
# 4. File → Export As → Audio Only
# 5. Convert to WAV if needed:
ffmpeg -i recording.m4a -ar 16000 -ac 1 clean_reading.wav
```

**Option 2: Voice Memos (iPhone)**
```
1. Record using Voice Memos app
2. Share/Export recording
3. Convert using online tool or ffmpeg:
   ffmpeg -i recording.m4a -ar 16000 -ac 1 clean_reading.wav
```

**Option 3: Terminal (Mac)**
```bash
# Record directly to WAV
sox -d -r 16000 -c 1 clean_reading.wav
# Press Ctrl+C to stop
```

### Script to Read

Read this naturally, as you would to a child:

```
You are Adalyn, and today you went to see a glowing trail outside your window. 
You put on your rainbow boots and open the door. 
The sparkling path leads to a big tree. 
You follow it and find a little fairy. 
She is sitting on a flower. 
The fairy looks at you and smiles. 
She has magic dust in her hands.
```

---

## 🚀 Running Tests

### 1. Setup

```bash
cd genai/alignment_testing
pip install -r requirements.txt
```

### 2. Run Test on Single Recording

```bash
python test_alignment.py --audio test_audio/clean_reading.wav
```

### 3. Test with Simulated Noise

```bash
# Mix TV noise at 10dB SNR
python test_alignment.py \
  --audio test_audio/clean_reading.wav \
  --noise background_noise/tv_noise.wav \
  --snr 10
```

### 4. Batch Test All Recordings

```bash
# Test all WAV files in test_audio/
for audio in test_audio/*.wav; do
  echo "Testing: $audio"
  python test_alignment.py --audio "$audio"
done
```

---

## 📊 Understanding Results

The test will output:

```
RESULTS SUMMARY
================================================================

MFCC+DTW:
  Accuracy: 92.3%           ← How many words correctly aligned
  Latency: 145.2ms          ← Processing time
  Real-time factor: 0.23x   ← Can process 4x faster than real-time!
  Words aligned: 24 / 26    ← 24 out of 26 words found

Onset Detection:
  Accuracy: 88.5%
  Latency: 68.4ms           ← Faster!
  Real-time factor: 0.11x
  Words aligned: 23 / 26

VAD+Syllable:
  Accuracy: 81.2%
  Latency: 32.1ms           ← Fastest!
  Real-time factor: 0.05x
  Words aligned: 21 / 26
```

**What we're looking for:**
- ✅ Accuracy > 85% (better than current STT)
- ✅ Latency < 200ms (feels instant)
- ✅ Real-time factor < 1.0 (can process in real-time)
- ✅ Robust to noise (accuracy doesn't drop too much)

---

## 🎤 If You Don't Have ffmpeg

**Install ffmpeg:**

```bash
# macOS (Homebrew)
brew install ffmpeg

# Or download from: https://ffmpeg.org/download.html
```

**Or use online converter:**
- https://online-audio-converter.com/
- Convert to: WAV, 16000 Hz, Mono

---

## 📁 Expected Directory Structure After Recording

```
alignment_testing/
├── test_audio/
│   ├── clean_reading.wav       ← You provide
│   ├── with_tv.wav             ← You provide
│   └── restaurant.wav          ← You provide
├── background_noise/
│   ├── tv_noise.wav            ← Optional
│   └── conversation.wav        ← Optional
├── results/
│   └── alignment_results.json  ← Auto-generated
└── scripts/
    └── adalyn_story.txt        ← Already provided
```

---

## 🔬 What Happens Next

1. **You record** → test audio files
2. **I run tests** → try different alignment approaches
3. **We analyze** → which approach is best
4. **Port to Flutter** → implement winning approach
5. **Super reliable tracking!** → production ready

---

## 💡 Tips

- **Speak naturally** - don't overenunciate
- **Include mistakes** - stumbles, repeats (real-world conditions!)
- **Vary pacing** - kids might interrupt, you might pause
- **Test edge cases** - very noisy, very quiet, etc.

The more realistic your recordings, the better we can tune the system!

