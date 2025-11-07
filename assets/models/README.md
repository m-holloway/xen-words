# 3D Assets Organization

## Overview

We use a **procedural, compositional asset pipeline** where 3D assets are generated from version-controlled Python scripts with adjustable parameters. This enables rapid iteration, reusability, and consistent quality.

## 🎯 Quick Start

### Make a Change to Existing Asset

```bash
# 1. Edit parameters in generator script
nano asset-generation/generators/generate_foliage.py

# 2. Regenerate asset
blender --background --python asset-generation/generators/generate_foliage.py

# 3. Rebuild dependent assets and scene
blender --background --python asset-generation/generators/generate_potted_plant.py
blender --background --python asset-generation/composers/compose_game_scene.py

# 4. Test in game (full restart required)
flutter run
```

### Create New Asset

See [Procedural Workflow Guide](../../asset-generation/docs/PROCEDURAL_WORKFLOW.md) for detailed instructions.

## 📁 Directory Structure

```
assets/models/
├── library/                    # 📦 Generated Assets (binary .blend files)
│   ├── Pot.blend              # Generated from asset-generation/
│   ├── Foliage.blend          # Generated from asset-generation/
│   ├── PottedPlant.blend      # Composed from Pot + Foliage + Dirt
│   └── GroundPlane.blend      # Manual (with procedural texture)
│
├── scenes/                     # 🎬 Scene Compositions
│   └── GameScene.blend        # Composed from library assets
│
├── exports/                    # 📤 Game-Ready GLB Files
│   └── GameScene.glb          # Final export for Thermion
│
├── GroundPlane.glb            # [ACTIVE] Current game export (backward compatible)
└── Rabbit.glb                 # Character model

asset-generation/              # 🔧 Asset Generation Infrastructure (see asset-generation/README.md)
├── generators/                # Procedural asset generators (SOURCE OF TRUTH)
├── tools/                     # Pipeline tools (analyzer, rebuild)
├── composers/                 # Scene composition scripts
└── docs/                      # Comprehensive documentation
```

## 🎨 Asset Pipeline Philosophy

### Generators (Python) = Source of Truth

- **Generator scripts** define how assets are created
- **Parameters** at top of scripts control appearance
- **.blend files** are build artifacts (can be regenerated)
- **Version control** generator scripts, not necessarily .blend files

### Compositional, Not Monolithic

```
✅ PottedPlant = Pot + Foliage + Dirt
   → Can mix different pots and foliage
   → Easy to adjust components independently

❌ PottedPlant = single joined mesh
   → Hard to vary
   → No reusability
```

## 🚀 Common Commands

### Rebuild Everything
```bash
blender --background --python asset-generation/tools/rebuild_all.py
```

### Analyze Asset
```bash
blender --background --python asset-generation/tools/asset_analyzer.py -- assets/models/library/PottedPlant.blend
```

### Rebuild Scene & Export
```bash
blender --background --python asset-generation/composers/compose_game_scene.py
```

## 📊 Current Asset Stats

| Asset | Polys | Materials | Status |
|-------|-------|-----------|--------|
| Pot | 128 | 1 (Concrete) | ✅ Procedural |
| Foliage | ~1770 | 2 (Leaf, Branch) | ✅ Procedural |
| PottedPlant | ~1900 | 4 (Pot, Dirt, Leaf, Branch) | ✅ Compositional |
| GroundPlane | 1 | 1 (Wood) | ⚠️ Manual |
| **Scene Total** | ~3800 | 5 unique | ✅ Mobile-optimized |

## 📚 Documentation

**Asset Generation Pipeline**: See [asset-generation/README.md](../../asset-generation/README.md)

- **[Procedural Workflow](../../asset-generation/docs/PROCEDURAL_WORKFLOW.md)** - How to use the pipeline
- **[Asset Parameters](../../asset-generation/docs/ASSET_PARAMETERS.md)** - Complete parameter reference
- **[Lessons Learned](../../asset-generation/docs/LESSONS_LEARNED.md)** - Best practices & insights
- **[Asset Library Guide](ASSET_LIBRARY_GUIDE.md)** - Detailed library organization
- **[Blender MCP](BLENDER_MCP.md)** - Interactive Blender integration

## 🎯 Design Principles

1. **Procedural > Manual** - Generators are maintainable and reproducible
2. **Compositional > Monolithic** - Small pieces, composed into complex assets
3. **Parameters > Hardcoded** - Adjustable values at top of scripts
4. **Analyzed > Assumed** - Automated quality checks
5. **Documented > Implicit** - Captured knowledge scales the team

## 🔄 Iteration Speed

**Before procedural pipeline**: ~60 minutes per asset adjustment  
**After procedural pipeline**: ~4 minutes per asset adjustment  
**Speedup**: **15× faster iteration**
4. Export to both locations:
   - `exports/GameScene.glb`
   - `GroundPlane.glb` (for game)

### Testing in Game

After rebuilding:
```bash
flutter run
```

The game will load the updated `GroundPlane.glb` automatically.

## Current Assets

### PottedPlant.blend
- **Polygons**: 28 (10 pot + 18 leaves in 3 layers)
- **Materials**: 
  - `ConcretePotMaterial` (brushed concrete texture)
  - `LeafMaterial` (green)
- **Size**: ~0.4m tall
- **Usage**: Background decoration

### GroundPlane.blend
- **Polygons**: 1 (simple quad)
- **Materials**: `laminate_floor_02_material` (wood texture)
- **Size**: 20m × 20m
- **Usage**: Game floor

## Scene Composition

**GameScene.blend** contains:
- 1× GroundPlane (at origin)
- 2× PottedPlant instances (share mesh data)
  - Plant 1: `(-1.0, 2.5, -0.1)` 
  - Plant 2: `(1.0, 2.5, -0.1)` rotated 0.5rad

**Total**: 57 polygons, 3.6MB exported

## Benefits of This Structure

✅ **Modularity**: Each asset is a separate, reusable file  
✅ **Efficiency**: Instances share mesh data (memory-efficient)  
✅ **Maintainability**: Update asset in library/ → rebuild scenes  
✅ **Scalability**: Easy to add new assets and scenes  
✅ **Collaboration**: Clear separation of concerns  

## Migration Status

✅ Separated assets into library/  
✅ Created scene composition system  
✅ Backward compatible exports  
✅ Helper scripts for automation  
⏳ Can remove old `GroundPlane.blend` (root) after migration complete  

## Future: Multiple Scenes

When you need different environments:

```
scenes/
├── GameScene.blend      # Main gameplay
├── MenuScene.blend      # Main menu
└── TutorialScene.blend  # Tutorial level
```

Each composes from the same `library/` assets!

## Documentation

- **Detailed guide**: `ASSET_LIBRARY_GUIDE.md` (full workflow, best practices)
- **This file**: Quick reference for daily work

## Questions?

The structure supports your growth from simple scenes to complex, multi-environment games while keeping assets organized and reusable! 🚀

