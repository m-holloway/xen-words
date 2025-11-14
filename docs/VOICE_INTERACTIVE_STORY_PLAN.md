# Voice-Interactive Story Reader Implementation Plan

## Overview
Enhance story reader with automatic voice recognition for seamless parent-child interaction.

## Key Features

### 1. Word Highlighting in Narration
- Parse text to find target words
- Highlight in amber boxes (inline with text)
- Track validation state (pending/listening/validated)
- Visual progression as words are spoken

### 2. Auto Voice Recognition
- Auto-start listening when narration beat loads (if target words present)
- Listen for each target word in sequence
- Validate with Sherpa recognizer
- Trigger fireworks on success
- Handle retries on failures

### 3. Child Turn Beats
- Show word in large box
- Auto-start recognition immediately
- No "Can you say..." prompt from parent
- Child speaks directly
- Celebrate success automatically

### 4. Visual States
- **Pending**: Amber box, normal opacity
- **Listening**: Amber box, glowing, mic icon pulsing
- **Validated**: Green box, checkmark, celebration particles
- **Failed**: Red shake, "Try again?" prompt

## Implementation Steps

1. Create `InteractiveWordWidget` for inline word highlighting
2. Add voice recognition state to `StoryReaderScreen`
3. Parse narration text to find/highlight target words
4. Implement auto-listen sequencing
5. Integrate fireworks celebration
6. Add retry/skip dialogs
7. Update child turn beats to auto-listen
8. Add post-story review screen

## Technical Details

### Voice Recognition Flow
```dart
// When narration beat loads:
1. Parse text for target words → ["you", "see", "go"]
2. Set currentTargetIndex = 0
3. Auto-start listening for words[0]
4. On recognition success:
   - Mark word as validated
   - Trigger fireworks
   - Move to next word (currentTargetIndex++)
   - Auto-start listening for words[1]
5. When all words validated → Show "Continue" button
```

### Word State Tracking
```dart
class WordState {
  final String word;
  final int position; // Index in text
  bool isValidated;
  bool isListening;
  
  WordValidationState get state {
    if (isValidated) return WordValidationState.validated;
    if (isListening) return WordValidationState.listening;
    return WordValidationState.pending;
  }
}
```

## Next: Implement in story_reader_screen.dart

