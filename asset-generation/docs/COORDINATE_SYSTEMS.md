# Coordinate System Reference

## Overview

This document explains the coordinate system differences between Blender (where we create assets) and Thermion/GLB (where we render them). **Understanding this is critical for correct asset positioning.**

---

## Blender Coordinate System (Z-Up)

Blender uses a **Z-up** coordinate system:

- **X-axis**: Left (-) / Right (+)
- **Y-axis**: Forward (+) / Backward (-) from default view
- **Z-axis**: Down (-) / Up (+) (vertical)

**Visual reference:**
```
        +Z (Up)
         |
         |
    ----+---- +X (Right)
        |
        |
       -Y (Backward/Behind)
```

**In Blender:**
- Character is typically at origin: `(0, 0, 0)`
- Forward from character: Positive Y
- Behind character: Negative Y
- Up: Positive Z

---

## Thermion/GLB Coordinate System (Y-Up)

Thermion (and GLB format) uses a **Y-up** coordinate system:

- **X-axis**: Left (-) / Right (+) (same as Blender)
- **Y-axis**: Down (-) / Up (+) (was Z in Blender)
- **Z-axis**: Backward (-) / Forward (+) (was -Y in Blender)

**Visual reference:**
```
        +Y (Up)
         |
         |
    ----+---- +X (Right)
        |
        |
       +Z (Forward/Toward Camera)
```

**In Thermion:**
- Character is at origin: `(0, 0, 0)`
- Camera is typically at: `Z=3.0` looking at character
- Forward (toward camera): Positive Z
- Behind (away from camera): Negative Z
- Up: Positive Y

---

## Coordinate Conversion

When Blender exports to GLB, it automatically converts coordinates:

**Conversion formula:**
```
Blender (X, Y, Z) → GLB (X, Z, -Y)
```

**Breakdown:**
- X stays the same
- Blender's Z becomes GLB's Y (vertical)
- Blender's -Y becomes GLB's Z (forward/back)

---

## Practical Examples

### Example 1: Positioning Backdrop Behind Character

**Goal**: Place backdrop behind character (away from camera)

**In Blender:**
```python
backdrop.location = (0, 3.5, 0)
# X=0 (center)
# Y=3.5 (positive = forward in Blender, but becomes negative Z in GLB = behind!)
# Z=0 (ground level)
```

**After GLB export, in Thermion:**
- X = 0 (centered)
- Y = 0 (ground level)
- Z = -3.5 (behind character, away from camera) ✓

**Why this works**: Positive Y in Blender becomes negative Z in Thermion, which is behind the character.

---

### Example 2: Positioning Plants Forward from Character

**Goal**: Place plants in front of character (toward camera)

**In Blender:**
```python
plant.location = (-1.0, 2.5, -0.1)
# X=-1.0 (left side)
# Y=2.5 (forward from character)
# Z=-0.1 (slightly below ground)
```

**After GLB export, in Thermion:**
- X = -1.0 (left side)
- Y = -0.1 (slightly below ground)
- Z = -2.5 (behind character) ❌ **Wait, that's wrong!**

**Correction needed**: Plants at `Y=2.5` in Blender are actually behind the character in Thermion. To place them forward, use negative Y in Blender:

```python
plant.location = (-1.0, -2.5, -0.1)
# Y=-2.5 (backward in Blender) → Z=2.5 (forward in Thermion) ✓
```

---

### Example 3: Backdrop Depth Relative to Plants

**Problem**: Backdrop intersecting with plants

**Plants are at**: `Y=2.5` in Blender

**Backdrop should be**: Further back than plants

**Solution**:
```python
# Plants
plant.location = (-1.0, 2.5, -0.1)

# Backdrop (behind plants)
backdrop.location = (0, 3.5, 0)  # Y=3.5 > Y=2.5, so further back ✓
```

**In Thermion:**
- Plants: Z = -2.5
- Backdrop: Z = -3.5
- Backdrop is further back (more negative Z) ✓

---

## Camera Positioning Reference

**Camera setup in Thermion:**
- Camera position: `(0, ~1.1, 3.0)` - looking at character from front
- Character position: `(0, 0, 0)`
- Camera looks at: Character center at `(0, 1.1, 0)`

**What this means:**
- Objects with **positive Z** in Thermion = **in front of camera** (may obscure view)
- Objects with **negative Z** in Thermion = **behind character** (visible, doesn't obscure)
- Objects with **Z ≈ 0** = **at character level** (on floor, etc.)

---

## Common Mistakes

### ❌ Mistake 1: "Behind = Negative Y"
```python
# WRONG - This puts it in front of camera!
backdrop.location = (0, -2.5, 0)  # Negative Y in Blender
# → Becomes Z=2.5 in Thermion (in front of camera!) ❌
```

### ✅ Correct: "Behind = Positive Y"
```python
# CORRECT - This puts it behind character
backdrop.location = (0, 2.5, 0)  # Positive Y in Blender
# → Becomes Z=-2.5 in Thermion (behind character) ✓
```

### ❌ Mistake 2: Same Depth as Other Objects
```python
# WRONG - Backdrop intersects with plants
backdrop.location = (0, 2.5, 0)  # Same Y as plants
plant.location = (-1.0, 2.5, -0.1)  # Same Y = same depth!
```

### ✅ Correct: Different Depths
```python
# CORRECT - Backdrop behind plants
backdrop.location = (0, 3.5, 0)  # Y=3.5 > Y=2.5 (plants)
plant.location = (-1.0, 2.5, -0.1)  # Plants at Y=2.5
```

---

## Quick Reference Table

| Direction | Blender (Z-up) | Thermion (Y-up) | Notes |
|-----------|----------------|-----------------|-------|
| Left | Negative X | Negative X | Same |
| Right | Positive X | Positive X | Same |
| Up | Positive Z | Positive Y | Converted |
| Down | Negative Z | Negative Y | Converted |
| Forward (toward camera) | Negative Y | Positive Z | Inverted |
| Backward (away from camera) | Positive Y | Negative Z | Inverted |

---

## Testing Positioning

When positioning assets:

1. **Export to GLB** and test in app
2. **If object obscures camera**: It's too far forward (positive Z in Thermion = negative Y in Blender)
3. **If object not visible**: It might be too far back or outside camera view
4. **If objects intersect**: Check their Y values in Blender - objects with same Y are at same depth

---

## Related Documentation

- [PROCEDURAL_WORKFLOW.md](PROCEDURAL_WORKFLOW.md) - General workflow including coordinate notes
- [ASSET_PARAMETERS.md](ASSET_PARAMETERS.md) - Asset-specific positioning examples
- Scene composer: `composers/compose_game_scene.py` - See actual positioning code

