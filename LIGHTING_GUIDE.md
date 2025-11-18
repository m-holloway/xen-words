# Scene Lighting System - Quick Guide

## Overview

The scene lighting is now controlled through the **LightingDirector** - a clean, intuitive control panel where all lighting parameters are defined in natural language. No math, no magic numbers!

## Files Changed

1. **`lib/widgets/lighting_director.dart`** (NEW)
   - Central control panel for all lighting
   - All parameters documented with natural descriptions
   - Easy to tune with hot reload

2. **`lib/widgets/character_view.dart`** (UPDATED)
   - Now uses LightingDirector for all lights
   - Cleaner, more maintainable code

## How to Use

### Basic Workflow

1. **Open** `lib/widgets/lighting_director.dart`
2. **Edit** a parameter (e.g., change `primaryIntensity` from 120000 to 150000)
3. **Save** the file
4. **Hot Reload** (press `r` in terminal or use IDE hot reload)
5. **See the change** instantly in your app!

### Key Parameters to Start With

#### 🎚️ Master Controls (Quickest way to adjust overall look)

```dart
static const double masterBrightness = 1.0;  // Multiply all lights (try 1.2 for brighter, 0.8 for darker)
```

#### ☀️ Primary Light (Main scene illumination)

```dart
static const double primaryIntensity = 120000.0;  // How bright (try 150000 for more depth)
static const double primaryColorTemp = 4000.0;     // Warmth (3500=cozy, 5500=neutral)
static const bool primaryCastsShadows = true;      // Shadows on/off
```

**Direction** (where light comes from):
```dart
static const LightDirection primaryDirection = LightDirection(
  x: 0.0,   // Left (-) to Right (+)
  y: -0.4,  // From above (negative = downward)
  z: 0.8,   // From behind character (positive = from backdrop)
  description: "Natural light from backdrop opening",
);
```

#### 💡 Fill Light (Softens shadows)

```dart
static const double fillIntensity = 50000.0;   // Should be less than primary (try 30000-60000)
static const double fillColorTemp = 5500.0;     // Often cooler than primary
```

#### ✨ Rim Light (Edge highlights)

```dart
static const double rimIntensity = 40000.0;     // Subtle edge glow
static const double rimColorTemp = 3500.0;      // Warm gold for separation
```

## Common Adjustments

### "I want more depth and dimension"

1. ↑ Increase `primaryIntensity` → 150000
2. ↓ Decrease `fillIntensity` → 30000
3. ✓ Ensure `primaryCastsShadows = true`

Result: Stronger contrast = more visible depth

### "Shadows are too dark"

1. ↑ Increase `fillIntensity` → 70000
2. ↑ Increase `ambientIntensity` → 12000

Result: Lifted shadows while keeping dimension

### "Character feels floaty/not grounded"

1. ✓ Ensure `primaryCastsShadows = true`
2. Adjust `primaryDirection` to have negative Y (from above)
3. ↑ Increase `primaryIntensity` for stronger shadows

Result: Clear shadow on ground = grounded character

### "Scene feels too warm/cozy" (want more neutral)

1. ↑ Increase `primaryColorTemp` → 5000-5500
2. ↑ Increase `rimColorTemp` → 5500
3. ↑ Increase `fillColorTemp` → 6000

Result: Cooler, more neutral daylight

### "Scene feels too cool/sterile" (want warmer)

1. ↓ Decrease `primaryColorTemp` → 3500-4000
2. ↓ Decrease `rimColorTemp` → 3000
3. Keep `fillColorTemp` cooler for nice contrast

Result: Warm, inviting learning space

### "Everything is too bright/dark"

**Too bright:**
- ↓ Decrease `masterBrightness` → 0.7 or 0.8

**Too dark:**
- ↑ Increase `masterBrightness` → 1.2 or 1.5

This affects ALL lights proportionally!

## Understanding Light Direction

**IMPORTANT:** Direction is where light travels **FROM** (not toward).

