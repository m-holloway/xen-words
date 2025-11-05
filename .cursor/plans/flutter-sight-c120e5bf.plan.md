<!-- c120e5bf-73c2-4d5d-a3c1-62224800bfd6 7a81789d-53c0-4d5e-b1c0-6ecc2141fd3d -->
# Flutter Sight Words App Migration

## Overview

Port the Unity sight words educational app to Flutter, maintaining all core functionality including speech recognition, 3D character animations, and visual effects. Implementation will be staged for rapid iteration.

## Architecture

### Speech Recognition Abstraction

Create `ISpeechRecognizer` interface with implementations for:

- Vosk (50MB model) - prioritize for initial implementation
- Sherpa-ONNX support structure for future

### Core Components

- **GameController**: Main game state management (Flutter state management - Provider/Riverpod)
- **WordManager**: Handle word list (64 sight words, 2 per week for 31 weeks)
- **AudioPlayer**: Play success/failure sounds and word pronunciations
- **AnimationController**: Manage character states (idle, celebrate, fail)
- **ParticleManager**: Fireworks celebrations using thermion/filament

## Implementation Stages

### Stage 1: Core 2D Functionality

- Flutter project setup with Android/iOS support
- Copy all audio assets from Unity project (`/Assets/sound/`, `/Assets/StreamingAssets/words/ruth/`)
- Implement word display UI (large text, kid-friendly)
- Speech recognition integration (Vosk first, with abstraction layer)
- Audio playback for success/failure/game complete
- Week selection UI (1-31 weeks, 2 words per week)
- Word shuffling logic
- Basic visual feedback (text color/shake for incorrect, simple celebration for correct)

**Key Files to Port Logic From:**

- `GameController.cs` - main game loop, word progression, audio coordination
- `WordController.cs` - word shake animation logic
- `NumWeeksController.cs` - week selection UI

### Stage 2: 3D Character Integration

- Add thermion/filament dependency
- Import rabbit_rig.fbx model and animations from Unity project
- Implement animation state machine:
  - Idle (default/listening state)
  - Celebrate (on correct word)
  - Fail (on incorrect word)
- Blend character rendering with Flutter UI

**Key Files for Reference:**

- `AnimationRandomizer.cs` - random celebration animation selection
- Unity Animator Controller setup

### Stage 3: Particle Effects

- Implement fireworks particle system in thermion
- Single firework on correct word (random position/color)
- Finale fireworks burst on game completion (5 fireworks with delays)
- Particle physics: initial velocity, gravity, air resistance, size/intensity curves
- Billboard rendering with gaussian texture
- Optional: particle trails, HDR/glow effects (if performant)

**Key Files for Reference:**

- `FireworksManager.cs` - launch logic, particle positioning, color randomization
- `RandomHSLGenerator.cs` - color generation

## Technical Details

### Project Structure

```
lib/
  main.dart
  models/
    word_list.dart
  services/
    speech_recognizer_interface.dart
    vosk_speech_recognizer.dart
    audio_player_service.dart
  controllers/
    game_controller.dart
  widgets/
    word_display.dart
    week_selector.dart
    character_view.dart (stage 2)
    fireworks_overlay.dart (stage 3)
  utils/
    color_generator.dart
assets/
  audio/
    sound/ (from Unity)
    words/ (from Unity)
  models/ (stage 2)
  textures/ (stage 3)
```

### Dependencies

- `flutter_vosk` or vosk FFI bindings
- `audioplayers` for sound effects
- `thermion_flutter` for 3D rendering (stage 2+)
- `provider` or `riverpod` for state management
- `permission_handler` for microphone access

### Asset Migration

Copy from Unity project:

- `/Assets/sound/*.wav` → `assets/audio/sound/`
- `/Assets/StreamingAssets/words/ruth/*.mp3` → `assets/audio/words/`
- `/Assets/ts-little-animals/Models/rabbit_rig.fbx` → `assets/models/` (stage 2)
- Animation files associated with rabbit (stage 2)

### Word List

Hardcode the 64-word list from GameController.cs (weeks 1-31), maintain shuffling logic with week-based subset selection.

### UI Considerations

- Large, readable text for pre-reading children
- Visual microphone activity indicator (RMS display)
- Simple week selector (slider or number picker)
- Touch word to hear pronunciation (like Unity implementation)
- "Well done!" completion screen with fireworks

## Platform Support

- Target: Android and iOS
- Microphone permissions handling
- Screen timeout prevention during active game
- Performance optimization for particle effects on mobile devices

### To-dos

- [ ] Create Flutter project, setup dependencies, copy audio assets
- [ ] Implement word list, shuffling, week selection logic
- [ ] Build core UI: word display, week selector, visual indicators
- [ ] Implement audio playback service for all sound effects and word pronunciations
- [ ] Integrate speech recognition with abstraction layer (Vosk implementation)
- [ ] Wire up game controller with state management, connect all components
- [ ] Add thermion dependency, setup 3D rendering context
- [ ] Import and setup rabbit model with animation state machine
- [ ] Implement fireworks particle system with physics and visual effects