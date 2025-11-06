# Build Notes - Xen Words Flutter App

## Build Issues Fixed

### Issue 1: 3D Rendering Solution (Resolved)
**Initial Approach:**
- Initially considered `model_viewer_plus` (WebView-based) and `flutter_scene` (experimental)
- `model_viewer_plus` had flickering issues during animation transitions
- `flutter_scene` required experimental native assets feature

**Resolution:**
- Chose **Thermion** (Google Filament-based) for production-ready 3D rendering
- Native rendering (Metal/Vulkan) with smooth animation transitions
- Full GLB animation support with crossfading

**Changes Made:**
- Added `thermion_dart` and `thermion_flutter` dependencies
- Implemented 3D character view using Thermion's `ViewerWidget`
- Smooth animation transitions with 0.3s crossfade
- See `3D_INTEGRATION.md` for complete implementation details

**Setup Requirements:**
- Enable native assets: `flutter config --enable-native-assets`
- Set Android NDK version to 28.2.13676358 in `android/app/build.gradle.kts`

### Issue 2: Thermion Build Requirements (Resolved)
**Error:**
```
Package(s) thermion_dart require the native assets feature to be enabled.
thermion_flutter requires Android NDK 28.2.13676358
```

**Resolution:**
1. Enable native assets: `flutter config --enable-native-assets`
2. Update `android/app/build.gradle.kts` to set `ndkVersion = "28.2.13676358"`
3. Run `flutter clean` and rebuild

**Changes Made:**
- Updated `android/app/build.gradle.kts` with required NDK version
- Native assets feature enabled (stable feature in recent Flutter versions)

### Issue 3: Gradle Symlink Error
**Error:**
```
PathExistsException: Cannot create link, path = '.../windows/flutter/ephemeral/.plugin_symlinks/audioplayers_windows'
```

**Resolution:**
- Removed the problematic symlinks directory: `rm -rf windows/flutter/ephemeral/.plugin_symlinks`
- Re-ran `flutter pub get` successfully

### Issue 4: Disk Space Constraints
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

1. **Speech Recognition**: Using Sherpa-ONNX (offline) as primary, with `speech_to_text` as fallback.

2. **3D Character**: Using Thermion for 3D rendering with smooth animation transitions. See `3D_INTEGRATION.md` for implementation details. Some animations from Unity project are not yet in the GLB file - see `MISSING_ANIMATIONS.md`.

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
6. Add more animations to GLB (see `MISSING_ANIMATIONS.md`)
7. Consider offline speech recognition (optional)
8. Test 3D character on various devices for performance