### Coordinate System
- **X-axis:** Left (-) to Right (+)
- **Y-axis:** Down (-) to Up (+)
- **Z-axis:** Far (-) to Near/Camera (+)

### Common Directions

```dart
// From above (like ceiling light)
LightDirection(x: 0.0, y: -1.0, z: 0.0)

// From behind (rim/backlight from backdrop)
LightDirection(x: 0.0, y: -0.3, z: 1.0)

// From front (camera direction)
LightDirection(x: 0.0, y: -0.5, z: -1.0)

// From side right
LightDirection(x: 1.0, y: -0.3, z: 0.0)
```

**Negative Y = from above** (this is how shadows point downward!)

## Color Temperature Reference

| Kelvin | Description | Use For |
|--------|-------------|---------|
| 2000-3000K | Warm candlelight, sunset | Extra cozy, magical |
| 3500-4500K | Warm white, morning sun | **Zen learning space (default)** |
| 5000-5500K | Neutral daylight | Clear, balanced, neutral |
| 6000-7000K | Cool daylight, overcast | Crisp, clean, professional |
| 8000K+ | Blue hour, twilight | Cool, dramatic |

## Experimentation Tips

### Start Bold, Then Refine

1. **Exaggerate** parameters to clearly see their effect
   - Try `primaryIntensity = 200000` to see strong contrast
   - Try `fillIntensity = 0` to see pure shadows
   - Try extreme directions like `y: -1.0` or `z: 1.0`

2. **Observe** what changes
   - Where do shadows fall?
   - How warm/cool does it feel?
   - Is the character grounded?

3. **Tune back** to what feels right
   - Find the sweet spot between dramatic and readable
   - Balance depth with visibility

### A/B Testing

Toggle lighting on/off to compare:

```dart
static const bool useCustomLighting = false;  // See default Thermion lighting
static const bool useCustomLighting = true;   // See your custom setup
```

### Document Your Findings

As you explore, note what worked:
- Screenshot before/after
- Note parameter values that felt good
- Write down "why" it worked

This helps if you need to recreate the look later!

## Quick Reference Presets

### Current Setup (Warm Cozy Learning Space)
```dart
primaryIntensity = 120000
primaryColorTemp = 4000 (warm daylight)
fillIntensity = 50000
rimIntensity = 40000
rimColorTemp = 3500 (warm gold)
```

### Bright & Clear (High visibility)
```dart
primaryIntensity = 150000
primaryColorTemp = 5500 (neutral)
fillIntensity = 80000
rimIntensity = 50000
masterBrightness = 1.2
```

### Soft & Dreamy (Gentle)
```dart
primaryIntensity = 80000
primaryColorTemp = 4500 (warm)
fillIntensity = 60000
rimIntensity = 30000
masterBrightness = 0.9
```

### Dramatic Contrast (Bold)
```dart
primaryIntensity = 180000
primaryColorTemp = 4000
fillIntensity = 30000
rimIntensity = 60000
rimColorTemp = 3000 (very warm)
```

## Performance Notes

- **Shadows have a cost** but modern devices handle them well
- Start with shadows on primary light only
- Add more shadow-casting lights only if needed
- Test on actual device (not just simulator) for realistic performance

## Next Steps

1. **Test the current setup** - see how it looks!
2. **Try adjusting `primaryIntensity`** - easiest way to see impact
3. **Experiment with `primaryDirection`** - find the angle that creates best depth
4. **Play with color temperature** - find what feels most inviting
5. **Document what works** - share findings for future reference!

## Questions to Answer Through Testing

- What intensity creates visible depth without being too harsh?
- What direction gives best rim lighting on character?
- Does the character feel grounded with current shadow setup?
- What color temperature feels most inviting for learning?
- Is the backdrop opening visually motivated as the light source?
- Do shadows make sense for the scene geometry?

Remember: **Trust your eyes!** If it looks better, it probably is. The goal is "warm, dimensional, and inviting" - not technical perfection.

Happy exploring! 🎨✨



