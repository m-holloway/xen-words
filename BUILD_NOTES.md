# Build Notes - Xen Words Flutter App

## Build Issues Fixed

### Issue 1: flutter_scene Native Assets Error
**Error:**
```
Package(s) flutter_scene flutter_scene_importer require the native assets feature to be enabled.
Enable using `flutter config --enable-native-assets`.
```

**Resolution:**
1. Enabled native assets feature: `flutter config --enable-native-assets`
2. However, decided to comment out `flutter_scene` dependency since:
   - It's not actively being used yet (character view uses emoji placeholder)
   - Adds build complexity
   - Can be re-enabled when ready to implement actual 3D character

**Changes Made:**
- Commented out `flutter_scene: ^0.9.2-0` in `pubspec.yaml`
- Character view currently uses animated emoji (🐰) as placeholder
- 3D support can be added later by:
  1. Converting `rabbit_rig.fbx` to GLB format
  2. Uncommenting flutter_scene dependency
  3. Enabling native assets
  4. Updating character_view.dart to load the 3D model

### Issue 2: Gradle Symlink Error
**Error:**
```
PathExistsException: Cannot create link, path = '.../windows/flutter/ephemeral/.plugin_symlinks/audioplayers_windows'
```

**Resolution:**
- Removed the problematic symlinks directory: `rm -rf windows/flutter/ephemeral/.plugin_symlinks`
- Re-ran `flutter pub get` successfully

### Issue 3: Disk Space Constraints
**Error:**
```
No space left on device (during Gradle build)
```

**Resolution:**
- Cleaned Gradle caches: `rm -rf ~/.gradle/caches`
- Cleaned project build: `flutter clean && rm -rf build`
- Using `flutter run` instead of `flutter build apk` to reduce disk usage during development

## Current Build Status

✅ **Code Quality:**
- No linter errors
- All imports resolved
- Type-safe implementation

✅ **Dependencies:**
- All packages downloaded successfully
- Permissions configured for Android and iOS
- Audio assets copied from Unity project

✅ **Architecture:**
- Clean separation of concerns
- Abstraction layers for speech recognition
- Provider-based state management
- Modular widget structure

## Running the App

**For Development:**
```bash
flutter run
```

**For Release Build (when ready):**
```bash
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

## Known Considerations

1. **Speech Recognition**: Using `speech_to_text` package (online). For offline, consider Vosk or Sherpa-ONNX later.

2. **3D Character**: Currently using emoji placeholder. Full 3D requires:
   - Model conversion (FBX → GLB)
   - Re-enabling flutter_scene
   - Native assets feature

3. **Disk Space**: Keep an eye on available disk space. Clean caches periodically:
   ```bash
   flutter clean
   rm -rf ~/.gradle/caches
   ```

4. **Permissions**: Make sure to test microphone permissions on actual devices.

## Testing Checklist

- [ ] Test speech recognition on real device
- [ ] Verify audio playback works
- [ ] Test all word progression logic
- [ ] Verify fireworks animations
- [ ] Test week selection
- [ ] Check microphone indicator
- [ ] Test completion flow
- [ ] Verify wakelock prevents screen timeout
- [ ] Test on both Android and iOS

## Next Steps

1. Test on physical device
2. Adjust audio volumes if needed
3. Fine-tune animation timings
4. Test speech recognition accuracy
5. Consider adding progress tracking
6. Implement 3D character (optional)
7. Consider offline speech recognition (optional)

