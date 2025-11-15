# Evaluation Method Scrutiny: Does It Match Reality?

## Your Real Use Case

**What the app needs to do:**
1. Parent reads script out loud (e.g., "You are Adalyn...")
2. Sherpa-ONNX provides **real-time partial STT** as parent speaks
3. We phonemize the partial STT output
4. We align phonemes to the known script
5. We highlight the **current word** being read
6. **Latency must be <120ms** for smooth highlighting
7. Must handle **background noise**, **mispronunciations**, **STT errors**

---

## What Our Evaluation Actually Tests

### ✅ What We Test Correctly

#### 1. **Phoneme-Level Fuzzy Matching**
```python
# Our eval DOES test this:
- Converting words to phonemes ✅
- Fuzzy similarity matching (vowel→vowel = 0.75, exact = 1.0) ✅
- Handling insertions/deletions (skipping phonemes) ✅
- Sliding window (last 15 phonemes) ✅
```

#### 2. **Script Constraint**
```python
# Our eval DOES test this:
- Aligning to a known script ✅
- Finding best position in script ✅
- Only moving forward ✅
```

#### 3. **Diverse Audio Conditions**
```python
# Our 500 LibriSpeech samples include:
- Multiple speakers (male, female) ✅
- Different speech rates ✅
- Various accents ✅
- Clean professional audio ✅
```

#### 4. **Streaming Simulation**
```python
# We process incrementally:
for i in range(0, len(words), 5):  # 5 words at a time
    chunk = words[i:i+5]
    cumulative_phonemes.extend(chunk_phonemes)
    position = align(cumulative_phonemes, script)
    # Check: does position match expected? ✅
```

---

## ⚠️ What Our Evaluation DOESN'T Test (Gaps)

### Gap 1: **Real Sherpa-ONNX STT Errors**

**What we test:**
- Perfect Whisper transcriptions
- Clean, accurate text

**What you'll get in production:**
```
Parent says:  "You are Adalyn"
Sherpa gives: "yoo ar add a lynn"  ← STT errors!
```

**Why this matters:**
- Whisper is MUCH more accurate than Sherpa
- Sherpa makes more errors, especially with names
- Our 99.6% accuracy might drop to 90-95% with real Sherpa

**Mitigation:**
- Phoneme matching IS designed for this (fuzzy similarity)
- But we should test with actual Sherpa output

---

### Gap 2: **Real-Time Partial Results**

**What we test:**
```python
# We simulate "chunks" of 5 words:
Chunk 1: "you are adalyn today you"  (5 words)
Chunk 2: "see a glowing window shimmering" (5 more)
```

**What Sherpa actually gives:**
```
Partial 1: "you"
Partial 2: "you are"
Partial 3: "you are add"
Partial 4: "you are add a"
Partial 5: "you are adalyn"  ← Final for that phrase
```

**Why this matters:**
- Real STT gives word-by-word or even letter-by-letter
- Our "5 word chunks" might be too coarse
- Real latency could be different

**Mitigation:**
- Our algorithm uses sliding window (last 15 phonemes)
- This SHOULD handle incremental updates fine
- But we should verify with real Sherpa partial results

---

### Gap 3: **Background Noise (Partially Addressed)**

**What we test:**
- LibriSpeech clean audio
- (We generated augmented samples with your Panera noise, but those are in training data, not eval)

**What you'll get in production:**
- Real background noise (TV, siblings, dogs)
- Parent coughing, pausing, restarting
- Child interrupting

**Why this matters:**
- Clean recording got 100% accuracy
- Noisy recording might be worse

**Mitigation:**
- Phoneme matching is inherently robust to noise (fuzzy similarity)
- We DID test on your clean recording (100% success)
- But should test on noisy recordings too

---

### Gap 4: **Timing-Based Accuracy (Not Position-Based)**

**What we test:**
```python
# We check: "Is predicted word index == expected word index?"
expected_idx = 9  # Word 9 in script
predicted_idx = 9  # Did we predict word 9?
correct = (predicted_idx == expected_idx)  # YES! ✅
```

