<!-- b46eee03-3441-4f32-8b26-ab7dd54daa44 921c46ec-6d89-4108-af1c-3d28665e6a5c -->
# 3D Visual Enhancements Plan

## Overview

Improve the visual quality of the 3D character in both the splash screen and game through advanced lighting techniques, cinematic camera work, and animation polish.

## Current State Analysis

### Lighting System

**Current**: Three-point lighting setup

- Key light: 5500K, 120000 intensity, direction (0.4, -0.9, 0.2)
- Fill light: 6500K, 40000 intensity, direction (-0.3, -0.5, -0.8)
- Rim light: 7000K, 30000 intensity, direction (-0.2, 0.3, 0.9)

**Limitations**:

- No image-based lighting (IBL) for realistic environment reflections
- No skybox or background
- Static lighting (doesn't respond to game state)
- No shadows enabled

### Camera System

**Current**: Director-friendly CameraConfig with state-based positions

- Predefined shots: wide, medium, close, tight
- Game state cameras: playing, celebrating, failing, completed
- Splash screen: Continuous orbit/zoom animation
- Smooth transitions with easeOutCubic curve (800ms)

**Limitations**:

- Camera movements are purely positional (no shake, sway, or secondary motion)
- No depth of field effects
- Limited cinematic techniques (no dolly, crane, or tracking shots)
- Splash screen orbit is mathematical, not artistic

### Animation System

**Current**: GLB animations with 0.3s crossfade

- State-based animation selection
- Fallback logic for missing animations
- Continuous looping

**Limitations**:

- Limited animation variety (only 5-6 animations used)
- No procedural animations (breathing, eye movement, subtle idle motion)
- No physics-based effects (cloth, hair simulation)
- No animation blending for complex states

## Enhancement Strategy

### Phase 1: Advanced Lighting

**Implement Image-Based Lighting (IBL)**

- Add HDR environment map for realistic lighting
- Enable reflections on character model
- Configure IBL intensity to match scene tone
- Test multiple environment maps (studio, outdoor, warm interior)

**Add Skybox/Background**

- Implement simple gradient skybox for depth
- Configure background color per game state (celebratory gold, calm blue, etc.)
- Ensure background doesn't distract from character

**Dynamic Lighting by Game State**

- Celebrating: Increase key light intensity, add warm color shift
- Failing: Reduce overall intensity, add cooler color shift
- Playing: Balanced neutral lighting
- Completed: Pulsing/shifting lights for excitement

**Enable Shadows**

- Configure shadow maps with appropriate resolution
- Set shadow softness for natural look
- Balance shadow intensity to avoid too dark/harsh

**Post-Processing Effects**

- Bloom for celebration state (subtle glow)
- Vignette for focus during gameplay
- Color grading per state (warmer/cooler tones)

### Phase 2: Cinematic Camera Work

**Enhanced Game State Cameras**

- Playing: Add subtle sway (breathing effect)
- Celebrating: Dynamic zoom-in with slight spiral
- Failing: Slight pull-back with downward tilt
- Completed: 360° slow orbit while zooming

**Camera Shake System**

- Implement configurable shake (amplitude, frequency, decay)
- Add shake on celebration (excitement)
- Subtle shake on failure (impact)
- Ensure shake doesn't cause motion sickness

**Advanced Camera Movements**

- Implement Bezier curve camera paths for smooth complex moves
- Add "look-ahead" prediction for character animation
- Create camera presets: dramatic, subtle, neutral
- Allow camera to respond to audio cues

**Depth of Field Effects**

- Focus on character center
- Blur background for depth
- Adjust focal length per shot type (wider = more blur)

**Splash Screen Camera Refinement**

- Replace mathematical orbit with artistic camera choreography
- Create keyframe-based camera sequence
- Add anticipation/follow-through to movements
- Synchronize camera with character animation beats

### Phase 3: Animation Polish

**Add Procedural Animations**

- Breathing motion during idle states
- Eye blinking and tracking
- Ear twitching (character is a rabbit)
- Weight shifting during idle

**Enhanced Animation Transitions**

- Increase crossfade to 0.5s for smoother blending
- Add anticipation frames before major transitions
- Implement animation curves (ease-in for celebration, bounce for failure)

**State-Specific Animation Variants**

- Playing: Rotate between multiple idle animations
- Celebrating: Chain multiple celebration animations
- Add randomization to prevent repetitive feel

**Physics-Based Enhancements**

- Enable soft-body physics for cloth/accessories
- Add secondary motion (ears lag behin

### To-dos

- [ ] Delete FLUTTER_SCENE_MIGRATION.md and update pubspec.yaml with Thermion
- [ ] Rewrite character_view.dart to use Thermion
- [ ] Update 3D_INTEGRATION.md with Thermion approach
- [ ] Update ANIMATION_MAPPING.md, README.md, and BUILD_NOTES.md
- [ ] Test implementation and fix any issues