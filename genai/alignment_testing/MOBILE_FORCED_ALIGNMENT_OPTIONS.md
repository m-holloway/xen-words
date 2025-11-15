# Mobile Forced Alignment: Existing Model Options

## Key Insight 💡

**You're absolutely right: We DON'T need full STT for forced alignment!**

```
Full STT:          Audio → Model → "What was said?" (unknown)
                   ↓
                   Hard problem, needs large language model

Forced Alignment:  Audio + Script → Model → "When was it said?" (known)
                   ↓
                   Easier problem, just needs acoustic matching
```

**This means we can use MUCH smaller models!**

---

## Option 1: Whisper Tiny + Custom Alignment ⭐ **RECOMMENDED**

### Specifications:
- **Model size:** 39 MB (Whisper Tiny)
- **Runs on mobile:** ✅ You've already proven this!
- **Latency:** ~100-200ms for 30s audio (batch mode)
- **Streaming latency:** ~50-100ms (with chunked processing)

### How it works:

```python
import whisper
from whisper.audio import SAMPLE_RATE, N_FRAMES

# Load Whisper Tiny (one-time, 39MB)
model = whisper.load_model("tiny")

# For forced alignment, we DON'T use full transcription
# Instead, we extract phoneme-level features from encoder

def align_to_script(audio_chunk, script_words):
    # 1. Get encoder output (mel spectrogram features)
    mel = whisper.log_mel_spectrogram(audio_chunk)
    
    # 2. Extract audio features
    audio_features = model.encoder(mel)  # (batch, time, 384)
    
    # 3. Get CTC-like probabilities from decoder
    # (Whisper has tokens, not phonemes, but close enough)
    logits = model.decoder(audio_features)  # (batch, time, 51864 tokens)
    
    # 4. Custom alignment: Match detected tokens to script
    word_positions = align_tokens_to_script(
        logits, 
        script_words,
        using="dtw"  # Dynamic Time Warping
    )
    
    return word_positions
```

