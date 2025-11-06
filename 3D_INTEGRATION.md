# 3D Character Integration - Thermion Implementation

## Overview

This document describes the 3D character integration using **Thermion**, a production-ready Flutter package built on Google's Filament rendering engine. The character (`Rabbit.glb`) is displayed in the `CharacterView` widget, positioned in the bottom-right corner during gameplay.

## Why Thermion?

After evaluating multiple 3D rendering solutions, Thermion was chosen for the following reasons:

### ✅ Advantages

1. **Production-Ready**: Built on Google's Filament engine (mature, battle-tested)
2. **Native Performance**: Metal (iOS) and Vulkan (Android) rendering - no WebView overhead
3. **Smooth Animations**: Proper animation blending and crossfading for seamless transitions
4. **Full GLB Support**: Complete support for glTF/GLB models with skeletal animations
5. **Cross-Platform**: iOS, Android, macOS, Windows, Linux, Web
6. **Game-Ready**: Designed for interactive 3D applications like games
7. **Good Documentation**: Active development with clear API

**Note**: Thermion does require the native assets feature to be enabled (`flutter config --enable-native-assets`), but this is a stable feature in recent Flutter versions.

### ❌ Why Not Other Options?

**model_viewer_plus:**
- WebView-based, causing flicker/disappearing during animation transitions
- No smooth animation blending
- Performance overhead from WebView isolation

**flutter_scene:**
- Still in preview (v0.0.2)
- Limited maturity and community adoption
- Similar native assets requirement as Thermion

**Unity Integration:**
- Massive app size increase
- Overkill for a simple character widget
- Complex build process

## Current Implementation

### Status: ✅ COMPLETE

- ✅ **Model Loaded**: `assets/models/Rabbit.glb` 
- ✅ **Integration**: `lib/widgets/character_view.dart` uses Thermion `ViewerWidget`
- ✅ **Animations**: Smooth transitions between game states
- ✅ **UI Integration**: Embedded in `GameScreen` Stack (bottom-right, 180x180)

### Dependencies

```yaml
dependencies:
  thermion_dart: ^0.3.4+1
  thermion_flutter: ^0.3.4
```

### Setup Requirements

1. **Enable Native Assets** (required):
   ```bash
   flutter config --enable-native-assets
   ```

2. **Android NDK Version** (required):
   - Thermion requires Android NDK 28.2.13676358 or higher
   - Set in `android/app/build.gradle.kts`:
     ```kotlin
     android {
         ndkVersion = "28.2.13676358"
     }
     ```

## Animation System

### Game State to Animation Mapping

The character responds to game states with appropriate animations:

| Game State | Animation | Description |
|------------|-----------|-------------|
| `playing` | "Happy Idle" | Cheerful idle animation during gameplay |
| `celebrating` | "Victory Idle" | Celebration animation on correct word |
| `failing` | "Defeat" | Failure animation on incorrect word |
| `completed` | "Locking Hip Hop Dance" | Energetic dance on game completion |
| `initial` | "Idle" | Default idle animation |

### Animation Features

- **Smooth Transitions**: 0.3 second crossfade between animations
- **Looping**: All animations loop appropriately
- **Fallback Handling**: If an animation name doesn't exist, falls back to available animations
- **Error Handling**: Graceful error handling with console logging

### Available Animations in GLB

The `Rabbit.glb` file includes the following animations:

**Idle:**
- "Idle"
- "Happy Idle" ✅ (used for playing state)
- "Dwarf Idle"
- "Standing Idle 04"
- "Standing W_Briefcase Idle"

**Celebrations:**
- "Victory Idle" ✅ (used for celebrating state)

**Failures:**
- "Defeat" ✅ (used for failing state)
- "Fall Flat"

**Dances/Completion:**
- "Locking Hip Hop Dance" ✅ (used for completed state)
- "Wave Hip Hop Dance"

**Other:**
- Dodging, Dying Backwards, Falling Back Death
- Fast Run, Slow Run, Running, Walking
- Jump, Jumping
- Kicking, Inside Crescent Kick, Side Kick
- Punching, One Hand Club Combo
- Shoulder Hit And Fall
- Sword And Shield Power Up

## Implementation Details

### Character View Widget

The `CharacterView` widget uses Thermion's `ViewerWidget` with animated camera control:

```dart
ViewerWidget(
  assetPath: null, // Loaded programmatically to avoid double-loading
  initialCameraPosition: Vector3(0, 1.8, 3.0), // Default position
  manipulatorType: ManipulatorType.NONE, // Disable user interaction
  background: Colors.transparent,
  transformToUnitCube: false, // Keep original scale
  postProcessing: true, // Enable tone mapping and anti-aliasing
  onViewerAvailable: _onViewerAvailable, // Setup lighting and camera
)
```

**Camera Animation:**
- Uses `AnimationController` with `TickerProviderStateMixin` for smooth transitions
- Camera position animates smoothly between game states using `easeOutCubic` easing
- Camera is controlled via `viewer.getActiveCamera()` and `camera.lookAt()`

**Lighting Setup:**
- Three-point lighting system configured in `_onViewerAvailable`
- Key light: Warm daylight from top-right (main illumination)
- Fill light: Cooler light from front-left (reduces shadows)
- Rim light: From back (adds depth and separation)

### Animation Control

Animations are controlled programmatically:

```dart
// When game state changes
await _asset!.playGltfAnimationByName(
  animationName,
  loop: true,
  crossfade: 0.3, // Smooth transition
);
```

### Key Features

