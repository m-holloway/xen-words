# Next Task: Scene Lighting & Atmosphere

## Overview
Improve the visual depth and atmosphere of the 3D game scene through lighting. The current scene is technically solid with good composition and asset placement, but feels **visually flat** due to uniform lighting. We need to add dimension, depth, and a warm, inviting atmosphere.

## Current State

### What's Working
- ✅ Clean scene composition with proper depth layering
- ✅ Shoji backdrop with central opening (natural light source)
- ✅ Character, rug, plants, fusuma panels all positioned correctly
- ✅ Scene runs at 60fps with ~2,900 polygons
- ✅ Good aesthetic foundation (zen/minimalist)

### The Problem
- ⚠️ **Everything is evenly lit** - no sense of depth or dimension
- ⚠️ **No shadows** - character appears to float rather than stand on the rug
- ⚠️ **Flat materials** - lack of highlights/shadows to show form
- ⚠️ **No atmosphere** - scene feels sterile rather than inviting
- ⚠️ **Missing visual hierarchy** - no focal point created by lighting

### Visual Reference
Current scene has uniform brightness everywhere. Compare to:
- Real rooms with window light: bright areas near windows, darker corners, shadows
- Natural light creates depth: rim lighting, cast shadows, ambient occlusion
- Good 3D scenes: clear light direction, grounded objects, atmospheric depth

## Goal
Transform the scene from "technically correct" to **"warm, dimensional, and inviting"** through strategic lighting. Make it feel like a real, cozy learning space.

## Technical Context

### Thermion Lighting API
We'll work primarily in `lib/widgets/character_view.dart` within the `CharacterView` class.

**Key Methods** (from Thermion documentation):
- `addLight(LightType type)` - Add directional, point, or spot lights
- `setLightPosition(light, x, y, z)` - Position lights in 3D space
- `setLightDirection(light, x, y, z)` - Set directional light direction
- `setLightColor(light, r, g, b)` - Set light color
- `setLightIntensity(light, intensity)` - Set brightness
- `setLightCastShadows(light, bool)` - Enable/disable shadows
- `setIndirectLight()` - Set ambient/environment lighting
- `setShadowsEnabled(bool)` - Global shadow toggle

**Scene Coordinate System** (in Thermion/Flutter):
- X-axis: Left (-) to Right (+)
- Y-axis: Down (-) to Up (+)
- Z-axis: Far (-) to Near (+) [toward camera]

**Current Scene Layout**:
- Character at (0, 0, 0)
- Backdrop at Z ≈ -3.5 (behind character)
- Camera at Z ≈ 3.0 (in front of character)
- Plants at Z ≈ -2.5
- Fusuma at Z ≈ 2.0 (foreground framing)

### Existing Lighting Setup
Currently minimal/default:
- Viewer has default ambient light
- No directional or point lights added
- No shadows enabled
- Scene uses Thermion's default lighting

### Performance Considerations
- Real-time shadows have a performance cost
- We target 60fps on mobile devices
- Shadow map resolution affects both quality and performance
- Multiple lights compound performance impact
- May need to test on lower-end devices

## Exploration Tasks

### Phase 1: Directional Light (Primary Goal)
**Hypothesis**: A single well-placed directional light simulating natural light from the backdrop opening will create most of the depth we need.

**Experiment**:
1. Add a directional light positioned as if coming from behind/above the backdrop
   - Start with direction roughly `(0, -0.5, -1)` (from above and behind)
   - Try warm color temperature: `(1.0, 0.95, 0.9)` for soft daylight
   - Start with moderate intensity (~50,000-100,000 lux equivalent)

2. Enable shadows for this light
   - Character should cast shadow forward onto rug
   - Plants should cast shadows on floor
   - Check shadow softness/sharpness

3. **Iterate on direction**:
   - Try from directly behind: `(0, 0, -1)`
   - Try from above-behind: `(0, -0.7, -0.7)`
   - Try slight angle: `(0.2, -0.5, -1)` for asymmetry
   - See what creates best rim lighting on character
   - Find what makes the space feel most natural

4. **Iterate on intensity**:
   - Start conservative, increase until we see clear depth
   - Avoid over-exposure or harsh shadows
   - Balance readability with atmosphere

5. **Iterate on color**:
   - Try neutral white: `(1.0, 1.0, 1.0)`
   - Try warm daylight: `(1.0, 0.95, 0.9)`
   - Try golden hour: `(1.0, 0.9, 0.8)`
   - See what creates the most inviting atmosphere

**Questions to Answer**:
- Does the directional light create sufficient depth on its own?
- What direction feels most natural for the scene layout?
- How dark can shadows go while maintaining readability?
- Does the character feel grounded with shadows?

### Phase 2: Ambient/Indirect Light (If Needed)
**Hypothesis**: After adding directional light, we may need ambient light to lift shadows and prevent areas from going too dark.

**Experiment**:
1. Check if areas without direct light are too dark
2. If so, add subtle indirect/ambient light
   - Much lower intensity than directional light
   - Neutral or slightly cool color to contrast warm directional
   - Just enough to maintain visibility, not flatten the scene

3. Try different ambient intensities:
   - Very subtle: ~10-20% of directional light intensity
   - See how much is needed for readability
   - Don't eliminate shadows, just soften them

**Questions to Answer**:
- Do we even need ambient light or does directional + environment work?
- What intensity preserves depth while maintaining readability?
- Should ambient be warm, cool, or neutral?

### Phase 3: Additional Lights (Optional)
**Hypothesis**: We probably don't need more lights, but if directional + ambient isn't enough, we might add:

**Possible Additions**:
1. **Subtle fill light** from front-side to lift character face
   - Very low intensity
   - Only if character front is too dark

