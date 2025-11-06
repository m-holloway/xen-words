# Animation Mapping - Unity to Flutter

## Unity Project Analysis

### Animation System in Unity

From `/Users/michaelholloway/dev/Sight Words/Assets/GameController.cs`:

1. **Animator Triggers Used:**
   - `"Celebrate"` - Triggered on correct word (line 541)
   - `"Fail"` - Triggered on incorrect word (line 678)
   - `"Test"` - Debug trigger (line 715)

2. **Animation Randomizer:**
   - Uses blend tree with `CelebrateIndex` parameter
   - Randomly selects from multiple celebration animations
   - Located in `AnimationRandomizer.cs`

### External Animation Files

The Unity project has external `.anim` files organized in folders:

**Location:** `/Users/michaelholloway/dev/Sight Words/Assets/ts-little-animals/animations/`

#### Positive (Celebrations):
- `root_combined_Cheering (4)-rabbit.anim`
- `root_combined_Joyful Jump-rabbit.anim`
- `root_combined_Victory Idle-rabbit.anim`
- `root_combined_Victory Idle2-rabbit.anim`
- `root_combined_Fist Pump-rabbit.anim`
- `root_combined_Head Nod Yes-rabbit.anim`
- `root_combined_Agreeing-rabbit.anim`
- And more...

#### Negative/Failure:
- `root_combined_Shaking Head No-rabbit.anim`
- `root_combined_Defeat Idle-rabbit.anim`
- `root_combined_Defeat Idle2-rabbit.anim`
- `root_combined_Annoyed Head Shake-rabbit.anim`
- `root_combined_Fall Flat-rabbit.anim`
- `root_combined_Death-rabbit.anim`
- And more...

#### Idle:
- `root_combined_Idle-rabbit.anim`
- `root_combined_Idle2-rabbit.anim`
- `root_combined_Happy Idle-rabbit.anim`
- `root_combined_Happy Idle2-rabbit.anim`
- `root_combined_Standing Idle 02-rabbit.anim`
- And more...

#### Dance (Completion):
- `root_combined_Dancing-rabbit.anim`
- `root_combined_Dancing2-rabbit.anim`
- `root_combined_Hip Hop Dancing-rabbit.anim`
- `root_combined_Chicken Dance-rabbit.anim`
- And many more dance variations...

## Current Flutter Implementation (Thermion)

### 3D Rendering: Thermion

The app now uses **Thermion** (Google Filament-based) for native 3D rendering with smooth animation transitions. See `3D_INTEGRATION.md` for complete implementation details.

**Key Advantages:**
- ✅ Native rendering (Metal/Vulkan) - no WebView overhead
- ✅ Smooth animation transitions with crossfading
- ✅ Production-ready, mature engine
- ✅ Full GLB animation support

### Animation Mapping (Updated with Actual GLB Animations)

The `CharacterView` widget uses Thermion's `ViewerWidget` and maps game states to actual GLB animation names:

```dart
GameState.celebrating → "Victory Idle"
GameState.failing → "Defeat"
GameState.playing → "Happy Idle"
GameState.completed → "Locking Hip Hop Dance"
```

**Available Alternatives:**
- Celebrating: "Victory Idle" (current)
- Failing: "Defeat" (current), "Fall Flat" (alternative)
- Playing: "Happy Idle" (current), "Idle", "Dwarf Idle", "Standing Idle 04" (alternatives)
- Completed: "Locking Hip Hop Dance" (current), "Wave Hip Hop Dance" (alternative)

### Smooth Animation Transitions

Thermion provides smooth animation transitions using crossfading:

```dart
await _asset!.playGltfAnimationByName(
  animationName,
  loop: true,
  crossfade: 0.3, // 0.3 second smooth transition
);
```

This eliminates the flickering/disappearing issue that occurred with WebView-based solutions.

### Visibility Fix

**Fixed:** Character is now visible during celebration (was previously hidden).

Changed in `game_screen.dart`:
- **Before:** Hidden during `celebrating` state
- **After:** Visible during all gameplay states (only hidden during `initial`)