### Pros:
✅ **Already runs on mobile** (you've tested it!)
✅ **No training needed** (use pre-trained Whisper)
✅ **Good accuracy** (Whisper is SOTA)
✅ **Multilingual** (bonus for future internationalization)
✅ **39MB is acceptable** for offline capability

### Cons:
⚠️ 39MB is larger than ideal (but proven to work)
⚠️ Not optimized specifically for forced alignment
⚠️ Need custom alignment code on top

### Implementation Timeline:
- **POC: 1 day** (adapt Whisper outputs for alignment)
- **Production: 3-5 days** (optimize for streaming, integrate Flutter)

---

## Option 2: Vosk (Kaldi-based) - Mobile-Optimized

### Specifications:
- **Model size:** 20-50 MB (depending on language)
- **Designed for mobile:** ✅ Specifically optimized
- **Latency:** Real-time (5-10ms per frame)
- **Built-in alignment:** ✅ Has alignment API

### How it works:

```python
from vosk import Model, KaldiRecognizer
import json

# Load Vosk model (one-time, ~40MB for English)
model = Model("vosk-model-small-en-us-0.15")

# Create recognizer with script constraint
recognizer = KaldiRecognizer(model, 16000)
recognizer.SetWords(True)  # Enable word timing

# For forced alignment, we can constrain the grammar
# This forces Vosk to only recognize script words
recognizer.SetGrammar(script_words)  # ← Key feature!

def process_audio_stream(audio_chunk):
    if recognizer.AcceptWaveform(audio_chunk):
        result = json.loads(recognizer.Result())
        return result['result']  # Word timestamps
```

### Pros:
✅ **Built for mobile** (optimized for ARM)
✅ **Real-time streaming** (native support)
✅ **Built-in forced alignment** via grammar constraints
✅ **Smaller than Whisper** (20-50MB)
✅ **Open source** (Apache 2.0 license)
✅ **No training needed**

### Cons:
⚠️ Less accurate than Whisper
⚠️ Grammar constraints may be too rigid
⚠️ Kaldi can be tricky to work with

### Implementation Timeline:
- **POC: 2-3 days** (test Vosk alignment on your audio)
- **Production: 1 week** (integrate with Flutter, optimize)

### Vosk Mobile Integration:
```dart
// Flutter integration (vosk_flutter package exists!)
import 'package:vosk_flutter/vosk_flutter.dart';

class VoskAligner {
  late VoskFlutterPlugin vosk;
  late Model model;
  
  Future<void> initialize(List<String> scriptWords) async {
    vosk = VoskFlutterPlugin.instance();
    model = await vosk.createModel('assets/vosk-model-small-en');
    
    // Set grammar to script words for forced alignment
    await vosk.setGrammar(model, scriptWords);
  }
  
  Stream<WordPosition> alignStream(Stream<Uint8List> audioStream) async* {
    await for (var chunk in audioStream) {
      var result = await vosk.recognize(model, chunk);
      if (result != null) {
        yield WordPosition(
          wordIndex: result.wordIndex,
          startTime: result.start,
          confidence: result.conf,
        );
      }
    }
  }
}
```

---

## Option 3: Silero STT (Ultra-Lightweight) 🚀

### Specifications:
- **Model size:** 9-16 MB (depending on variant)
- **Designed for:** Edge devices, mobile
- **Latency:** Real-time (<30ms per frame)
- **License:** MIT (very permissive)

### Models available:
```
silero_stt_en_v5:       16 MB  (best accuracy)
silero_stt_en_v5_jit:    9 MB  (quantized, fast)
```

### How it works:

```python
import torch
import torchaudio

# Load Silero model (one-time, 9-16MB)
model, decoder, utils = torch.hub.load(
    repo_or_dir='snakers4/silero-models',
    model='silero_stt',
    language='en',
    device='cpu'
)

# Silero outputs CTC logits (phoneme-like)
def get_phoneme_probabilities(audio):
    logits = model(audio)  # (batch, time, vocab)
    return logits

# Custom alignment
def align_to_script(audio, script_phonemes):
    logits = get_phoneme_probabilities(audio)
    # Use CTC decoder with script constraint
    word_positions = ctc_forced_align(logits, script_phonemes)
    return word_positions
```

### Pros:
✅ **Tiny!** 9-16 MB
✅ **Fast** (real-time on mobile CPU)
✅ **MIT license** (can modify freely)
✅ **PyTorch → ONNX → TFLite** conversion well-documented
✅ **Optimized for Russian + English**

### Cons:
⚠️ Less accurate than Whisper
⚠️ Need to implement custom alignment
⚠️ Limited to Russian/English
⚠️ Less battle-tested than Whisper/Vosk

### Implementation Timeline:
- **POC: 2-3 days** (test accuracy on your audio)
- **Production: 1-2 weeks** (implement alignment, optimize)

---

## Option 4: PocketSphinx (Classic Lightweight)

### Specifications:
- **Model size:** 5-15 MB (acoustic model + dictionary)
- **Legacy but proven:** Used in production for 15+ years
- **Native forced alignment:** Built-in feature
- **Runs anywhere:** C library, tiny dependencies

### How it works:

```python
from pocketsphinx import AudioFile, get_model_path

model_path = get_model_path()

# Configure for forced alignment
config = {
    'hmm': model_path + '/en-us',
    'dict': model_path + '/cmudict-en-us.dict',
    'align': True,  # ← Forced alignment mode
    'fsg': 'script.fsg'  # Finite state grammar from script
}

audio = AudioFile(audio_file=audio_path, **config)

for phrase in audio:
    # phrase.segments has word-level timestamps
    for word in phrase.seg():
        print(f"{word.word}: {word.start_frame} - {word.end_frame}")
```

### Pros:
✅ **Very small** (5-15 MB)
✅ **Built-in forced alignment**
✅ **Proven technology** (decades of use)
✅ **Low latency** (real-time)
✅ **Easy C integration** (for Flutter FFI)

### Cons:
❌ **Low accuracy** (pre-deep-learning tech)
❌ **Struggles with natural speech** (designed for clear dictation)
❌ **Not maintained** (last update 2018)
❌ **May fail on casual parent reading**

### Verdict:
**Not recommended** unless you need <10MB and can tolerate 60-70% accuracy.

---

## Comparison Matrix

| Feature | Whisper Tiny | Vosk | Silero | PocketSphinx |
|---------|--------------|------|--------|--------------|
| **Size** | 39 MB | 20-50 MB | 9-16 MB | 5-15 MB |
| **Accuracy** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **Latency** | ~100ms | <50ms | <30ms | <20ms |
| **Mobile-ready** | ✅ Proven | ✅ Optimized | ✅ Works | ✅ Native |
| **Built-in Alignment** | ❌ Need custom | ✅ Grammar | ❌ Need custom | ✅ Built-in |
| **Streaming** | ⚠️ Chunked | ✅ Native | ✅ Native | ✅ Native |
| **Ease of Use** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Training Needed** | ❌ No | ❌ No | ❌ No | ❌ No |
| **License** | MIT | Apache 2.0 | MIT | BSD |

---

## My Recommendation: **Vosk** 🎯

### Why Vosk?

1. **Goldilocks size:** 20-50MB (bigger than ideal, smaller than Whisper)
2. **Built-in forced alignment:** Grammar constraints do exactly what we need
3. **Mobile-optimized:** Designed for ARM processors
4. **Real-time streaming:** Native support, <50ms latency
5. **Battle-tested:** Used in production apps for years
6. **Flutter integration exists:** `vosk_flutter` package
7. **No training needed:** Pre-trained models work out of box

### Proof of Concept (Tonight):

```python
# Test Vosk forced alignment on your audio (30 minutes)

from vosk import Model, KaldiRecognizer
import wave

# Download model (one-time)
# wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip

model = Model("vosk-model-small-en-us-0.15")
rec = KaldiRecognizer(model, 16000)
rec.SetWords(True)

# Set script as grammar (forced alignment)
script = "you are adalyn today you see a glowing window shimmering in your backyard"
rec.SetGrammar(script.split())

wf = wave.open("audio/adalyn_reading_background.wav", "rb")
while True:
    data = wf.readframes(4000)
    if len(data) == 0:
        break
    if rec.AcceptWaveform(data):
        result = json.loads(rec.Result())
        print(result)

final = json.loads(rec.FinalResult())
print("Word timings:", final['result'])
```

**This will show us IMMEDIATELY if Vosk can handle your parent reading audio!**

---

## Alternative: Whisper Tiny if Vosk fails

If Vosk's accuracy isn't good enough (possible with noisy audio), fall back to:

**Whisper Tiny (39MB) + Custom CTC Alignment**

- Better accuracy (proven on noisy audio)
- You've already tested it on mobile
- 39MB is acceptable for offline capability
- Can extract phoneme-level features for alignment

---

## Next Steps (Recommended)

### Tonight (1 hour):
1. Test Vosk on your `adalyn_reading_background.wav`
2. Measure accuracy and latency
3. If >85% accuracy → Use Vosk
4. If <85% accuracy → Use Whisper Tiny

### This Week (2-3 days):
1. Integrate chosen model into Flutter
2. Build streaming word tracker
3. Test with live microphone input
4. Measure end-to-end latency (<100ms target)

### Production (1 week):
1. Optimize for battery life
2. Handle edge cases (pauses, child interruptions)
3. Add confidence thresholds
4. User testing with real parents

---

## Questions to Answer

1. **Is 39MB acceptable for Whisper Tiny?** (You said it runs on device)
2. **Can we test Vosk tonight?** (30 min POC to validate)
3. **What's acceptable latency?** (You said <100ms)
4. **Battery life constraints?** (How long are typical sessions?)

**Let me know and I'll build the POC with either Vosk or Whisper Tiny!** 🚀