2. **Rim light** to separate character from background
   - If directional light doesn't create enough separation
   - Positioned behind/above character at angle

3. **Accent light** on plants or backdrop
   - Only if we want to emphasize specific elements

**Experiment conservatively** - each light adds complexity and performance cost.

**Questions to Answer**:
- Is one directional light + ambient sufficient?
- Do we need additional lights or just better tuning?
- Can we achieve the look with minimal lights for performance?

### Phase 4: Shadow Refinement
Once we have light positions/intensities working:

1. **Shadow Quality**:
   - Adjust shadow map resolution (if available)
   - Balance quality vs performance
   - Test on mobile device if possible

2. **Shadow Softness**:
   - Hard shadows vs soft shadows
   - What looks more natural for this scene?
   - Penumbra settings if available

3. **Shadow Coverage**:
   - Ensure character shadow is visible on rug
   - Plant shadows on floor
   - Check for shadow artifacts or issues

### Phase 5: Testing & Polish

**Test Across Game States**:
- Learning mode (close-up)
- Playing mode (standard view)
- Celebrating mode (any special camera angles)
- Ensure lighting works for all states

**Test Readability**:
- Word cards must remain clearly visible
- Character must be easily distinguishable
- UI elements shouldn't be obscured

**Performance Check**:
- Monitor FPS during gameplay
- Check on lower-end device if available
- Shadow performance impact acceptable?

**Visual Consistency**:
- Does lighting feel natural throughout?
- Any awkward transitions or dark spots?
- Does it enhance the zen/cozy aesthetic?

## Implementation Approach

### Code Location
Primary file: `lib/widgets/character_view.dart`

**Likely insertion point**:
In `_onViewerAvailable()` callback, after scene is loaded but before animations start. Something like:

```dart
Future<void> _onViewerAvailable() async {
  // ... existing scene loading code ...
  
  // Setup lighting
  await _setupSceneLighting();
  
  // ... rest of initialization ...
}

Future<void> _setupSceneLighting() async {
  // Add directional light (sun/window light from backdrop)
  final sunLight = await _viewer!.addLight(LightType.directional);
  await _viewer!.setLightDirection(sunLight, 0, -0.5, -1);
  await _viewer!.setLightColor(sunLight, 1.0, 0.95, 0.9);
  await _viewer!.setLightIntensity(sunLight, 75000);
  await _viewer!.setLightCastShadows(sunLight, true);
  
  // Add ambient light if needed
  // ... etc
}
```

### Iterative Development Process
1. **Add one light** - observe effect
2. **Adjust parameters** - tweak until it feels right
3. **Screenshot/document** what works and what doesn't
4. **Try variations** - don't settle on first attempt
5. **Test in-app** - see how it feels during actual gameplay
6. **Refine** based on observations

### Documentation
As you iterate, note:
- What parameter values you tried
- What worked well vs what didn't
- Why you chose the final values
- Any performance observations
- Screenshots of before/after

This will help if we need to adjust later or apply similar lighting to other scenes.

## Success Criteria

### Visual Quality
- [ ] Scene has clear sense of **depth and dimension**
- [ ] Character appears **grounded** (not floating)
- [ ] Lighting creates **visual hierarchy** (focal points)
- [ ] Atmosphere feels **warm and inviting**
- [ ] Lighting direction makes **visual sense** for the space
- [ ] Materials show **form through highlights/shadows**

### Technical Requirements
- [ ] Maintains **60fps** on target devices
- [ ] Word cards remain **clearly readable**
- [ ] Character is **easily distinguishable**
- [ ] Works across **all game states** (learning, playing, celebrating)
- [ ] No visual **artifacts or glitches**

### Aesthetic Goals
- [ ] Enhances the **zen/minimalist aesthetic**
- [ ] Feels **natural and realistic** (not artificial)
- [ ] Creates **cozy learning corner** atmosphere
- [ ] More **inviting and alive** than current flat lighting
- [ ] Complements the **shoji backdrop** design

## Deliverables

1. **Updated Code**:
   - Lighting implementation in `character_view.dart`
   - Well-commented explaining choices
   - Parameter values documented

2. **Visual Documentation**:
   - Before/after screenshots (if possible)
   - Notes on what parameters were chosen and why

3. **Performance Notes**:
   - FPS observations
   - Any performance concerns or optimizations

4. **Recommendations**:
   - What worked best
   - What didn't work or could be improved
   - Future lighting enhancements to consider

## Open Questions / Exploration Areas

- **Light Direction**: What angle creates the best rim lighting and depth?
- **Light Color**: Warm vs neutral vs cool - what feels most inviting?
- **Shadow Intensity**: How dark before it impacts readability?
- **Ambient Level**: How much fill light is needed?
- **Number of Lights**: Can we achieve the look with just one or two lights?
- **Shadow Softness**: Hard shadows or soft shadows for this aesthetic?
- **Performance**: What's the FPS impact of shadows on mobile?

## Future Considerations (Out of Scope)

These might be follow-up tasks after getting basic lighting working:
- Animated lighting (time-of-day changes, flickering)
- Baked lightmaps for better performance
- Light probes for indirect lighting
- More advanced shadow techniques
- Per-material lighting adjustments
- Volumetric lighting effects

## Notes

- This is **exploratory work** - iterate and see what feels good!
- Trust your visual judgment - if it looks better, it probably is
- Don't be afraid to try unconventional approaches
- Performance matters but visual quality is also important
- Ask for feedback if you're unsure between options
- Document your process so we can learn from it

Remember: The goal is to make the scene feel **alive and inviting**. Technical perfection is secondary to creating that warm, dimensional atmosphere. If something looks good but breaks a "rule," that's okay! Let's see what works. 🎨


