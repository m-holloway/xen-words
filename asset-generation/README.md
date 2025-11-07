# Asset Generation Infrastructure

## Overview

This directory contains the **procedural asset pipeline** for generating and managing 3D assets used in xen-words. Assets are created from version-controlled Python scripts with adjustable parameters.

## 🚀 Quick Start

### Generate Assets
```bash
cd /Users/michaelholloway/dev/xen-words

# Generate individual assets
blender --background --python asset-generation/generators/generate_pot.py
blender --background --python asset-generation/generators/generate_foliage.py
blender --background --python asset-generation/generators/generate_potted_plant.py

# Compose scene from library assets
blender --background --python asset-generation/composers/compose_game_scene.py

# Or rebuild everything
blender --background --python asset-generation/tools/rebuild_all.py
```

### Analyze Assets
```bash
blender --background --python asset-generation/tools/asset_analyzer.py -- assets/models/library/PottedPlant.blend
```

## 📁 Structure

```
asset-generation/
├── generators/              # Procedural asset generators
│   ├── generate_pot.py
│   ├── generate_foliage.py
│   └── generate_potted_plant.py
│
├── tools/                   # Pipeline tools
│   ├── asset_analyzer.py
│   └── rebuild_all.py
│
├── composers/               # Scene composition
│   └── compose_game_scene.py
│
├── docs/                    # Comprehensive documentation
│   ├── PROCEDURAL_WORKFLOW.md
│   ├── ASSET_PARAMETERS.md
│   ├── LESSONS_LEARNED.md
│   └── INFRASTRUCTURE_SUMMARY.md
│
├── README.md               # This file
├── INFRASTRUCTURE_SUMMARY.md
└── REFACTORING_REVIEW.md
```

## 📚 Documentation

Start here based on what you need:

### I want to...

**...adjust an existing asset**
→ Read [PROCEDURAL_WORKFLOW.md](docs/PROCEDURAL_WORKFLOW.md) → "Scenario 1: Adjusting an Existing Asset"

**...know what parameters I can change**
→ Read [ASSET_PARAMETERS.md](docs/ASSET_PARAMETERS.md)

**...understand why things are designed this way**
→ Read [LESSONS_LEARNED.md](docs/LESSONS_LEARNED.md)

**...get a high-level overview**
→ Read [INFRASTRUCTURE_SUMMARY.md](INFRASTRUCTURE_SUMMARY.md)

**...review before committing**
→ Read [REFACTORING_REVIEW.md](REFACTORING_REVIEW.md)

## 🎯 Key Concepts

### Generators are Source of Truth
- Python scripts define how assets are created
- Parameters at top of files control appearance
- .blend files in `assets/models/library/` are generated outputs

### Compositional Architecture
```
Pot.blend (standalone)     ──┐
                             ├──> PottedPlant.blend
Foliage.blend (standalone) ──┘
```

### Parametric Adjustments
```python
# In generate_foliage.py:
FOLIAGE_CONFIG = {
    'height': 0.70,      # Easy to change
    'leaf_count': 58,    # Clear meaning
    # ...
}
```

## 🔄 Typical Workflow

1. **Edit** generator parameters
2. **Run** generator script
3. **Analyze** output (optional)
4. **Compose** into scene
5. **Test** in Flutter app

See [docs/PROCEDURAL_WORKFLOW.md](docs/PROCEDURAL_WORKFLOW.md) for details.

## 📊 What Gets Generated

| Generator | Output | Location | Polys |
|-----------|--------|----------|-------|
| `generate_pot.py` | Pot.blend | assets/models/library/ | ~128 |
| `generate_foliage.py` | Foliage.blend | assets/models/library/ | ~1770 |
| `generate_potted_plant.py` | PottedPlant.blend | assets/models/library/ | ~1900 |
| `compose_game_scene.py` | GameScene.blend + GLB | assets/models/scenes/ & exports/ | ~3800 |

## 🛠️ Tools

### Asset Analyzer
Analyzes .blend files for quality, performance, and issues.

```bash
blender --background --python asset-generation/tools/asset_analyzer.py -- assets/models/library/MyAsset.blend
```

**Reports**:
- Polygon counts
- Material usage
- Geometry issues
- Mobile performance estimate
- Bounding box dimensions

### Rebuild All
Regenerates entire asset library from generators.

```bash
blender --background --python asset-generation/tools/rebuild_all.py
```

**Does**:
1. Generates Pot.blend
2. Generates Foliage.blend
3. Composes PottedPlant.blend
4. Composes GameScene.blend
5. Exports GameScene.glb

## 🎓 Best Practices

1. **Always analyze after generation**
   ```bash
   blender --background --python asset-generation/tools/asset_analyzer.py -- assets/models/library/NewAsset.blend
   ```

2. **Keep parameters at top of files**
   - Makes them easy to find and adjust
   - Documents what can be changed

3. **Use rebuild_all.py for safety**
   - Ensures all dependencies are up to date
   - Catches errors early

4. **Document new parameters**
   - Update `docs/ASSET_PARAMETERS.md`
   - Add usage examples

5. **Commit generators, not .blend files**
   - Generators are source of truth
   - .blend files can be regenerated

## 📈 Performance Targets

- **Per-asset**: 500-2000 polygons (mobile)
- **Scene total**: < 5000 polygons
- **Materials**: < 8 per asset
- **Current**: 3800 polygons (✅ 24% under budget)

## 🔗 Related

- **Asset Library**: `assets/models/library/` - Generated .blend files
- **Scenes**: `assets/models/scenes/` - Composed scenes
- **Exports**: `assets/models/exports/` - Game-ready GLB files
- **Flutter Integration**: `lib/widgets/character_view.dart` - Loads GLB assets

## 💡 Tips

### Making Plants Taller
```python
# In generate_foliage.py:
'height': 0.85,  # Was 0.70
```

### Making Pots Wider
```python
# In generate_pot.py:
'top_radius': 0.30,  # Was 0.24
```

### Adding More Leaves
```python
# In generate_foliage.py:
'leaf_count': 75,  # Was 58
```

### Testing Changes
```bash
# After editing a generator:
blender --background --python asset-generation/generators/generate_foliage.py
blender --background --python asset-generation/generators/generate_potted_plant.py
blender --background --python asset-generation/composers/compose_game_scene.py

# Then restart app (hot reload doesn't work for 3D assets):
flutter run
```

---

**For complete documentation, see the `docs/` folder.**