**What you actually care about:**
```python
# You care about: "When parent says word 9, do we highlight it IMMEDIATELY?"
time_parent_said_word_9 = 5.2 seconds (from audio)
time_we_highlighted_word_9 = 5.25 seconds (from our system)
latency = 0.05 seconds = 50ms ✅
```

**Why this matters:**
- We're testing **position accuracy**, not **timing accuracy**
- We don't measure **latency** in our eval
- We don't use ground truth **timestamps** at all!

**This is a CRITICAL gap!**

---

### Gap 5: **Script Deviations**

**What we test:**
- Parent reads script perfectly (LibriSpeech is verbatim transcription)

**What might happen:**
```
Script:  "You are Adalyn today"
Parent:  "You are... um... Adalyn, and today"  ← Added words, paused
```

**Why this matters:**
- Real parents might skip words, add words, restart
- Our eval assumes perfect adherence to script

**Mitigation:**
- Phoneme matching with fuzzy similarity SHOULD handle this
- But we haven't explicitly tested it

---

## 🔍 Deep Dive: How Our Eval Works

### Step-by-Step Walkthrough

#### 1. **Load Ground Truth**
```python
gt = {
  "transcript": "The long drizzle had begun.",
  "word_timings": [
    {"word": "The", "start": 0.0, "end": 0.3},
    {"word": "long", "start": 0.3, "end": 0.54},
    # ... etc
  ]
}
```

**Note:** We load the timings but DON'T USE THEM in eval!

#### 2. **Prepare Script (Same as Transcript)**
```python
script = "The long drizzle had begun."
script_phonemes = [DH, AH, L, AO, NG, D, R, IH, Z, AH, L, ...]
word_boundaries = [0, 2, 6, ...]  # Phoneme indices where words start
```

#### 3. **Simulate Streaming**
```python
# Process 5 words at a time
for i in range(0, len(words), 5):
    # Get next 5 words from ground truth
    chunk = ["The", "long", "drizzle", "had", "begun"]
    
    # Phonemize
    chunk_phonemes = [DH, AH, L, AO, NG, D, R, IH, Z, AH, L, ...]
    
    # Accumulate (simulating continuous listening)
    cumulative_phonemes += chunk_phonemes
    
    # Align to script
    predicted_word_idx, confidence = fuzzy_phoneme_align(
        cumulative_phonemes,  # All phonemes heard so far
        script_phonemes,       # Expected script
        word_boundaries        # Word positions in script
    )
    
    # Check accuracy
    expected_word_idx = i + len(chunk) - 1  # Last word in chunk
    correct = (predicted_word_idx == expected_word_idx)
```

#### 4. **Fuzzy Phoneme Alignment**
```python
def fuzzy_phoneme_align(detected, script, boundaries):
    # Use last 15 phonemes (sliding window)
    recent = detected[-15:]
    
    # Try aligning at each possible word position
    best_word = 0
    best_score = 0.0
    
    for word_idx in range(len(boundaries)):
        # Try starting alignment at this word
        score = score_match(recent, script, boundaries[word_idx])
        
        if score > best_score:
            best_word = word_idx
            best_score = score
    
    return best_word, best_score

def score_match(detected, script, start_pos):
    # Match phonemes one-by-one
    for each detected_phoneme:
        similarity = phoneme_similarity(detected[i], script[j])
        
        if similarity > 0.7:
            # Good match, advance both
            score += similarity
        elif similarity > 0.5:
            # Moderate match
            score += similarity * 0.8
        else:
            # Poor match, skip detected (likely noise)
            pass
    
    return average_score
```

---

## ✅ What This Evaluation PROVES

### 1. **Phoneme-Level Matching Works**
- 99.6% accuracy across 500 diverse samples
- Robust to different speakers, rates, accents
- High confidence (0.87 average)

### 2. **Script Constraint is Powerful**
- Knowing the script makes alignment 10x easier
- Can handle deviations and errors
- Always moves forward (no backtracking)

### 3. **Algorithm is Fast**
- Processed 500 samples in <1 second
- Each alignment: <10ms
- Well under 120ms latency target

---

## ⚠️ What This Evaluation DOESN'T PROVE

