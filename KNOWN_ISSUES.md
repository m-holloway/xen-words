# Known Issues

## Active Issues

None currently active.

---

## Resolved Issues

See git history for resolved issues.

---

## Intermittent / To Monitor

### Audio Stream Stalls (Observed: Nov 12, 2025)

**Symptoms:**
- App stops responding to speech input
- Yellow microphone indicator remains visible
- Only animation logs continue, no speech processing
- Eventually "snaps out of it" and resumes
- When it happens, user sees long gaps between recognition results

**Recent Observations:**
- Seen during testing session (sequences 334-341)
- ASR was producing unusual results ("CHRISTIE", "HULLO", "MY DEAR", etc. for "green")
- May be related to:
  - Background audio interference
  - Microphone permissions changing
  - iOS audio session interruption
  - Low audio input level triggering timeout

**Diagnostic Logging Added:**
- Audio chunk tracking (`_audioChunksReceived`)
- Gap detection (warns if >5s between chunks)
- Stream end detection (`onDone` callback)
- Logs every 50 chunks to confirm audio flow

**Current Status:**
- Monitoring - not actively reproducing
- Diagnostic logs in place to capture more info if it recurs
- See `lib/services/sherpa_recognizer.dart` lines with `_audioChunksReceived`

**If It Recurs:**
- Check terminal logs for:
  - "Audio gap detected" warnings
  - "Audio stream ended unexpectedly" messages
  - Chunk count at time of stall
- Look for iOS audio session interruptions
- Check microphone permission state
- Consider adding heartbeat/keepalive mechanism

**Related Code:**
- `lib/services/sherpa_recognizer.dart` - Audio processing and diagnostics
- `AUDIO_STALL_FIX.md` - Initial diagnostic investigation

---

## Feature Requests / Future Enhancements

See `ADAPTIVE_COACHING_IMPLEMENTATION_PLAN.md` for planned features.

