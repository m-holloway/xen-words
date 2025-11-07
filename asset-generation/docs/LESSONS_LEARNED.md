# Critical Lessons Learned - Asset Generation

This document captures important lessons learned during asset generation, particularly around common pitfalls and how to avoid them.

## Face Normals and Geometry Issues

### Problem: Diagonal/Warped Appearance
**Symptom:** Rectangular panels appear diagonal or warped in the rendered output, even though geometry is correct.

**Root Cause:** 
- Face normals pointing in wrong direction (backward instead of forward)
- Inconsistent vertex winding order
- Z-fighting when multiple faces occupy the same space

**Solution:**
1. **Always recalculate normals after geometry creation:**
   ```python
   bpy.ops.object.mode_set(mode='EDIT')
   bpy.ops.mesh.select_all(action='SELECT')
   bpy.ops.mesh.normals_make_consistent(inside=False)
   bpy.ops.object.mode_set(mode='OBJECT')
   ```

2. **Ensure consistent vertex winding order:**
   - For faces viewed from front (positive Y in Blender), use counter-clockwise winding
   - Order: top-left → top-right → bottom-right → bottom-left
   - This ensures normals point forward (toward camera)

3. **Prevent z-fighting:**
   - Offset overlapping geometry slightly (e.g., panels 0.001 units behind frames)
   - Never place multiple faces at exact same position
   - Use different materials for different depth layers

### Example: Shoji Panel Generation
When creating shoji panels with frames and translucent centers:
- Frames at Y=0.0 (wood material)
- Panels at Y=-0.001 (translucent paper material, slightly behind)
- This prevents z-fighting and flickering

## Coordinate System Conversion

### Blender (Z-up) vs Thermion (Y-up)
**Critical:** Blender uses Z-up coordinate system, but Thermion uses Y-up.

**Conversion Rules:**
- Blender: (X, Y, Z) where Z is up, Y is forward/back
- Thermion: (X, Y, Z) where Y is up, Z is forward/back
- During GLB export, Blender automatically converts Z-up → Y-up

**Positioning Notes:**
- In Blender, positive Y = forward (toward camera)
- In Thermion, positive Z = forward (toward camera)
- To place something BEHIND character in Thermion, use positive Y in Blender
- To place something IN FRONT of character in Thermion, use negative Y in Blender

**Common Mistake:**
Placing backdrop at `(0, -3.5, 0)` in Blender places it IN FRONT of camera in Thermion.
Correct: `(0, 3.5, 0)` in Blender places it BEHIND character in Thermion.

See `COORDINATE_SYSTEMS.md` for detailed documentation.

## Material and Texture Issues

### Procedural Textures Don't Export Well
**Problem:** Procedural textures (noise, gradient) often don't export to GLB format.

**Solution:** Use image textures instead:
1. Generate image programmatically using numpy
2. Create Blender image from pixel data
3. Pack image into blend file (`image.pack()`)
4. Connect to material via Image Texture node
5. **Critical:** Connect UV coordinates to texture Vector input

### Transparency and Z-Fighting
**Problem:** Transparent materials can cause flickering when faces overlap.

**Solution:**
- Reduce transparency (alpha 0.95-0.98 instead of 0.85)
- Offset overlapping geometry
- Enable backface culling (`mat.use_backface_culling = True`)
- Use transmission weight sparingly (0.1-0.2 max)

### Material Assignment
**Problem:** Materials not applying correctly to faces.

**Solution:**
- Set `face.material_index` when creating faces
- Append materials to object in correct order (index 0, 1, 2...)
- Verify material indices match face indices

## Geometry Creation Best Practices

### Flat Surfaces
When creating flat rectangular panels:
- Use same Y (depth) value for all corners of rectangle
- Calculate curve depth at rectangle center, not per-corner
- This prevents warping/diagonal appearance

### UV Mapping
**Always create UV layer:**
```python
uv_layer = bm.loops.layers.uv.new("UVMap")
```

**Assign UVs when creating faces:**
```python
for i, loop in enumerate(face.loops):
    u = (i % 2) * 1.0  # Simple mapping
    v = (i // 2) * 1.0
    loop[uv_layer].uv = (u, v)
```

### Vertex Winding Order
**Critical for correct normals:**
- Counter-clockwise when viewed from front
- Consistent across all faces
- Affects which side of face is visible

## GLB Export Considerations

### Multiple Materials
- GLB exporter creates separate primitives for each material
- Export log shows "Primitives created: 2" for two-material object
- This is correct and expected

### Transparency
- Alpha blending must be enabled (`blend_method = 'BLEND'`)
- Alpha value in BSDF inputs controls transparency
- Some renderers may not support transparency well

### Texture Embedding
- Use `image.pack()` to embed textures in blend file
- Packed textures export with GLB automatically
- External textures may not be included

## Debugging Workflow

### Validate Geometry
1. Check vertex positions match expectations
2. Verify face normals point correct direction
3. Check for overlapping faces (z-fighting)
4. Verify material assignment

### Use Blender MCP for Validation
```python
# Take screenshot to see actual result
mcp_blender_get_viewport_screenshot()

# Check object info
mcp_blender_get_object_info("Backdrop")

# Verify materials
# Check face counts, normals, etc.
```

### Common Checks
- **Polygon count:** Should match expected (e.g., 379 for shoji backdrop)
- **Material slots:** Should match number of materials
- **Y positions:** Should have clear separation (frames vs panels)
- **Face normals:** Should point forward (positive Y in Blender)

## Performance Considerations

### Polygon Budget
- Keep assets within budget (e.g., backdrop: 32-400 polygons)
- Use instancing for repeated elements (e.g., plants)
- Optimize grid subdivisions based on viewing distance

### Texture Resolution
- 1K (1024x1024) is usually sufficient for backgrounds
- Higher resolutions increase file size
- Consider texture compression

## Testing Checklist

Before finalizing an asset:
- [ ] Geometry is correct (no warping, proper rectangles)
- [ ] Face normals point forward
- [ ] No z-fighting (faces at different depths)
- [ ] Materials assigned correctly
- [ ] Textures embedded (if using images)
- [ ] UV mapping correct
- [ ] Exports to GLB without errors
- [ ] Visual validation in Blender viewport
- [ ] Test in target application (Thermion/Flutter)

## References

- `COORDINATE_SYSTEMS.md` - Detailed coordinate conversion guide
- `PROCEDURAL_WORKFLOW.md` - Asset generation workflow
- `TEXTURE_APPLICATION.md` - Texture application challenges
