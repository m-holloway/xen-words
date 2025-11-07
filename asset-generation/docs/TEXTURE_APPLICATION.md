# Texture Application Guide

## Current Status

### ✅ Working: Static Textures in GLB
- Textures embedded in GLB files work perfectly
- Example: Ground plane with Polyhaven wood texture
- Textures are baked into the GLB during export

### ⚠️ Limitation: Runtime Texture Application
- **Rug personalized texture**: Generated at runtime but not yet applied
- **Issue**: Thermion doesn't provide a straightforward API to modify materials/textures on loaded GLB objects
- **Current state**: Texture is generated and cached, but not visible in scene

---

## Rug Texture Implementation

### What's Working
1. ✅ Texture generation (`lib/utils/rug_texture_generator.dart`)
   - Generates 1024×1024 PNG with child's name
   - Three-layer composition (weave pattern, name, fabric texture)
   - Caching system for performance

2. ✅ Texture file creation
   - Saved to app cache directory
   - Ready for application

### What's Missing
- **Texture application to rug object**
- Rug geometry is loaded as part of `GameScene.glb`
- No Thermion API found to modify materials at runtime

---

## Potential Solutions

### Option 1: Load Rug Separately (Recommended)
Load the rug as a separate GLB and apply texture before adding to scene:

```dart
// Load rug separately
final rugAsset = await viewer.loadGltf(
  'assets/models/library/Rug.glb',
  addToScene: false,  // Don't add yet
);

// Apply texture (if Thermion API supports it)
// await viewer.setTexture(rugAsset, texturePath);

// Then add to scene
await viewer.addToScene(rugAsset);
```

**Pros**: More control over rug object
**Cons**: Requires Thermion API support for texture modification

### Option 2: Pre-generate Rug GLBs
Generate multiple GLB files with different names baked in:

```python
# In Blender, generate multiple rug variants
for name in ["Xen Words", "Addy", "Default"]:
    # Load texture
    # Apply to rug material
    # Export as Rug_{name}.glb
```

**Pros**: Works with current Thermion capabilities
**Cons**: Requires pre-generating variants, not truly dynamic

### Option 3: Use Separate Material System
Create rug with a material that can be swapped:

```dart
// Load rug with placeholder material
// Replace material node at runtime
// (Requires Thermion material API)
```

**Pros**: Dynamic texture application
**Cons**: May not be supported by Thermion

### Option 4: Investigate Thermion Material API
Check if Thermion provides:
- `ThermionAsset.setMaterial()`
- `ThermionViewer.replaceTexture()`
- Material modification methods

**Next step**: Review Thermion package documentation/API

---

## Backdrop Texture Enhancement

### Current State
- Solid color material (off-white/cream)
- Appears flat and untextured

### Enhancement Applied
- Added subtle noise texture for variation
- 15% noise influence for subtle texture
- Maintains clean, minimal aesthetic

### Future Improvements
- Could add very subtle gradient (darker at edges)
- Could add soft vertical lines (wall texture)
- Keep it subtle - backdrop should not distract

---

## Best Practices

### For Static Textures (GLB-embedded)
1. ✅ Use Polyhaven or similar PBR textures
2. ✅ Embed in GLB during export
3. ✅ Use 1K resolution for background elements
4. ✅ Use 2K resolution for hero objects

### For Runtime Textures
1. ⚠️ Currently limited by Thermion API
2. ✅ Generate textures efficiently (cache aggressively)
3. ✅ Use appropriate resolution (1024×1024 for rug)
4. ⚠️ May need to pre-generate variants

---

## Testing Checklist

- [ ] Rug texture generation works
- [ ] Rug texture is cached correctly
- [ ] Rug texture file exists at expected path
- [ ] Rug geometry loads correctly
- [ ] Backdrop has subtle texture variation
- [ ] No performance impact from texture generation

---

## Related Documentation

- [COORDINATE_SYSTEMS.md](COORDINATE_SYSTEMS.md) - Positioning assets
- [PROCEDURAL_WORKFLOW.md](PROCEDURAL_WORKFLOW.md) - Asset generation workflow
- [ASSET_PARAMETERS.md](ASSET_PARAMETERS.md) - Material parameters

---

## Next Steps

1. **Investigate Thermion API** for runtime texture/material modification
2. **Test Option 1** (load rug separately) if API supports it
3. **Consider Option 2** (pre-generate variants) as fallback
4. **Document findings** in this file

