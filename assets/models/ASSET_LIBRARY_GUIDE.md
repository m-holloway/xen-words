# 3D Asset Library Structure

## Overview

This document describes the organization of 3D assets for the xen-words project, designed for modularity, reusability, and scalability.

## Directory Structure

```
assets/models/
├── library/              # Reusable asset components (building blocks)
│   ├── PottedPlant.blend # Single potted plant (28 polys)
│   ├── GroundPlane.blend # Floor surface (1 poly)
│   └── ...               # Future assets (chairs, tables, etc.)
│
├── scenes/               # Composed scenes (asset instances)
│   └── GameScene.blend   # Main game scene (composes library assets)
│
├── exports/              # Final GLB exports for game engine
│   └── GameScene.glb     # Exported scene for Thermion
│
└── [legacy files]        # Old monolithic files (can be removed)
    ├── GroundPlane.blend # Old combined file
    └── GroundPlane.glb   # Old export
```

## Design Principles

### 1. Separation of Concerns
- **Library assets**: Single, reusable components at origin (0,0,0)
- **Scene files**: Compositions that instance library assets with positions/rotations
- **Exports**: Final GLB files for the game engine

### 2. Asset Instances
- Use **instances** (shared mesh data) not duplicates for memory efficiency
- Example: 2 plants in scene = 2 objects, 1 mesh data block
- Reduces memory: 28 polys × 1 = 28 polys, not 56

### 3. Material Organization
- Keep materials with assets in library files
- Materials travel with assets when appended/linked to scenes
- Use descriptive names: `ConcretePotMaterial`, `LeafMaterial`, etc.

## Working with Assets

### Creating a New Asset

1. **Model the asset** in Blender centered at origin (0,0,0)
2. **Name clearly**: Use descriptive names like `ChairModern`, `TableWood`
3. **Keep it low-poly**: Target 10-100 polys for mobile
4. **Apply transforms**: Rotation=0, Scale=1
5. **Save in library/**: `assets/models/library/AssetName.blend`

### Composing a Scene

1. **Open/Create scene file**: `scenes/SceneName.blend`
2. **Append assets** from library:
   ```python
   # In Blender Python console:
   import bpy
   
   # Append an asset
   asset_path = "library/PottedPlant.blend"
   with bpy.data.libraries.load(asset_path) as (data_from, data_to):
       data_to.objects = ["PottedPlant"]
   
   for obj in data_to.objects:
       bpy.context.collection.objects.link(obj)
   ```
3. **Position instances**: Move, rotate, scale as needed
4. **Create instances** for reuse:
   ```python
   # Create instance (shares mesh data)
   plant2 = plant1.copy()
   plant2.data = plant1.data  # Important: share geometry!
   plant2.location = (x, y, z)
   bpy.context.collection.objects.link(plant2)
   ```

### Exporting for Game

1. **Open scene file**: `scenes/GameScene.blend`
2. **Export GLB**: File → Export → glTF 2.0 (.glb)
3. **Settings**:
   - Format: GLB (Binary)
   - Include: Selected Objects (or check your needs)
   - Transform: +Y Up
   - Geometry: Apply Modifiers ✓
   - Materials: Export ✓
4. **Save to exports/**: `assets/models/exports/GameScene.glb`

## Current Assets

### PottedPlant.blend
- **Type**: Decorative plant
- **Polys**: 28 (10 pot + 18 leaves)
- **Materials**: 
  - `ConcretePotMaterial` (gray, rough)
  - `LeafMaterial` (green)
- **Size**: ~0.4m tall
- **Usage**: Background decoration, indoor scenes

### GroundPlane.blend
- **Type**: Floor surface  
- **Polys**: 1 (simple quad)
- **Materials**: 
  - `laminate_floor_02_material` (wood texture from Polyhaven)
- **Size**: 20m × 20m
- **Usage**: Base floor for all game scenes

## Integration with Flutter/Thermion

### Current Integration
Game currently loads: `assets/models/GroundPlane.glb`

Referenced in: `lib/widgets/character_view.dart`
```dart
await viewer.loadGltf(
  'assets/models/GroundPlane.glb',
  addToScene: true,
);
```

### Future: Scene System
When we have multiple scenes:

```dart
class SceneManager {
  Future<void> loadScene(String sceneName) async {
    await viewer.loadGltf(
      'assets/models/exports/$sceneName.glb',
      addToScene: true,
    );
  }
}

// Usage
await sceneManager.loadScene('GameScene');
await sceneManager.loadScene('MenuScene');
```

## Best Practices

### Performance (Mobile)
- ✅ Keep total scene < 10k polys
- ✅ Use texture atlases when possible
- ✅ Instance repeated objects (don't duplicate)
- ✅ Use LOD (Level of Detail) for complex assets
- ✅ Bake lighting when possible

### Organization
- ✅ One asset = one .blend file in library/
- ✅ Use clear, descriptive names
- ✅ Center assets at origin in library files
- ✅ Document materials and texture sources
- ✅ Version control .blend files (they're ~2MB, manageable)

### Workflow
- ✅ Modify assets in library/ files only
- ✅ Rebuild scenes when library assets change
- ✅ Re-export GLB when scenes change
- ✅ Test in game after each export

## Adding Polyhaven Textures

When downloading textures from Polyhaven for assets:

1. **Download via MCP** (preserves PBR setup):
   ```python
   # In Blender with MCP addon
   download_polyhaven_asset(
       asset_id="texture_name",
       asset_type="textures",
       resolution="1k"  # mobile-friendly
   )
   ```

2. **Apply to asset** in library file
3. **Save library file** with embedded textures
4. **Materials travel** with asset to scenes

## Future Enhancements

### Asset Library Browser
Blender 3.0+ has built-in asset browser. We can mark assets:
```python
# Mark object as asset
obj.asset_mark()
obj.asset_data.description = "Low-poly potted plant for indoor scenes"
obj.asset_data.tags.new("plant")
obj.asset_data.tags.new("indoor")
```

### Linking vs Appending
- **Append** (current): Copies data into scene, scene is self-contained
- **Link** (advanced): References external file, changes propagate
- For now, use append for simplicity

### Multiple Scenes
As game grows, create:
- `MenuScene.blend` - Main menu environment
- `GameScene.blend` - Gameplay environment
- `TutorialScene.blend` - Tutorial level
- Each composes from same library/

## Migration Notes

### From Old Structure
We migrated from:
- ❌ Monolithic `GroundPlane.blend` (everything mixed)

To:
- ✅ `library/PottedPlant.blend` (reusable asset)
- ✅ `library/GroundPlane.blend` (reusable asset)
- ✅ `scenes/GameScene.blend` (composition)

### Updating the Game
1. Re-export scene: `scenes/GameScene.blend` → `exports/GameScene.glb`
2. Update code to reference: `assets/models/exports/GameScene.glb`
3. Or keep backward compatible: export to both locations during transition

## Questions?

This structure supports:
- ✅ Reusable components
- ✅ Multiple scene compositions
- ✅ Easy asset updates (modify in library, rebuild scenes)
- ✅ Memory-efficient instancing
- ✅ Scalable asset library
- ✅ Clear separation of concerns

For more info on Blender asset workflows:
- [Blender Manual: Asset Libraries](https://docs.blender.org/manual/en/latest/files/asset_libraries/index.html)
- [Best Practices for Game Assets](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html)