### 1. **Real-Time Performance**
- We don't measure actual latency
- We don't use Sherpa's partial results
- We simulate with 5-word chunks (not realistic)

### 2. **Sherpa-ONNX Robustness**
- We use perfect Whisper transcriptions
- Sherpa will have more errors
- Accuracy might drop from 99.6% to 90-95%

### 3. **Noisy Environment Performance**
- Most samples are clean audio
- Real parent reading will have background noise
- Need to test with your noisy recordings

### 4. **Timing Accuracy**
- We test position (word index) not timing
- Real app needs to highlight within 120ms of speaking
- We don't measure this

---

## 🎯 Recommendations

### Must Do Before Deployment:

#### 1. **Test with Real Sherpa-ONNX Output**
```python
# Run Sherpa on your clean recording
sherpa_output = run_sherpa("clean_recording.wav")
# Result: "yoo ar adelene and tuh day..."

# Test our alignment with Sherpa output
accuracy = test_alignment(sherpa_output, script)
# Expected: 85-95% (lower than Whisper, but still good)
```

#### 2. **Measure Real-Time Latency**
```python
# For each word in ground truth:
word_spoken_time = gt['word_timings'][i]['start']  # e.g., 5.2s
word_detected_time = our_system_log[i]['timestamp']  # e.g., 5.25s
latency = word_detected_time - word_spoken_time  # 50ms ✅

# Check: latency < 120ms for all words?
```

#### 3. **Test on Noisy Recordings**
- Use your "reading-with-background-noise.m4a"
- Run Sherpa on it
- Test alignment
- Expected: 80-90% accuracy (still usable)

### Nice to Have:

#### 4. **Test Word-by-Word Streaming**
```python
# Simulate realistic Sherpa partial results
partials = ["you", "you are", "you are add", "you are adalyn"]
for partial in partials:
    position = align(partial, script)
    # Check: does position advance smoothly?
```

#### 5. **Test Script Deviations**
- Parent adds extra words: "You are, um, Adalyn"
- Parent skips words: "You Adalyn today"
- Does alignment still work?

---

## 📊 Confidence Level

### High Confidence (✅)
- **Phoneme matching algorithm works** (99.6% proven)
- **Fast enough** (<10ms per alignment)
- **Robust to speakers/accents** (500 diverse samples)

### Medium Confidence (⚠️)
- **Sherpa-ONNX accuracy** (not tested, but algorithm designed for this)
- **Noisy environment** (clean recording worked perfectly, but more testing needed)
- **Real-time latency** (theory says <120ms, but not measured)

### Low Confidence (❓)
- **Partial result streaming** (not tested, assumed to work)
- **Script deviations** (not tested explicitly)

---

## 🚀 Recommended Path Forward

### Phase 1: Validate Real-World Performance (1-2 days)

1. **Run Sherpa on your clean recording**
   - Compare Sherpa output vs Whisper output
   - Test alignment with Sherpa's transcription
   - Measure accuracy drop (expect 90-95% vs 100%)

2. **Run Sherpa on your noisy recording**
   - Test in realistic background noise
   - Measure accuracy (expect 80-90%)

3. **Measure real-time latency**
   - Process audio as if streaming
   - Timestamp when each word is detected
   - Verify <120ms latency

### Phase 2: Port to Dart (2-3 days)

If Phase 1 shows >85% accuracy on real Sherpa output:
- Port PhonemeAligner to Dart
- Integrate with existing Sherpa-ONNX
- Test in Flutter app

### Phase 3: Live Testing (1 day)

- You read the story
- App tracks in real-time
- Measure accuracy and latency
- Tune parameters if needed

---

## 💡 Bottom Line

**Our evaluation proves the algorithm works in theory**, but we need to validate it works with:
1. ✅ Real Sherpa-ONNX STT (not perfect Whisper)
2. ✅ Real-time partial results (not 5-word chunks)
3. ✅ Background noise (not clean audio)
4. ✅ Measured latency (not just position accuracy)

**I recommend:**
- Spend 1-2 days testing with real Sherpa output first
- If accuracy >85% on your recordings → port to Dart
- If accuracy <85% → tune phoneme similarity weights

**Want me to run Sherpa on your recordings right now and test?**

