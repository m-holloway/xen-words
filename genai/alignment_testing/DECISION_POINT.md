# Decision Point: The Right Path Forward

## Executive Summary

**We've been solving the WRONG problem.**

- **What we built:** Generic word boundary detector (binary classification)
- **What we need:** Script-aware word position tracker (forced alignment)

**The fundamental mismatch means our current approach CANNOT succeed, no matter how much we tune it.**

---

## The Problem We're Actually Solving

### User Story:
```
As a parent reading "You are Adalyn..." to my child,
I want the app to highlight the current word I'm saying,
So my child can follow along and learn sight words.
```

### Technical Requirements:
1. **Input:** Live audio stream + Known script
2. **Output:** Current word index in script
3. **Latency:** <100ms from speech to UI update
4. **Accuracy:** >90% correct word highlights
5. **Robustness:** Works with background noise, pauses, interruptions

---

## Why Our Current Approach Fails

### Architecture Mismatch:

```
┌─────────────────────────────────────────────────────┐
│ WHAT WE BUILT                                       │
├─────────────────────────────────────────────────────┤
│ Input:  500ms audio window (NO SCRIPT!)            │
│ Model:  CNN → Dense → Sigmoid                       │
│ Output: P(boundary) for center frame                │
│ Latency: 750ms (500ms buffer + inference)          │
│                                                      │
│ Problems:                                            │
│ ❌ Doesn't know script → can't track word position  │
│ ❌ Only detects "a boundary" → can't map to words  │
│ ❌ Can't recover from errors                        │
│ ❌ Too slow for real-time                           │
│ ❌ Trained on audiobooks, not parent reading        │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ WHAT WE NEED                                        │
├─────────────────────────────────────────────────────┤
│ Input:  Audio stream + Script                      │
│ Model:  Acoustic Model → Alignment Algorithm        │
│ Output: word_index (which script word is being said)│
│ Latency: <50ms (streaming)                          │
│                                                      │
│ Benefits:                                            │
│ ✅ Script-aware → knows what should be said        │
│ ✅ Direct word index → no guessing                  │
│ ✅ Recovers from errors (uses forward constraint)   │
│ ✅ Fast enough for real-time                        │
│ ✅ Can fine-tune on parent reading data             │
└─────────────────────────────────────────────────────┘
```

### Concrete Example:

**Parent reads:** "You... are... Adalyn"

**Our boundary detector:**
```
Detects: [boundary at 0.5s, boundary at 1.2s]
Question: Which script words are these?
Answer: ¯\_(ツ)_/¯  (We don't know! We'd need extra logic to guess)
```

**Forced alignment:**
```
Script: ["You", "are", "Adalyn", "Today", ...]
Audio phonemes: [Y UW] [pause] [AA R] [pause] [AE D AH L IH N]
Alignment: word_0 @ 0.0-0.5s, word_1 @ 0.5-1.2s, word_2 @ 1.2-2.0s
Result: At 0.3s → word_index=0, At 0.8s → word_index=1, At 1.5s → word_index=2
```

---

## The Right Solution: Lightweight Forced Aligner

### High-Level Architecture:

```
┌──────────────────────────────────────────────────────────┐
│ 1. ACOUSTIC MODEL (What we train)                       │
├──────────────────────────────────────────────────────────┤
│ Input:  5-10 frames of MFCCs (80-160ms context)         │
│ Model:  Small CNN (similar to what we built)            │
│ Output: Phoneme probabilities (39 classes)              │
│         [P(/Y/), P(/UW/), P(/AA/), ...]                 │
│                                                          │
│ Training Data: LibriSpeech + Parent reading samples     │
│ Size: <5MB                                               │
│ Inference: ~5-10ms                                       │
└──────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────┐
│ 2. SCRIPT ENCODER (No training needed)                  │
├──────────────────────────────────────────────────────────┤
│ Input:  "You are Adalyn"                                 │
│ Process: Text → Words → Phonemes (CMU dict)             │
│ Output: [[Y,UW], [AA,R], [AE,D,AH,L,IH,N]]             │
└──────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────┐
│ 3. ALIGNMENT (CTC Decoding / DTW)                       │
├──────────────────────────────────────────────────────────┤
│ Input:  Stream of phoneme probabilities + Script phones │
│ Process: Find best path through audio that matches      │
│          script phoneme sequence                         │
│ Output: word_index, confidence                           │
│                                                          │
│ Constraint: Words must be spoken in script order        │
│ Recovery: If uncertain, use script to constrain         │
└──────────────────────────────────────────────────────────┘
```

### Streaming Inference (Real-time):

```python
class StreamingWordTracker:
    def __init__(self, acoustic_model, script):
        self.model = acoustic_model
        self.script_phonemes = text_to_phonemes(script)
        self.script_words = script.split()
        self.current_word_idx = 0
        self.buffer = []  # Last 10 frames
    
    def process_frame(self, audio_16ms):
        """Called every 16ms with new audio"""
        # 1. Extract MFCCs (~1ms)
        mfccs = extract_mfcc(audio_16ms)
        
        # 2. Predict phonemes (~5ms)
        phoneme_probs = self.model.predict(mfccs)
        
        # 3. Add to buffer
        self.buffer.append(phoneme_probs)
        
        # 4. Every 5 frames (80ms), align
        if len(self.buffer) >= 5:
            word_idx = self.align_to_script(
                self.buffer,
                self.script_phonemes,
                start_idx=self.current_word_idx
            )
            
            if word_idx > self.current_word_idx:
                self.current_word_idx = word_idx
            
            # Slide window
            self.buffer = self.buffer[-3:]
        
        return self.current_word_idx
    
    # Total latency: 16ms + 1ms + 5ms = 22ms ✅
```

