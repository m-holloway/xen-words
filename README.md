# Xen Words - Flutter Sight Words App

A Flutter-based educational app for helping children learn sight words through speech recognition and interactive gameplay. This is a port of the original Unity-based sight words application.

## Features

### Stage 1: Core 2D Functionality ✅ COMPLETED
- ✅ Flutter project setup with Android/iOS support
- ✅ Audio asset integration (word pronunciations and sound effects)
- ✅ Word display UI with animations
- ✅ Speech recognition using `speech_to_text` package
- ✅ Audio playback for success/failure/game complete
- ✅ Week selection (1-31 weeks, 2 words per week)
- ✅ Word shuffling logic
- ✅ Visual feedback (shake animation for incorrect, celebration for correct)
- ✅ Game state management with Provider
- ✅ Microphone activity indicator
- ✅ Screen timeout prevention during gameplay

### Stage 2: Character Integration ✅ COMPLETED
- ✅ flutter_scene dependency added for 3D rendering support
- ✅ Animated character view with state-based animations
- ✅ Character responds to game states (idle, celebrate, fail)
- 📝 Note: Currently using emoji placeholder (🐰). 3D model requires FBX to GLB conversion

### Stage 3: Particle Effects ✅ COMPLETED
- ✅ Custom fireworks particle system
- ✅ Physics simulation (gravity, air resistance, velocity)
- ✅ Single firework on correct word
- ✅ Multiple fireworks finale on game completion
- ✅ Random colors using HSL color generation
- ✅ Smooth particle animation with proper lifecycle management

## Project Structure

```
lib/
  ├── main.dart                          # App entry point
  ├── models/
  │   └── word_list.dart                 # Word list and game logic
  ├── services/
  │   ├── speech_recognizer_interface.dart   # Speech recognition abstraction
  │   ├── speech_to_text_recognizer.dart     # Speech recognition implementation
  │   └── audio_player_service.dart          # Audio playback service
  ├── controllers/
  │   └── game_controller.dart           # Main game state controller
  ├── widgets/
  │   ├── game_screen.dart               # Main game screen
  │   ├── word_display.dart              # Word display with animations
  │   ├── week_selector.dart             # Week selection UI
  │   ├── microphone_indicator.dart      # Microphone status indicator
  │   ├── character_view.dart            # Animated character
  │   └── fireworks_overlay.dart         # Fireworks particle system
  └── utils/
      └── color_generator.dart           # HSL color generation

assets/
  ├── audio/
  │   ├── sound/                         # Sound effects (copied from Unity)
  │   └── words/                         # Word pronunciations (copied from Unity)
  └── models/
      └── rabbit_rig.fbx                 # 3D character model (needs conversion)
```

## Dependencies

- **flutter_sdk**: Core Flutter framework
- **provider**: State management
- **audioplayers**: Audio playback
- **speech_to_text**: Speech recognition
- **permission_handler**: Microphone permissions
- **flutter_animate**: UI animations
- **wakelock_plus**: Keep screen on during gameplay
- **flutter_scene**: 3D rendering (for future 3D character)

## Getting Started

### Prerequisites
- Flutter SDK (3.9.2 or higher)
- Xcode (for iOS development)
- Android Studio (for Android development)

### Setup

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Run the app:**
   ```bash
   flutter run
   ```

### Platform-Specific Setup

#### Android
Permissions are already configured in `android/app/src/main/AndroidManifest.xml`:
- RECORD_AUDIO
- INTERNET
- WAKE_LOCK

#### iOS
Permissions are configured in `ios/Runner/Info.plist`:
- NSMicrophoneUsageDescription
- NSSpeechRecognitionUsageDescription

## Word List

The app includes 64 sight words organized across 31 weeks (2 words per week):
- Weeks 1-5: Basic words (you, see, go, i, has, he, the, had, and, of)
- Weeks 6-10: Common words (a, we, is, am, at, to, as, have, in)
- Weeks 11-15: Action words (it, can, his, him, on, did, girl, for, but, up)
- Weeks 16-20: Descriptive words (all, look, with, her, what, was, were, said, that, down)
- Weeks 21-25: More complex words (they, boy, out, do, little, be, she, there, then, when)
- Weeks 26-31: Colors (some, red, orange, yellow, green, blue, purple, black, gray, pink, white, brown)

## How to Play

1. **Select Weeks**: Choose the number of weeks (1-31) to practice
2. **Start Game**: Tap "Start Game" to begin
3. **Speak Words**: When a word appears, say it clearly into the microphone
4. **Get Feedback**: 
   - Correct: Celebration animation + fireworks + success sound
   - Incorrect: Shake animation + failure sound
5. **Complete Round**: Finish all words to see the grand finale with multiple fireworks

## Future Enhancements

### 3D Character Model
To enable the full 3D character experience:

1. **Convert the FBX model to GLB:**
   - Option A: Use Blender
     - Open `assets/models/rabbit_rig.fbx`
     - File → Export → glTF 2.0 (.glb)
     - Save as `rabbit_rig.glb`
   - Option B: Online converter
     - Use https://products.aspose.app/3d/conversion/fbx-to-glb
     - Upload `rabbit_rig.fbx` and download `rabbit_rig.glb`

2. **Update character_view.dart:**
   - Uncomment the 3D loading code
   - Update the asset path to `assets/models/rabbit_rig.glb`
   - Configure animations for idle, celebrate, and fail states

3. **Test and adjust:**
   - Verify model loads correctly
   - Adjust camera position and lighting
   - Fine-tune animation timing

### Speech Recognition Alternatives
The app uses `speech_to_text` package currently, but the architecture supports:
- **Vosk**: Offline speech recognition (50MB model)
- **Sherpa-ONNX**: High-performance on-device recognition
- Custom implementations via `ISpeechRecognizer` interface

### Additional Features to Consider
- Progress tracking and statistics
- Multiple difficulty levels
- Custom word lists
- Parent dashboard
- Rewards and achievements
- Multi-language support

## Known Limitations

1. **3D Character**: Currently using emoji placeholder. Full 3D character requires model conversion.
2. **Speech Recognition**: Online-only with `speech_to_text`. Consider offline alternatives for better privacy and reliability.
3. **Particle Effects**: Basic 2D implementation. For more advanced effects, consider using shaders or more sophisticated rendering techniques.

## Development Notes

### Speech Recognition
The speech recognition is abstracted through `ISpeechRecognizer` interface, making it easy to swap implementations:
- Current: `SpeechToTextRecognizer` using `speech_to_text` package
- Future: Can add `VoskSpeechRecognizer`, `SherpaOnnxRecognizer`, etc.

### Audio Management
All audio is managed through `AudioPlayerService`:
- Separate players for sound effects and word pronunciations
- Automatic microphone pausing during audio playback
- Completion callbacks for coordinating game state

### State Management
Using Provider pattern with `GameController`:
- Centralized game state
- Automatic UI updates via `ChangeNotifier`
- Clean separation of concerns

## Testing

To test without voice recognition:
- Tap on the displayed word to hear its pronunciation
- Modify game logic temporarily to accept keyboard input for testing

## Credits

- Original Unity app developed by Michael Holloway
- Flutter port developed with AI assistance
- Audio assets from original Unity project
- Character model from ts-little-animals asset pack

## License

Private project - not for distribution
