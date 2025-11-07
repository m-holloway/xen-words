# Procedural Asset Workflow

## Overview

Our 3D asset pipeline is **procedural** and **compositional**, meaning assets are generated from code with adjustable parameters and composed from reusable components. This approach enables:

- ✅ **Version control** for asset generation logic
- ✅ **Parametric adjustments** without manual re-modeling
- ✅ **Rapid iteration** and experimentation
- ✅ **Consistency** across asset variations
- ✅ **Reusability** through composition

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PROCEDURAL PIPELINE                       │
└─────────────────────────────────────────────────────────────┘

1. GENERATORS (Python scripts)
   ├── generate_pot.py          → Creates Pot.blend
   ├── generate_foliage.py      → Creates Foliage.blend
   └── generate_potted_plant.py → Composes PottedPlant.blend

2. LIBRARY (Binary .blend files)
   ├── Pot.blend          (generated from script)
   ├── Foliage.blend      (generated from script)
   ├── PottedPlant.blend  (composed from Pot + Foliage)
   └── GroundPlane.blend  (manual, with procedural texture)

3. SCENES (Compositions)
   └── GameScene.blend    (instances of library assets)

4. EXPORTS (Game-ready)
   └── GameScene.glb      (final export for Thermion)
```

## Workflow: Making Changes

### Scenario 1: Adjusting an Existing Asset

**Example: Make plants taller and fuller**

1. **Edit the generator script**:
   ```bash
   # Open in your editor
   nano assets/models/scripts/generators/generate_foliage.py
   ```

2. **Adjust parameters**:
   ```python
   FOLIAGE_CONFIG = {
       'height': 0.85,          # Was: 0.70 → Now taller
       'leaf_count': 75,        # Was: 58 → Now fuller
       'spread': 0.40,          # Was: 0.35 → Wider
       # ... other parameters
   }
   ```

3. **Regenerate**:
   ```bash
   cd assets/models
   blender --background --python scripts/generators/generate_foliage.py
   ```

4. **Recompose** dependent assets:
   ```bash
   blender --background --python scripts/generators/generate_potted_plant.py
   blender --background --python scripts/compose_game_scene.py
   ```

5. **Test** in game (hot reload won't work for 3D assets):
   ```bash
   flutter run
   ```

### Scenario 2: Creating a New Asset Variation

**Example: Create a small decorative pot**

1. **Create a new config** in the generator:
   ```python
   # In generate_pot.py
   
   SMALL_POT_CONFIG = {
       **POT_CONFIG,  # Copy defaults
       'bottom_radius': 0.12,
       'top_radius': 0.15,
       'height': 0.20,
   }
   ```

2. **Generate with custom config**:
   ```python
   generate_pot(SMALL_POT_CONFIG, "library/PotSmall.blend")
   ```

3. **Use in compositions**:
   ```python
   # In a scene composer
   append_asset("PotSmall", "Pot")
   ```

### Scenario 3: Creating a Completely New Asset

**Example: Add a bench**

1. **Create generator script**:
   ```bash
   touch assets/models/scripts/generators/generate_bench.py
   ```

2. **Write parametric generator**:
   ```python
   BENCH_CONFIG = {
       'length': 1.5,
       'width': 0.4,
       'height': 0.45,
       'leg_count': 4,
       # ... more parameters
   }
   
   def generate_bench(config, output_path):
       # Procedural geometry creation
       # ...
   ```

3. **Add to rebuild script**:
   ```python
   # In rebuild_all.py
   from generate_bench import generate_bench, BENCH_CONFIG
   generate_bench(BENCH_CONFIG, "library/Bench.blend")
   ```

## Best Practices

### 1. **Parameters at the Top**

Always define configuration dictionaries at the top of generator scripts:

```python
# ✅ Good - clear, adjustable
ASSET_CONFIG = {
    'width': 0.5,
    'height': 1.0,
    'segments': 16,
}

def generate_asset(config):
    width = config['width']
    # ...

# ❌ Bad - hardcoded values
def generate_asset():
    width = 0.5  # Hidden in code
    # ...