---

## Implementation Plan

### Phase 1: Proof of Concept (2 days)

**Goal:** Validate that phoneme-based forced alignment works

**Steps:**
1. Use Whisper to get phoneme-level timestamps (it can do this!)
2. Build simple CTC alignment on top
3. Test on your parent reading samples
4. Measure accuracy and latency

**Success criteria:**
- >85% word tracking accuracy
- <200ms latency (good enough for POC)

### Phase 2: Train Lightweight Acoustic Model (3-5 days)

**Goal:** Replace Whisper with tiny, fast model

**Steps:**
1. Download LibriSpeech with phoneme alignments
2. Train small CNN to predict 39 phoneme classes
   - Architecture: Similar to our current model
   - Output: 39-class softmax instead of binary
   - Size target: <5MB
3. Integrate CTC decoder
4. Test on device (iPhone/Android)

**Success criteria:**
- Model size: <5MB
- Inference: <10ms per frame
- Accuracy: >80% on LibriSpeech test

### Phase 3: Domain Adaptation (2-3 days)

**Goal:** Optimize for parent-child reading

**Steps:**
1. Record 10-20 parents reading children's books
2. Add background noise, interruptions
3. Fine-tune acoustic model on this data
4. Test with real parents and kids

**Success criteria:**
- Accuracy: >90% on parent reading
- Robustness: Works with moderate background noise
- User testing: Parents rate 4+/5

### Phase 4: Flutter Integration (3-5 days)

**Goal:** Production-ready widget

**Steps:**
1. Port model to TFLite
2. Integrate with existing audio pipeline
3. Build word highlighting UI
4. Optimize for <100ms end-to-end latency

**Success criteria:**
- Latency: <100ms (p95)
- Battery: <5% drain per 10-minute session
- Works offline

**Total: 2-3 weeks to production**

---

## Alternative: Use Existing Solution

### Option: Wav2Vec2 Forced Alignment

**Pros:**
- Battle-tested, state-of-the-art accuracy
- Pre-trained models available
- Python library: `transformers`

**Cons:**
- Large model (300MB+)
- Requires GPU for real-time
- May need cloud processing

**When to use:**
- If we can accept cloud dependency
- If we need production-ready TODAY
- If model size isn't a constraint

**Implementation:**
```python
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor
import torchaudio

# Load model (one-time)
processor = Wav2Vec2Processor.from_pretrained("facebook/wav2vec2-base-960h")
model = Wav2Vec2ForCTC.from_pretrained("facebook/wav2vec2-base-960h")

# Inference
audio, sr = torchaudio.load("parent_reading.wav")
inputs = processor(audio, sampling_rate=sr, return_tensors="pt")
logits = model(inputs.input_values).logits

# CTC decode with script constraint
from pyctcdecode import build_ctcdecoder
decoder = build_ctcdecoder(vocab, kenlm_model=None)
word_timestamps = decoder.decode_with_timestamps(logits, script_text)
```

**Timeline: 2-3 days to working prototype**

---

## My Strong Recommendation

**Do Phase 1 (POC with Whisper) FIRST** - 2 days of work

**Why:**
1. Validates the entire approach end-to-end
2. Proves that forced alignment solves our problem
3. Gives us working demo to show stakeholders
4. Lets us test UX before investing in lightweight model
5. Can use Whisper as fallback if lightweight model isn't ready

**Then decide:**
- If Whisper is fast enough → Ship it! (with cloud option)
- If we need smaller/faster → Do Phase 2-3
- If timeline is tight → Use Wav2Vec2 cloud solution

---

## Questions for You

1. **Do you agree our current boundary detection approach is fundamentally wrong?**
   - We can't track word positions without script awareness

2. **Are you comfortable pivoting to forced alignment?**
   - It's the industry-standard solution for this exact problem

3. **What's your timeline?**
   - Need production in 1 week → Use Wav2Vec2 cloud
   - Have 2-3 weeks → Build lightweight solution
   - Research phase → Do POC with Whisper first

4. **Offline vs Cloud?**
   - 100% offline → Need lightweight model (Phase 2-4)
   - Cloud OK for premium → Can use Wav2Vec2 today

5. **Can you record sample data?**
   - 10-20 parents reading children's books
   - Needed for Phase 3 (domain adaptation)

---

## Next Action

**I recommend: Let's build the Whisper POC (Phase 1) RIGHT NOW.**

It will take ~2 hours and prove whether forced alignment is the right approach.

If you agree, I'll:
1. Build phoneme-based forced aligner using Whisper
2. Test on your `adalyn_reading_background.wav`
3. Show you frame-by-frame word tracking
4. Measure accuracy against ground truth

**Then you'll see it working and we can decide the production path.**

Sound good?

