# Asset Parameters Reference

Complete reference for all adjustable parameters in our procedural asset generators.

## Pot Generator

**File**: `scripts/generators/generate_pot.py`

### Dimensions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bottom_radius` | float | 0.18 | Radius at pot bottom (meters) |
| `top_radius` | float | 0.24 | Radius at pot top/rim (meters) |
| `height` | float | 0.35 | Total pot height (meters) |
| `rim_height` | float | 0.01 | Height of decorative rim (meters) |
| `rim_flare` | float | 0.04 | How much rim extends outward (meters) |

### Detail

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `segments` | int | 16 | Number of segments around circumference (more = smoother) |
| `height_segments` | int | 3 | Vertical subdivisions for shaping |

**Optimization**: 16 segments is good for mobile. Use 32+ only for close-ups.

### Features

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `drainage_hole` | bool | True | Include drainage hole in bottom |
| `drainage_radius` | float | 0.015 | Radius of drainage hole (meters) |

### Material

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `material_name` | string | "ConcretePotMaterial" | Material name in Blender |
| `base_color` | RGBA | (0.6, 0.6, 0.6, 1.0) | Material color (0-1 range) |
| `roughness` | float | 0.8 | Surface roughness (0=mirror, 1=matte) |

**Example adjustments**:
```python
# Terra cotta pot
'base_color': (0.8, 0.5, 0.4, 1.0),  # Reddish-orange
'roughness': 0.9,                     # Very matte

# Glazed ceramic
'base_color': (0.2, 0.3, 0.5, 1.0),  # Blue
'roughness': 0.2,                     # Shiny
```

---

## Foliage Generator

**File**: `scripts/generators/generate_foliage.py`

### Overall Structure

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `height` | float | 0.70 | Total plant height (meters) |
| `spread` | float | 0.35 | Horizontal spread radius (meters) |

**Proportions**: `spread` typically 0.5-0.7× of `height` for natural look.

### Leaves

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `leaf_count` | int | 58 | Total number of leaves |
| `leaf_length` | float | 0.08 | Average leaf length (meters) |
| `leaf_width` | float | 0.035 | Average leaf width (meters) |
| `leaf_thickness` | float | 0.002 | Leaf thickness for volume (meters) |
| `leaf_variation` | float | 0.2 | Size variation (0-1, 0.2 = ±20%) |

**Performance impact**: Each leaf adds ~2-4 polygons. Keep `leaf_count` < 100 for mobile.

**Appearance tips**:
- Increase `leaf_count` for fuller plants
- Increase `leaf_length` and `leaf_width` proportionally for larger leaves
- Higher `leaf_variation` (0.3-0.4) adds more organic randomness

### Branches

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `main_stems` | int | 4 | Number of main stems from base |
| `branches_per_stem` | int | 2 | Secondary branches per main stem |
| `branch_thickness` | float | 0.003 | Branch radius (meters) |
| `branch_segments` | int | 4 | Detail level in branch curves |

**Structure**: Total branches = `main_stems` × (1 + `branches_per_stem`)

### Distribution

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `vertical_clustering` | float | 0.7 | How much leaves cluster by height (0-1) |
| `random_seed` | int | 42 | Seed for reproducible randomness |

**Clustering**:
- `0.0`: Leaves evenly distributed
- `0.5`: Some clustering
- `1.0`: Leaves tightly grouped by height

**Random seed**: Change this to get different leaf arrangements with same parameters.

### Materials

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `leaf_color` | RGBA | (0.15, 0.45, 0.12, 1.0) | Leaf color (rich green) |
| `leaf_roughness` | float | 0.4 | Leaf surface roughness |
| `leaf_specular` | float | 0.3 | Leaf specular highlight |
| `branch_color` | RGBA | (0.25, 0.18, 0.12, 1.0) | Branch color (brown) |
| `branch_roughness` | float | 0.9 | Branch surface roughness |

