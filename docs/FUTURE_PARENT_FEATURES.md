# Future Parent Features - Session Review & Coaching

## 📋 Overview
Advanced parent engagement features to enable deep session review, personalized coaching, and custom pronunciation recording.

---

## 🎯 Session Review & Playback

### Concept
Parents can review completed sessions, hearing their child's actual pronunciation attempts and seeing system responses.

### Features
1. **Session Browser**
   - List all past sessions chronologically
   - Show session metadata (date, duration, words attempted, success rate)
   - Filter by date range, week number, or mastery level
   
2. **Audio Playback**
   - Play recorded audio for each word attempt
   - Show what the system heard vs. expected word
   - Display whether attempt was accepted/rejected
   - Show multiple attempts for struggled words
   
3. **Session Summary**
   - Highlight "struggle words" for that session
   - Compare to historical performance
   - Show improvement trends
   - Identify words needing coaching

### UI Flow
```
Parent Dashboard
  → Session History Tab
    → Select Session
      → Word Grid (color-coded by success)
        → Tap Word → Hear Audio + See Recognition Result
          → Multiple attempts shown if applicable
```

---

## 👨‍👧 Parent-Child Coaching Mode

### Concept
A structured coaching session where parents can efficiently record custom pronunciations for their child's struggle words.

### Two Modes

#### Mode 1: Synchronous Coaching
Parent sits with child during live session:
- Parent hears word being attempted in real-time
- Parent sees system response
- Parent can record corrective pronunciation immediately
- Child hears parent's custom audio on next attempt

#### Mode 2: Asynchronous Review
Parent reviews session later without child:
- Parent sees session playback
- Parent hears child's attempts
- Parent records custom pronunciations
- Custom audio becomes available for future sessions

### Coaching Workflow (Asynchronous)
```
1. Parent selects "Review Session" from dashboard
2. System shows struggle words from that session
3. For each word:
   a. Play child's attempt(s)
   b. Show current help audio (if exists)
   c. Prompt: "How would you say this?"
   d. Parent records pronunciation
   e. Auto-save and move to next word
4. Session complete → Custom audio ready for next game
```

### Key Design Goals
- **Minimal UI mechanics** - flow like a session, not a settings page
- **Efficient workflow** - parent can coach 10 words in 2 minutes
- **Contextual** - parent hears child's attempt before recording
- **Progressive** - custom pronunciations improve over multiple sessions

---

## 🎤 Custom Parent Pronunciation System

### Storage
- Per-profile custom audio files
- Key: `custom_pronunciation_{profileId}_{word}.mp3`
- Fallback hierarchy:
  1. Custom parent recording
  2. TTS pronunciation (when implemented)
  3. System default

### Integration with Help Button
When child taps "Help" button:
```dart
if (customAudioExists(profileId, word)) {
  play(customAudio);
} else if (ttsAudioExists(word)) {
  play(ttsAudio);
} else {
  play(defaultAudio);
}
```

### Audio Recording
- Use same microphone permission as game
- Record in high quality (for clarity)
- Auto-normalize volume
- Max 3 seconds per word
- Option to re-record if parent not satisfied

---

## 📊 Enhanced Insights from Session Review

### Struggle Word Analysis
- **Frequency**: How often word appears in struggle lists
- **Consistency**: Does child struggle every session or improving?
- **Pattern**: Specific phoneme difficulties (future ML analysis)
- **Comparison**: How does this compare to typical learning curves?

### Parent Coaching Impact
Track effectiveness of custom pronunciations:
- Success rate before custom audio
- Success rate after custom audio
- Time to mastery comparison
- Parent engagement metrics

### Recommended Coaching
System suggests which words would benefit most from parent coaching:
- High struggle frequency
- No improvement over N sessions
- Similar words mastered (indicates isolated confusion)
- Critical sight words for reading progression

---

## 🔒 Privacy & Data Management

### Audio Storage
- All recordings stored locally (offline-first)
- Never uploaded to servers
- Deleted when profile deleted
- Parents can delete individual recordings

### COPPA Compliance
- Parental gate required for all session review features
- Clear privacy messaging
- Parent controls all recording features
- Option to disable audio recording entirely

---

## 🎨 UI/UX Mockups (High Level)

### Session Review Screen
```
╔════════════════════════════════════╗
║  Session: Nov 13, 2024 - Week 1   ║
║  Duration: 2m 15s | Score: 80%     ║
╠════════════════════════════════════╣
║                                    ║
║  Mastered (8 words)                ║
║  [the] [and] [a] [to] ...         ║
║                                    ║
║  Struggled (2 words)               ║
║  [see] ⚠️  [go] ⚠️                 ║
║                                    ║
║  [Review Struggle Words] [Coach]   ║
║                                    ║
╚════════════════════════════════════╝
```

### Coaching Flow
```
╔════════════════════════════════════╗
║  Coaching Session (2 words)        ║
║                                    ║
║  Word: "see"                       ║
║                                    ║
║  Child's Attempt:                  ║
║  [▶️ Play Audio] "thee"            ║
║                                    ║
║  Current Help Audio:               ║
║  [▶️ Play] (System TTS)            ║
║                                    ║
║  Your Pronunciation:               ║
║  [🎤 Record] [▶️ Preview]          ║
║                                    ║
║  [Skip] [Save & Next →]            ║
║                                    ║
╚════════════════════════════════════╝
```

---

## 📅 Implementation Phases

### Phase 1 (Current) ✅
- Word progress visualization
- Mastery tracking
- Color-coded word cloud
- Basic statistics

### Phase 2 (Next)
- Session history browser
- Audio recording infrastructure
- Basic playback capability

### Phase 3
- Full coaching mode
- Custom pronunciation integration
- Struggle word recommendations

### Phase 4
- ML-based phoneme analysis
- Comparative learning curves
- Advanced coaching suggestions

---

## 💡 Open Questions

1. **Audio Quality**: What quality/format for recordings? Balance clarity vs. storage
2. **Coaching Trigger**: Should system proactively suggest coaching after X failed attempts?
3. **Multiple Voices**: Allow multiple parents to record? Switch between them?
4. **Sibling Learning**: Can older siblings record pronunciations for younger ones?
5. **Teacher Integration**: Should teacher accounts have enhanced coaching tools?

---

## 🎯 Success Metrics

- **Parent Engagement**: % of parents who use coaching features
- **Coaching Effectiveness**: Improvement in mastery after custom audio
- **Time to Mastery**: Reduction in sessions needed per word
- **Parent Satisfaction**: Ratings of coaching feature usefulness
- **Child Outcomes**: Overall reading progression acceleration

---

*This document will be updated as features are designed and implemented.*

