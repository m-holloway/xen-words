# Audio Stream Stall Detection & Fixes

## Problem Identified

The app occasionally **stops listening to audio input** for extended periods (up to 2 minutes), showing a yellow microphone indicator but not responding to speech. Eventually it "unsticks" itself.

### Symptoms from Terminal Log

```
Line 950: ✅ Continuous listening started
Lines 951-964: Only animation events, NO speech processing for ~2 minutes
Line 965: Suddenly gets result " B" (with leading space)
Line 967: Result: " B" - successful recognition resumes
```

**Root Cause:** The audio stream from the `record` package stopped emitting audio chunks, but there was no logging or detection of this failure.

---

## Fixes Applied

### 1. Added Audio Flow Monitoring

**New tracking variables:**
```dart
DateTime? _lastAudioReceived;    // When we last got audio
int _audioChunksReceived = 0;    // Count of audio chunks
```

**Benefits:**
- Detects when audio stops flowing
- Logs gaps of 5+ seconds
- Shows periodic confirmation that audio is working

### 2. Added Gap Detection Logging

```dart
// Log if we haven't received audio in a while
if (_lastAudioReceived != null) {
  final gap = now.difference(_lastAudioReceived!);
  if (gap.inSeconds >= 5) {
    AppLogger.speech.w('⚠️ Audio gap detected: ${gap.inSeconds}s since last chunk');
  }
}
```

**What to look for:**
- If you see "⚠️ Audio gap detected: 120s" → Stream stopped for 2 minutes!
- This will help identify WHEN the problem occurs

### 3. Added Periodic Flow Confirmation

```dart
// Log every 50 chunks to confirm audio is flowing
if (_audioChunksReceived % 50 == 0) {
  AppLogger.speech.t('🎤 Audio flowing: received 50 chunks (3200 bytes)');
}
```

**Expected behavior:**
- At 16kHz, 16-bit mono → ~32KB/sec
- Should see "Audio flowing" message every ~1.5 seconds
- If you DON'T see these messages → audio stream is stalled

### 4. Added Stream End Detection

```dart
onDone: () {
  AppLogger.speech.w('⚠️ Audio stream ended unexpectedly');
  if (_shouldKeepListening) {
    AppLogger.speech.w('Stream ended while still supposed to be listening!');
  }
}
```

**What this catches:**
- If the `record` package stops the audio stream unexpectedly
- Should NOT happen during normal listening
- If you see this → the audio recorder is failing

### 5. Enhanced Error Logging

```dart
onError: (error) {
  AppLogger.speech.e('⚠️ Audio stream error: $error', error: error);
  _onError?.call(error.toString());
}
```

**What to watch for:**
- Microphone permission revoked
- Audio device disconnected
- OS-level audio system issues

---

## Testing Plan

### 1. Normal Operation Test

**Expected logs:**
```
🎤 Listening started (vocabulary: 61 words)
🎤 Audio flowing: received 50 chunks (3200 bytes)    ← Every ~1.5 sec
🎤 Audio flowing: received 100 chunks (3200 bytes)
📥 RECOGNITION RESULT
```

### 2. Stall Detection Test

**If the stall happens again, you should now see:**

```
🎤 Listening started
🎤 Audio flowing: received 50 chunks              ← Last message before stall
[SILENCE - no audio messages for minutes]
⚠️ Audio gap detected: 120s since last chunk    ← This is NEW!
📥 RECOGNITION RESULT: " B"                       ← When it unsticks
```

**The gap warning will tell us:**
- HOW LONG the audio was stalled
- WHEN the stall started (relative to other logs)
- That audio chunks stopped arriving (not just recognition failure)

### 3. What the Yellow Dot Means

The yellow microphone indicator shows that `_isListening = true`, but it doesn't mean audio is actually flowing!

**New diagnostics will show:**
- ✅ **If audio is flowing:** "Audio flowing" messages every ~1.5 seconds
- ❌ **If audio is stalled:** Long gaps with no "Audio flowing" messages
- ⚠️ **If stream ended:** "Audio stream ended unexpectedly" message

---

## Root Cause Hypotheses

Based on the symptom (leading space in " B"), here are likely causes:

### Hypothesis 1: iOS Audio Session Interruption
```
Symptom: Audio stops but resumes after ~2 min
Cause: Phone call, notification, or audio session interrupted
Solution: Need to handle iOS AVAudioSession interruptions
```

### Hypothesis 2: Android Audio Focus Loss
```
Symptom: Audio stops but resumes after ~2 min
Cause: Another app took audio focus (notification sound, etc.)
Solution: Need to handle Android audio focus changes
```

### Hypothesis 3: Record Package Bug
```
Symptom: Audio stream stops emitting events
Cause: Bug in the `record` package
Solution: May need to restart the recording stream
```

### Hypothesis 4: OS Background Throttling
```
Symptom: Audio processing slows/stops when app in background
Cause: iOS/Android background processing limits
Solution: Already using wakelock_plus, but may need more
```

---

## Next Steps

### When Stall Occurs Again:

1. **Check terminal for new diagnostics:**
   ```
   ⚠️ Audio gap detected: XXs     ← How long was the gap?
   ⚠️ Audio stream ended           ← Did the stream end?
   ⚠️ Audio stream error           ← Was there an error?
   ```

2. **Note what happened before stall:**
   - Notification received?
   - App switched to background?
   - Phone call?
   - Timer fired?

3. **Check audio chunk pattern:**
   - Last "Audio flowing" message timestamp
   - When recognition resumed
   - Calculate exact gap duration

### Potential Fixes (based on diagnostics):

**If: "Audio stream ended" appears**
```dart
// Auto-restart audio stream when it ends unexpectedly
if (_shouldKeepListening) {
  await _restartAudioStream();
}
```

**If: Long gap but no stream end**
```dart
// Watchdog timer to detect and recover from stalls
Timer.periodic(Duration(seconds: 10), (timer) {
  if (_isListening && !_hasRecentAudio()) {
    await _restartAudioStream();
  }
});
```

**If: Related to audio interruptions**
```dart
// Handle iOS AVAudioSession interruptions
// Handle Android audio focus changes
// Already using wakelock_plus for screen
```

---

## Also Fixed: Added 'n' → 'in' Mapping

Per user request, added single-letter mapping:
```dart
'n': 'in'    // Now in homophone map
```

**Total mappings:** 3,518 (was 3,517)

---

## Testing Checklist

- [ ] Hot reload the app
- [ ] Test normal recognition (should see "Audio flowing" logs)
- [ ] Test "were" word with comprehensive homophones
- [ ] Test "in" word (should accept "n")
- [ ] If stall occurs, check new diagnostic logs
- [ ] Note exact timing and circumstances of stall

---

## Summary

**Before:** Audio stalls were silent - no indication of what was wrong

**After:** Comprehensive diagnostics show:
- ✅ When audio is flowing normally
- ⚠️ When audio stops (with gap duration)
- ⚠️ If the stream ends unexpectedly
- ⚠️ If errors occur

**Next time the stall happens, we'll have detailed logs to identify the root cause!**