**Color variations**:
```python
# Lighter green (new growth)
'leaf_color': (0.25, 0.55, 0.20, 1.0)

# Darker green (shade plant)
'leaf_color': (0.10, 0.35, 0.08, 1.0)

# Autumn colors
'leaf_color': (0.7, 0.4, 0.1, 1.0)  # Orange-yellow
```

---

## Potted Plant Composer

**File**: `scripts/generators/generate_potted_plant.py`

### Component Paths

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `pot_file` | string | "Pot.blend" | Pot component filename (in library/) |
| `foliage_file` | string | "Foliage.blend" | Foliage component filename (in library/) |

**Mixing components**: Change these to use different pot/foliage combinations.

### Positioning

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `foliage_z_offset` | float | 0.32 | Height to place foliage base (meters) |
| `foliage_scale` | float | 1.0 | Scale factor for foliage |

**Alignment**: `foliage_z_offset` should be just above the pot rim for natural planting.

### Dirt Surface

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dirt_z` | float | 0.329 | Height of dirt surface (meters) |
| `dirt_radius` | float | 0.22 | Radius of dirt surface (meters) |
| `dirt_segments` | int | 16 | Detail of dirt surface circle |

**Positioning guide**:
- `dirt_z` should be slightly below pot rim (~0.01-0.02m)
- `dirt_radius` should be slightly smaller than pot inner radius

### Dirt Material

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dirt_color` | RGBA | (0.18, 0.12, 0.08, 1.0) | Dirt color (dark brown) |
| `dirt_roughness` | float | 0.95 | Dirt surface roughness (very matte) |

---

## Scene Composer

**File**: `scripts/compose_game_scene.py`

### Plant Placement

Currently hardcoded in `compose_scene()`:

```python
plant1.location = (-1.0, 2.5, -0.1)  # Left plant
plant2.location = (1.0, 2.5, -0.1)   # Right plant
plant2.rotation_euler = (0, 0, 0.5)  # Slight rotation
```

**Coordinate system**:
- X: left (-) / right (+)
- Y: forward (+) / backward (-)
- Z: up (+) / down (-)

**Visibility**: Keep Y > 2.0 to be behind character in "playing" camera view.

---

## Tips for Parameter Adjustment

### Start Conservative
1. Make small changes (10-20% adjustments)
2. Regenerate and test
3. Iterate until desired result

### Balance Quality and Performance
- **High quality**: More segments, more leaves, more detail
- **Performance**: Fewer segments, fewer leaves, simpler geometry
- **Target**: 500-2000 polys per asset for mobile

### Maintain Proportions
When scaling an asset, adjust related parameters proportionally:
```python
# Make plant 1.5× larger
'height': 0.70 * 1.5,      # 1.05m
'spread': 0.35 * 1.5,      # 0.525m
'leaf_length': 0.08 * 1.5, # 0.12m
'leaf_width': 0.035 * 1.5, # 0.0525m
```

### Use Analyzer
After changes, always check:
```bash
blender --background --python scripts/tools/asset_analyzer.py -- library/MyAsset.blend
```

---

## Common Adjustments

### "Plant too sparse"
```python
'leaf_count': 75,           # Increase
'branches_per_stem': 3,     # Add more branches
```

### "Plant too dense/cluttered"
```python
'leaf_count': 40,           # Decrease
'spread': 0.40,             # Increase spread
```

### "Leaves look flat"
```python
'leaf_thickness': 0.003,    # Increase (from 0.002)
'leaf_specular': 0.5,       # More shine
```

### "Pot too plain"
```python
'rim_flare': 0.06,          # More decorative rim
'height_segments': 5,       # More shape detail
# Or: add texture in material nodes
```

### "Wrong size/scale"
Check the analyzer output for actual dimensions:
```
Bounds:
  Size: 0.480 × 0.480 × 0.700 m
```

Adjust parameters to match desired real-world size.

