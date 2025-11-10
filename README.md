# Xen Words - Flutter Sight Words App

A Flutter-based educational app for helping children learn sight words through speech recognition and interactive gameplay. This is a port of the original Unity-based sight words application.

## Features

### Stage 1: Core 2D Functionality ✅ COMPLETED
- ✅ Flutter project setup with Android/iOS support
- ✅ Audio asset integration (word pronunciations and sound effects)
- ✅ Word display UI with animations
- ✅ Speech recognition using Sherpa-ONNX (offline, vocabulary-restricted)
- ✅ Audio playback for success/failure/game complete
- ✅ Week selection (1-31 weeks, 2 words per week)
- ✅ Word shuffling logic with duplicate handling
- ✅ Visual feedback (shake animation for incorrect, celebration for correct)
- ✅ Game state management with Provider
- ✅ Microphone activity indicator
- ✅ Screen timeout prevention during gameplay

### Stage 2: Character Integration ✅ COMPLETED
- ✅ 3D character model using Thermion (Google Filament engine)
- ✅ Animated character view with state-based animations
- ✅ Character responds to game states (idle, celebrate, fail)
- ✅ Smooth animation transitions with crossfading
- 📝 See `3D_INTEGRATION.md` for implementation details

### Stage 3: Particle Effects ✅ COMPLETED
- ✅ Custom fireworks particle system
- ✅ Physics simulation (gravity, air resistance, velocity)
- ✅ Single firework on correct word
- ✅ Multiple fireworks finale on game completion
- ✅ Random colors using HSL color generation
- ✅ Smooth particle animation with proper lifecycle management

### Stage 4: Advanced Rendering & UX ✅ COMPLETED
- ✅ Image-based lighting (IBL) with skybox integration
- ✅ Advanced fog system with full parameter control
- ✅ Dynamic lighting system (3-point lighting with tunable parameters)
- ✅ Real-time camera director with cinematic movements
- ✅ Live parameter tuning system (lighting, camera, rendering)
- ✅ Fully responsive layouts for all iOS/Android devices
- ✅ Personalized child name on rug with custom fonts
- ✅ Settings persistence with memory slots
- 📝 See `docs/RESPONSIVE_LAYOUT_GUIDE.md` for layout guidelines
- 📝 See `docs/SKYBOX_SETUP.md` for rendering details

## Project Structure

```
lib/
  ├── main.dart                          # App entry point
  ├── models/
  │   ├── word_list.dart                 # Word list and game logic
  │   ├── app_settings.dart              # User preferences and settings
  │   └── tunable_parameter.dart         # Director tuning parameter model
  ├── services/
  │   ├── speech_recognizer_interface.dart   # Speech recognition abstraction
  │   ├── sherpa_recognizer.dart             # Sherpa-ONNX implementation (PRIMARY)
  │   ├── speech_to_text_recognizer.dart     # Fallback implementation
  │   ├── audio_player_service.dart          # Audio playback service
  │   └── director_tuner.dart                # Live parameter tuning service
  ├── controllers/
  │   └── game_controller.dart           # Main game state controller
  ├── widgets/
  │   ├── game_screen.dart               # Main game screen
  │   ├── word_display.dart              # Word display with animations
  │   ├── week_selector.dart             # Week selection UI (responsive)
  │   ├── microphone_indicator.dart      # Microphone status indicator
  │   ├── character_view.dart            # Animated 3D character with lighting
  │   ├── splash_screen.dart             # Animated splash screen (responsive)
  │   ├── splash_character_view.dart     # 3D character for splash
  │   ├── settings_dialog.dart           # Settings UI with personalization
  │   ├── fireworks_overlay.dart         # Fireworks particle system
  │   ├── lighting_director.dart         # 3-point lighting system
  │   ├── camera_director.dart           # Cinematic camera controller
  │   ├── render_quality_director.dart   # Rendering & post-processing
  │   ├── director_overlay.dart          # Live tuning interface
  │   ├── director_report.dart           # Parameter change reporting
  │   ├── relative_touch_slider.dart     # Touch-based parameter adjustment
  │   └── goto_command.dart              # Quick parameter navigation
  └── utils/
      └── color_generator.dart           # HSL color generation

assets/
  ├── audio/
  │   ├── sound/                         # Sound effects
  │   └── words/                         # Word pronunciations
  ├── models/
  │   └── Rabbit.glb                     # 3D character model (152 animations)
  ├── skybox/                            # IBL and skybox textures
  │   ├── kloofendal_ibl.ktx            # IBL environment map
  │   └── kloofendal_skybox.ktx         # Skybox cubemap
  └── sherpa/                            # Speech recognition models
      ├── encoder-epoch-99-avg-1.onnx   # Sherpa-ONNX encoder
      ├── decoder-epoch-99-avg-1.onnx   # Sherpa-ONNX decoder
      ├── joiner-epoch-99-avg-1.onnx    # Sherpa-ONNX joiner
      └── tokens.txt                     # Token vocabulary
```

## Dependencies

### Core
- **flutter_sdk**: Core Flutter framework (3.9.2+)
- **provider**: State management

### Audio & Speech
- **audioplayers**: Audio playback for sounds and word pronunciations
- **sherpa_onnx**: Primary offline speech recognition (vocabulary-restricted)
- **record**: Audio capture for Sherpa-ONNX streaming
- **speech_to_text**: Fallback speech recognition (currently unused)
- **permission_handler**: Microphone and other permissions

### UI & Utilities
- **flutter_animate**: UI animations and transitions
- **wakelock_plus**: Screen timeout prevention during gameplay
- **shared_preferences**: Settings and tuning parameter persistence
- **google_fonts**: Custom fonts for personalization
- **path_provider**: File system access