```

### 2. **Document Parameters**

Add comments explaining what each parameter does:

```python
ASSET_CONFIG = {
    'radius': 0.25,          # Outer radius in meters
    'segments': 16,          # More = smoother circle (16-32 typical)
    'height': 0.5,           # Total height in meters
    'taper': 0.8,            # 0-1: how much narrower at top
}
```

### 3. **Use Meaningful Units**

- **Distances**: meters (Blender's default)
- **Angles**: radians for calculations, degrees in comments
- **Colors**: RGBA tuples (0-1 range)
- **Poly counts**: absolute numbers

### 3.5. **Coordinate System Conversion (CRITICAL!)**

**Blender uses Z-up, Thermion uses Y-up.** This affects positioning!

#### Blender Coordinate System
- **X**: Left (-) / Right (+)
- **Y**: Forward (+) / Backward (-) from character
- **Z**: Down (-) / Up (+)

#### Thermion Coordinate System (GLB Export)
- **X**: Left (-) / Right (+) (same as Blender)
- **Y**: Down (-) / Up (+) (was Z in Blender)
- **Z**: Backward (-) / Forward (+) (was -Y in Blender)

#### Conversion Rules
When exporting to GLB, Blender automatically converts:
- Blender `(X, Y, Z)` → GLB `(X, Z, -Y)`

**Important positioning notes:**
- **Camera position**: In Thermion, camera is at `Z=3.0` looking at character at `(0,0,0)`
- **Behind character**: Negative Z in Thermion = Positive Y in Blender
- **In front of character**: Positive Z in Thermion = Negative Y in Blender
- **Plants are at**: `Y=2.5` in Blender (forward from character)
- **Backdrop should be**: `Y > 2.5` in Blender (behind plants, further from camera)

**Example:**
```python
# In Blender scene composer:
backdrop.location = (0, 3.5, 0)  # X=0 (center), Y=3.5 (behind), Z=0 (ground)

# After GLB export, in Thermion:
# X=0 (center), Y=0 (ground), Z=-3.5 (behind character) ✓
```

**Common mistake**: Setting `Y=-2.5` in Blender thinking "behind" = negative, but this actually puts it in front of the camera!

### 4. **Validate Outputs**

After generation, run the analyzer:

```bash
blender --background --python scripts/tools/asset_analyzer.py -- library/MyAsset.blend
```

Check for:
- ✓ Poly count appropriate for mobile
- ✓ Materials properly assigned
- ✓ No geometry issues
- ✓ Correct dimensions

### 5. **Composition Over Monoliths**

Break assets into reusable components:

```
✅ Good (Compositional):
  PottedPlant.blend = Pot.blend + Foliage.blend + Dirt
  → Can mix different pots and foliage
  → Easy to adjust components independently

❌ Bad (Monolithic):
  PottedPlant.blend = single joined mesh
  → Hard to adjust pot without affecting foliage
  → No reusability
```

### 6. **Version Control Everything**

**Commit**:
- ✅ Generator scripts (`.py`)
- ✅ Documentation (`.md`)
- ✅ Scene composers
- ✅ Pipeline tools

**Don't commit** (use `.gitignore`):
- ❌ Blender backup files (`.blend1`, `.blend2`)
- ❌ OS files (`.DS_Store`)
- ⚠️ Large binary `.blend` files (optional - can commit)
- ⚠️ `.glb` exports (can be regenerated)

## Quick Reference

### Rebuild Everything
```bash
cd assets/models
blender --background --python scripts/tools/rebuild_all.py
```

### Analyze Asset
```bash
blender --background --python scripts/tools/asset_analyzer.py -- library/MyAsset.blend
```

### Manual Generation
```bash
# Individual asset
blender --background --python scripts/generators/generate_pot.py

# With custom parameters (edit script first)
blender --background --python scripts/generators/generate_foliage.py

# Compose scene
blender --background --python scripts/compose_game_scene.py
```

### Export for Game
```bash
# Scene composer automatically exports to:
#  - exports/GameScene.glb (new structure)
#  - GroundPlane.glb (backward compatible)
```

## Troubleshooting

### "File not found" errors
- Check paths are relative to the script location
- Ensure dependencies are generated first (Pot before PottedPlant)

### Geometry looks wrong
- Run asset analyzer to check for issues
- Verify parameters are in correct units (meters, not cm)
- Check smooth shading is applied

### Performance issues
- Run analyzer to check poly count
- Target < 2000 polys per asset for mobile
- Use instancing for repeated elements

### Can't see changes in game
- 3D assets don't hot reload - must restart app
- Ensure exports are regenerated
- Check `flutter clean` if caching issues

## Learn More

- [Asset Parameters Reference](ASSET_PARAMETERS.md) - All available parameters
- [Coordinate System Reference](COORDINATE_SYSTEMS.md) - **CRITICAL: Blender vs Thermion coordinate conversion**
- [Asset Library Guide](../ASSET_LIBRARY_GUIDE.md) - Library organization
- [Blender MCP Guide](../BLENDER_MCP.md) - Interactive Blender integration

