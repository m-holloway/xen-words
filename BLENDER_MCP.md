# Blender MCP Integration

## Overview

This project uses **Blender MCP** (Model Context Protocol) to create and modify 3D assets directly from the development environment. The MCP server provides programmatic access to Blender, allowing us to create, texture, and export 3D models without manual Blender interaction.

## What is Blender MCP?

Blender MCP is a Model Context Protocol server that connects Cursor (or other MCP-compatible tools) to Blender, enabling:
- **Programmatic 3D modeling** - Create and modify objects via code
- **Automated texturing** - Download and apply materials from Polyhaven
- **Asset export** - Export to GLB/GLTF for use in games
- **Scene management** - Full control over Blender scenes
- **Live preview** - Take screenshots of the viewport

## Setup

### Prerequisites
1. **Blender** installed on your system
2. **Blender MCP addon** installed and enabled in Blender
3. **MCP configuration** in `.cursor/mcp.json`

### Starting the Server
1. Launch Blender
2. Go to `Edit > Preferences > Add-ons`
3. Find the Blender MCP addon
4. Enable it and click "Start Server"
5. The addon should show "Server Running" status

## Available Resources

### Polyhaven Integration
Blender MCP provides access to **Polyhaven**, a free library of PBR textures, HDRIs, and 3D models.

**Categories available:**
- Textures: floor (230+), wall (216+), terrain (126+), concrete (86+), wood (71+), etc.
- HDRIs: Various environment maps
- Models: Various 3D models

**Quality:** Professional PBR materials with multiple maps (Diffuse, Normal, Roughness, AO, Displacement)

## Usage Examples

### Creating a Ground Plane

```python
# 1. Create a plane
import bpy
bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
plane = bpy.context.active_object
plane.name = "GroundPlane"
plane.scale = (5, 5, 1)  # Scale to 50m x 50m

# 2. Position it (Z-up in Blender)
plane.location.z = -0.1  # Below character's feet
```

### Applying Polyhaven Textures

```python
# Search for textures
# Categories: floor, wall, terrain, concrete, wood, etc.
# Returns asset list with IDs

# Download texture (available via MCP tools)
# asset_id: e.g., "brushed_concrete"
# asset_type: "textures"
# resolution: "1k", "2k", "4k", "8k"

# Apply to object (available via MCP tools)
# object_name: Name of Blender object
# texture_id: Polyhaven asset ID
```

### Exporting to GLB

```python
import bpy

# Select object(s) for export
bpy.ops.object.select_all(action='DESELECT')
obj = bpy.data.objects.get("ObjectName")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj

# Export as GLB with embedded textures
bpy.ops.export_scene.gltf(
    filepath="/path/to/output.glb",
    export_format='GLB',
    use_selection=True,
    export_materials='EXPORT',
    export_apply=True,
    export_image_format='AUTO'  # Embeds textures
)
```

### Scene Cleanup

```python
import bpy

# Remove default objects
objects_to_delete = ["Cube", "Light"]
for obj_name in objects_to_delete:
    if obj_name in bpy.data.objects:
        obj = bpy.data.objects[obj_name]
        bpy.data.objects.remove(obj, do_unlink=True)
```

## Project Assets Created

### Ground Plane
- **Source:** `assets/models/GroundPlane.blend` (5.7 MB)
  - Editable Blender file with material nodes
  - All texture maps included
  
- **Export:** `assets/models/GroundPlane.glb` (2.4 MB)
  - Embedded textures
  - Ready for use in Flutter/Thermion
  
- **Texture:** Polyhaven "Brushed Concrete" (1K resolution)
  - Diffuse, Normal, Roughness, AO, Displacement maps
  - Professional PBR material
  - Subtle, clean appearance perfect for kids' app

### Integration in Flutter
```dart
// Load ground plane in character_view.dart
Future<void> _createGroundPlane(ThermionViewer viewer) async {
  await viewer.loadGltf(
    'assets/models/GroundPlane.glb',
    addToScene: true,
  );
}
```

## Best Practices

### File Organization
1. **Keep source files:** Save `.blend` files in `assets/models/` for future editing
2. **Export to GLB:** Use GLB for game assets (smaller, embedded textures)
3. **Use 1K textures:** Balance quality and file size for mobile

### Coordinate Systems
- **Blender:** Z-up (Z is vertical)
- **Thermion/Flutter:** Y-up (Y is vertical)
- When positioning in Blender Z=-0.1, it becomes Y=-0.1 in Thermion

### Texture Selection
- **Concrete/Stone:** Neutral, professional look
- **Wood:** Warmer, more organic feel
- **Avoid busy patterns:** Kids' app should be clean and focused

### Performance
- **Use 1K textures** for ground planes (sufficient detail)
- **2K textures** for hero objects/characters
- **GLB format** embeds textures (fewer HTTP requests)
- **Test on target device** to ensure smooth performance

## Troubleshooting

### "Could not connect to Blender"
1. Ensure Blender is running
2. Check MCP addon is enabled in Blender preferences
3. Verify "Start Server" was clicked in addon settings
4. Restart Blender if needed

### Textures not appearing
1. Switch viewport to "Material Preview" or "Rendered" mode
2. Check object has UV mapping
3. Verify texture nodes are connected in Shader Editor

### Export file too large
1. Use lower resolution textures (1K instead of 2K/4K)
2. Use `export_image_format='JPEG'` for smaller files
3. Consider texture compression options

## Future Enhancements

### Potential Additions
- **Animated props** (bouncing balls, floating objects)
- **Environment objects** (clouds, trees, buildings)
- **Particle effects** (confetti, sparkles)
- **Custom character variations** (different colors, accessories)

### Workflow Ideas
1. **Iterate in Blender:** Make changes, export, hot reload in Flutter
2. **Asset library:** Build collection of reusable props
3. **Procedural generation:** Use Blender Python API for variations
4. **Batch export:** Script multiple assets at once

## Resources

- **Polyhaven:** https://polyhaven.com/ - Free PBR textures, HDRIs, models
- **Blender Python API:** https://docs.blender.org/api/current/
- **glTF/GLB Spec:** https://www.khronos.org/gltf/
- **Thermion Docs:** Flutter 3D rendering package documentation

## Notes

- MCP provides a powerful workflow for 3D asset creation
- Polyhaven integration eliminates need for manual texture downloads
- Programmatic approach ensures repeatability and documentation
- Perfect for rapid prototyping and iteration