### 3D Rendering
- **thermion_dart**: 3D rendering core (Google Filament engine)
- **thermion_flutter**: Flutter integration for Thermion

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

The app includes **61 unique sight words** organized across **31 weeks** (2 words per week, with some duplicates filtered):
- Weeks 1-5: Basic words (you, see, go, i, has, he, the, had, and, of)
- Weeks 6-10: Common words (a, we, is, am, at, to, as, have, in)
- Weeks 11-15: Action words (it, can, his, him, on, did, girl, for, but, up)
- Weeks 16-20: Descriptive words (all, look, with, her, what, was, were, said, that, down)
- Weeks 21-25: More complex words (they, boy, out, do, little, be, she, there, then, when)
- Weeks 26-31: Colors (some, red, orange, yellow, green, blue, purple, black, gray, pink, white, brown)

**Note**: The word list contains 62 entries, but "a" appears twice (weeks 6 and 7), resulting in 61 unique words. The game automatically handles duplicates to ensure each unique word appears only once per session.

## How to Play

1. **Select Weeks**: Choose the number of weeks (1-31) to practice
2. **Start Game**: Tap "Start Game" to begin
3. **Speak Words**: When a word appears, say it clearly into the microphone
4. **Get Feedback**: 
   - Correct: Celebration animation + fireworks + success sound
   - Incorrect: Shake animation + failure sound
5. **Complete Round**: Finish all words to see the grand finale with multiple fireworks

## 3D Character & Rendering

The 3D character model (`Rabbit.glb`) is fully integrated with advanced rendering features:

**✅ Implemented:**
- Native 3D rendering with Thermion (Google Filament engine)
- 152 animations with smooth transitions and crossfading
- 3-point lighting system (key, fill, rim) with live tuning
- Image-based lighting (IBL) and skybox (Kloofendal environment)
- Advanced fog system with full parameter control
- Dynamic camera director with cinematic movements
- Post-processing effects (bloom, tone mapping, anti-aliasing)
- Live parameter tuning interface (press 'd' during gameplay)

**📝 Documentation:**
- See `3D_INTEGRATION.md` for implementation details
- See `docs/SKYBOX_SETUP.md` for IBL and rendering configuration
- See `MISSING_ANIMATIONS.md` for animation catalog

**Future Enhancements:**
- Animation randomization for more variety
- Additional skybox environments
- Performance optimization for older devices

## Speech Recognition

**Current Implementation: Sherpa-ONNX (Primary)**
- ✅ Fully offline, no internet required
- ✅ Vocabulary restricted to sight words only (61 words)
- ✅ Real-time streaming recognition
- ✅ Fast endpoint detection (0.3-0.5s)
- ✅ Works on both iOS and Android

**Fallback: speech_to_text (Unused)**
- Kept in codebase for backwards compatibility
- Can be swapped via `ISpeechRecognizer` interface

**Architecture:**
- Abstracted through `ISpeechRecognizer` interface
- Easy to add new implementations (Vosk, custom models, etc.)
- Current: `SherpaRecognizer` in `lib/services/sherpa_recognizer.dart`

### Additional Features to Consider
- Progress tracking and statistics
- Multiple difficulty levels
- Custom word lists
- Parent dashboard
- Rewards and achievements
- Multi-language support

## Known Limitations

1. **Model Loading**: Sherpa-ONNX model initialization takes 10-15 seconds on first launch (blocking native call). A splash screen displays during this time.
2. **Animation Coverage**: 152 animations available, but not all Unity animations are in the GLB file - see `MISSING_ANIMATIONS.md` for details.
3. **Particle Effects**: Basic 2D particle system. For more advanced effects, consider GPU particles or shaders.
4. **Memory**: Thermion + Sherpa-ONNX models require ~200MB RAM. Tested successfully on iPhone SE and equivalent Android devices.

## Development Notes

### Speech Recognition
The speech recognition is abstracted through `ISpeechRecognizer` interface, making it easy to swap implementations:
- **Current**: `SherpaRecognizer` using Sherpa-ONNX for vocabulary-restricted offline recognition
- **Fallback**: `SpeechToTextRecognizer` (currently unused, kept for compatibility)
- **Architecture**: Supports custom implementations via `ISpeechRecognizer` interface

**Sherpa-ONNX Features:**
- Vocabulary restriction to 61 sight words only
- Real-time streaming recognition with partial results
- Fast endpoint detection for responsive UX
- Early recognition triggers (stable partial detection)
- Sequence tracking to prevent stale results

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
- Settings persistence with `SharedPreferences`

### Director System
Live parameter tuning system for development and fine-tuning:
- **Press 'd'** during gameplay to open the director interface
- Tune lighting (direction, intensity, color temperature)
- Adjust camera behavior (position, movement, transitions)
- Configure rendering (fog, bloom, shadows, tone mapping)
- Save/load presets with 4 memory slots
- Export JSON reports of all changes
- All changes persist across app sessions

### Responsive Layout
**All UI components are fully responsive** across iOS and Android devices in both portrait and landscape orientations. For detailed guidelines and best practices when creating new UI components, see:

📖 **[Responsive Layout Guide](docs/RESPONSIVE_LAYOUT_GUIDE.md)**

Key principles:
- Use `LayoutBuilder` for context-aware sizing
- Calculate sizes as percentages with `.clamp()` for bounds
- Detect landscape mode and reduce vertical spacing
- Wrap text in `FittedBox` to prevent wrapping
- Test on iPhone SE in both orientations

The guide includes:
- Before/after examples showing fixed vs responsive layouts
- Common responsive patterns and code snippets
- Testing strategy for different devices
- Quick reference checklist for all UI work

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