## Important: External Animations

### The Problem

The external `.anim` files from Unity are **NOT** automatically included in the GLB file. The `Rabbit.glb` file likely only contains:
- The 3D model geometry
- Textures
- Possibly some basic animations that were baked during export

### The Solution

To use the external animations, you need to:

1. **Bake External Animations into GLB** (Recommended):
   - Open the Unity project
   - Select the rabbit model with animator controller
   - Export to GLB with all animations included
   - This will combine the external `.anim` files into the GLB

2. **Alternative: Use Animation Names from GLB**:
   - The GLB might have different animation names than the `.anim` files
   - Check what animations are actually in the GLB
   - Update the animation names in `character_view.dart` to match

### How to Check GLB Animation Names

You can:
1. Use a GLB viewer (like https://gltf-viewer.donmccurdy.com/)
2. Use Blender to inspect the GLB file
3. Use the `gltf` package in Flutter to parse and list animations
4. Check console logs when the model loads (model_viewer_plus may log available animations)

## Next Steps

### Immediate (To Test Current Implementation):

1. **Test the current animation names:**
   - Run the app and see if "Cheering", "Shaking Head No", "Idle", "Dancing" work
   - If animations don't play, the names likely don't match what's in the GLB

2. **Identify actual animation names in GLB:**
   - Use a GLB viewer or Blender
   - Or check console logs when model loads
   - Update `_getAnimationForState()` with correct names

### To Use External Animations:

1. **Option A: Re-export from Unity (Best)**
   - Open Unity project
   - Select rabbit model with animator
   - Export to GLB with all animations
   - This will bake all external `.anim` files into the GLB
   - Animation names will match the `.anim` file names (without "root_combined_" prefix)

2. **Option B: Use Blender**
   - Import `Rabbit.glb` into Blender
   - Import external `.anim` files
   - Link animations to the model
   - Re-export as GLB with all animations

3. **Option C: Use Animation Names Already in GLB**
   - If GLB already has animations, just update the names in code
   - May not match Unity's external animations exactly

## Animation Name Mapping Reference

### Animations Available in GLB ✅

**Celebrations:**
- `"Victory Idle"` ✅ (currently used)

**Failures:**
- `"Defeat"` ✅ (currently used)
- `"Fall Flat"` ✅ (alternative)

**Idle:**
- `"Idle"` ✅
- `"Happy Idle"` ✅ (currently used)
- `"Dwarf Idle"` ✅
- `"Standing Idle 04"` ✅
- `"Standing W_Briefcase Idle"` ✅

**Dance/Completion:**
- `"Locking Hip Hop Dance"` ✅ (currently used)
- `"Wave Hip Hop Dance"` ✅ (alternative)

**Other Available:**
- Dodging, Dying Backwards, Falling Back Death
- Fast Run, Slow Run, Running, Walking
- Jump, Jumping
- Kicking, Inside Crescent Kick, Side Kick
- Punching, One Hand Club Combo
- Shoulder Hit And Fall
- Sword And Shield Power Up

### Missing Animations from Unity Project ❌

See `MISSING_ANIMATIONS.md` for complete list.

**Key Missing:**
- **Celebrations:** Cheering, Joyful Jump, Fist Pump, Head Nod Yes, Agreeing, Victory Idle2
- **Failures:** Shaking Head No, Annoyed Head Shake, Defeat Idle, Defeat Idle2, Death
- **Dances:** Dancing, Hip Hop Dancing, Chicken Dance, Gangnam Style, Macarena Dance, and 23 more
- **Idles:** Idle2, Happy Idle2, Standing Idle 02, and 9 more variations

**Note:** To use missing animations, they need to be baked into the GLB file. See `MISSING_ANIMATIONS.md` for details.

## Testing Checklist

- [ ] Character is visible during celebration
- [ ] Celebration animation plays (or falls back gracefully)
- [ ] Failure animation plays (or falls back gracefully)
- [ ] Idle animation plays during gameplay
- [ ] Dance animation plays on completion
- [ ] No performance issues on target devices
- [ ] Animations transition smoothly between states