1. **Async Loading**: Model loads asynchronously with loading indicator
2. **Animation Component**: Automatically adds animation component to enable animations
3. **State Management**: Responds to game state changes via `didUpdateWidget`
4. **Error Handling**: Comprehensive error handling with fallbacks

## Unity Project Reference

The original Unity project demonstrates the desired animation behavior:

- **Location**: `/Users/michaelholloway/dev/Sight Words/`
- **Animator Controller**: `Assets/ts-little-animals/tsla_animator.controller`
- **Animation Triggers**: "Celebrate", "Fail" (from Unity GameController)
- **Animation System**: Uses blend trees with randomization for variety
- **External Animations**: Located in `Assets/ts-little-animals/animations/` (many not in current GLB)

### Key Unity Behavior Replicated

- ✅ Smooth transitions between idle/celebration/failure states
- ✅ Animations loop appropriately for each state
- ✅ No visible interruption when switching animations

## Future Enhancements

### Additional Animations

Many animations from the Unity project are not yet in the GLB file. See `MISSING_ANIMATIONS.md` for the complete list. To add them:

1. **Re-export from Unity**: Export the GLB with all desired animations baked in
2. **Use Blender**: Import GLB and external `.anim` files, then re-export
3. **Update Code**: Add new animation names to the mapping in `character_view.dart`

### Priority Animations to Add

**High Priority:**
- "Cheering" - Used in Unity celebration blend tree
- "Shaking Head No" - Classic failure animation
- "Joyful Jump" - Great celebration alternative
- "Fist Pump" - Good celebration
- "Annoyed Head Shake" - Good failure alternative

**Medium Priority:**
- "Dancing" / "Hip Hop Dancing" - More dance options for completion
- "Chicken Dance" - Fun completion animation
- "Gangnam Style" - Popular dance
- "Macarena Dance" - Fun dance

### Animation Randomization

Consider implementing animation randomization (like Unity's blend tree) for variety:
- Randomly select from multiple celebration animations
- Randomly select from multiple failure animations
- Add idle animation variations

### Lighting System

**Current Implementation:**
- ✅ **Three-Point Lighting**: Key light (top-right), fill light (front-left), rim light (back)
- ✅ **Color Temperature**: Warm key light (5500K), cool fill (6500K), neutral rim (7000K)
- ✅ **Intensity Balance**: Key (120k), Fill (40k), Rim (30k) for natural-looking character

**Future Enhancements:**
- Add image-based lighting (IBL) with KTX environment files for even better PBR materials
- Add skybox for environment context
- Dynamic lighting adjustments based on game state (e.g., brighter on celebration)

### Camera System

**Current Implementation:**
- ✅ **State-Based Camera Positions**: Subtle camera adjustments for each game state
- ✅ **Smooth Animations**: 800ms easeOutCubic transitions between positions
- ✅ **Default Position**: `(0, 1.8, 3.0)` - slightly elevated, looking down at character

**Camera Positions by State:**
- **Playing**: `(0, 1.8, 3.0)` - Default neutral position
- **Celebrating**: `(0, 2.0, 2.5)` - Slight zoom in and elevation
- **Failing**: `(0, 1.5, 3.5)` - Slight pull back
- **Completed**: `(0.3, 2.2, 3.2)` - Slight zoom out with subtle rotation

**Future Enhancements:**
- Add cinematic reveal animations on game start (fade-in, zoom-in)
- Add dynamic camera shake on failure (subtle)
- Add slow rotation or orbit on completion
- Add camera presets for different character sizes/positions

## Troubleshooting

### Build Errors

**Error: "Package(s) thermion_dart require the native assets feature to be enabled"**
- Solution: Run `flutter config --enable-native-assets`
- Then run `flutter clean` and rebuild

**Error: "thermion_flutter requires Android NDK 28.2.13676358"**
- Solution: Update `android/app/build.gradle.kts` to set `ndkVersion = "28.2.13676358"`
- The NDK will be automatically downloaded by Android Studio/Gradle

### Model Doesn't Appear

1. Check console for loading errors
2. Verify `Rabbit.glb` is in `assets/models/` folder
3. Ensure `assets/models/` is declared in `pubspec.yaml`
4. Try clearing build cache: `flutter clean`

### Animations Don't Play

1. Verify animations were exported from Unity/Blender
2. Check animation names match exactly (case-sensitive)
3. Use GLB inspector to verify animation names
4. Check console logs for available animations

### Performance Issues

1. Test on physical device (not emulator)
2. Reduce model complexity if needed
3. Optimize textures (reduce resolution if needed)
4. Adjust camera position to reduce rendering load

### Animation Transitions Not Smooth

1. Verify `crossfade` parameter is set (0.3 seconds recommended)
2. Check that `loop: true` is set for continuous animations
3. Ensure `addAnimationComponent()` was called after loading

## References

- [Thermion Documentation](https://thermion.dev/)
- [Thermion Flutter Package](https://pub.dev/packages/thermion_flutter)
- [Thermion Dart Package](https://pub.dev/packages/thermion_dart)
- [Google Filament Engine](https://google.github.io/filament/)
- [glTF Specification](https://www.khronos.org/gltf/)
- [Unity Project](../Sight%20Words/) - Original Unity implementation

## Status

- [x] Add Thermion dependencies
- [x] Update `character_view.dart` with ViewerWidget
- [x] Map game states to animations
- [x] Implement smooth animation transitions
- [x] Implement three-point lighting system
- [x] Add state-based camera animations
- [x] Test on target devices
- [ ] Add additional animations (future enhancement)
- [ ] Implement animation randomization (future enhancement)
- [ ] Add IBL lighting with KTX environment files (future enhancement)
- [ ] Add cinematic reveal animations on game start (future enhancement)
