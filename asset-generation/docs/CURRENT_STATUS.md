# Current Scene Status

## Completed Features ✅

### 1. Personalized Welcome Rug
- **Status**: Fully functional and dynamic
- **Implementation**: Pure Flutter/Dart solution (no Blender subprocess required)
- **Features**:
  - Runtime texture generation using `dart:ui` Canvas
  - GLB modification to inject custom texture into template
  - Persistent child name via `shared_preferences`
  - 10 font options with live preview in settings:
    - Playful: Quicksand, Fredoka, Chewy, Rubik Bubbles
    - Clean: Nunito, Righteous
    - Quirky: Galindo, Pacifico
    - Elegant Scripts: Lavishly Yours, Ballet
  - Automatic regeneration when settings change
  - Custom loading overlay with error handling
- **Performance**: Texture generation takes ~500ms, cached after first load
- **Files**:
  - `lib/utils/glb_texture_replacer.dart` - GLB binary manipulation
  - `lib/widgets/character_view.dart` - Texture generation and loading
  - `lib/widgets/rug_loading_overlay.dart` - Loading UI
  - `lib/widgets/settings_page.dart` - Font picker with previews
  - `assets/models/library/Rug.glb` - Template with placeholder texture

### 2. Shoji Panel Backdrop
- **Status**: Complete and optimized
- **Implementation**: Three-object design with procedural textures
- **Architecture**:
  - `TopPanel`: Full-width static panel above the opening
  - `BackdropLeft` & `BackdropRight`: Side panels with central opening
- **Visual Details**:
  - Consistent shoji grid pattern (1m x 1m sub-panels)
  - Dark wood frames (RGB: 0.35, 0.25, 0.18)
  - White translucent paper panels
  - Texture-based geometry for performance (3 quads total)
  - Pixel-perfect frame thickness across all panels
- **Performance**: ~6 triangles total, single 3072px texture for top panel, 1024px for sides
- **Files**:
  - `asset-generation/generators/generate_backdrop.py` - Generator with texture creation
  - `assets/models/library/Backdrop.blend` - Three separate objects

### 3. Fusuma Panels (Foreground Framing)
- **Status**: Present but simple
- **Implementation**: Two solid panels flanking the scene
- **Position**: 5 units apart, at Y=-2.0 (foreground)
- **Purpose**: Frame the view and add depth
- **Files**:
  - `asset-generation/generators/generate_fusuma.py` - Simple quad generator
  - `assets/models/library/Fusuma.blend` - Single flat panel

### 4. Scene Integration
- **Status**: Working with proper depth layering
- **Depth Ordering** (back to front in Blender Y, which becomes Z in Thermion):
  - Backdrop panels: Y=3.5
  - Plants: Y=2.5
  - Character: Y=0.0
  - Rug: Y=0.0
  - Fusuma panels: Y=-2.0 (closest to camera)
- **Files**:
  - `asset-generation/composers/compose_game_scene.py` - Scene assembly
  - `assets/models/exports/GameScene.glb` - Final composed scene

## Pending/Incomplete Features 🚧

### 1. Books Asset
- **Status**: Generated but removed from scene
- **Reason**: Don't fit the aesthetic; need refinement
- **Files**: `assets/models/library/Books.blend` (preserved but unused)
- **Future Work**: 
  - Consider simpler design (e.g., a single stacked book set)
  - Better materials/textures
  - More intentional placement

## Technical Documentation

### Coordinate System
- **Blender**: Z-up (X-right, Y-depth, Z-height)
- **Thermion/Flutter**: Y-up (X-right, Y-height, Z-depth)
- **Conversion**: Automatic during GLB export (90° rotation around X-axis)
- **See**: `asset-generation/docs/COORDINATE_SYSTEMS.md`

### Key Learnings
- **Face normals**: Must point toward camera for proper rendering
- **Z-fighting**: Requires small offsets between overlapping geometry
- **Transparency**: Use `BLEND` material mode + alpha channel for GLB export
- **Texture-based geometry**: Far more efficient than actual subdivided geometry
- **GLB modification**: Can inject textures at runtime by parsing binary format
- **See**: `asset-generation/docs/LESSONS_LEARNED.md`

### Performance Metrics
- **Total Scene Poly Count**: ~1,200 triangles (well under 5K budget)
  - Character: ~1,000 (from original model)
  - Rug: 128 triangles
  - Backdrop: ~6 triangles (3 quads)
  - Fusuma: 4 triangles (2 quads)
  - Floor/other: ~60 triangles
- **Texture Memory**: ~4MB total
  - Rug: 1024x1024 PNG (~500KB compressed)
  - Backdrop: 3072x1024 + 2x 1024x1024 (~2MB)
  - Other assets: ~1.5MB

## Known Issues

### 1. Font Loading Delay
- **Issue**: First time a Google Font is used, there's a network delay
- **Impact**: Initial rug generation may take 1-2 seconds
- **Workaround**: Fonts are cached after first download
- **Future**: Could pre-load popular fonts on app startup

### 2. Rug Regeneration Timing
- **Issue**: Changing font requires full app restart to see updated rug
- **Why**: `_onViewerAvailable` callback only fires once per viewer lifecycle
- **Workaround**: User must restart app after changing settings
- **Future**: Implement hot reload for rug asset or scene refresh mechanism

## Future Enhancements 🔮

### High Priority
1. **Lighting**: Scene could use more dynamic lighting
   - Ambient occlusion
   - Subtle directional light (window light simulation)
   - Character rim lighting

2. **Animation**: More life in the scene
   - Plant leaves gentle sway
   - Subtle camera movement
   - Character breathing/idle animation

3. **Polish**:
   - Shadows (character on rug, plants on floor)
   - More refined materials (less flat colors)
   - Subtle texture on wood floor

### Medium Priority
4. **Additional Assets**:
   - Refined books (simpler, cleaner design)
   - Small decorative elements (cushion, tea set?)
   - Background details visible through backdrop opening

5. **Rug Enhancements**:
   - More customization options (colors, patterns)
   - Multiple rug shape options
   - Animated texture effects

### Low Priority
6. **Performance**:
   - LOD system for character
   - Texture atlasing
   - Progressive asset loading

## Testing Notes

### What Works Well
- ✅ Backdrop looks clean and professional
- ✅ Rug personalization is delightful and performant
- ✅ Font picker UI is intuitive with good previews
- ✅ Depth layering creates good spatial feel
- ✅ Overall aesthetic is cohesive (Zen/minimalist)

### What Needs Work
- ⚠️ Scene feels a bit empty/sterile (needs small details)
- ⚠️ Lighting is flat (no depth from shadows/highlights)
- ⚠️ Some materials are too flat/matte
- ⚠️ Fusuma panels are very simple (could be more detailed)

## Asset Generation Workflow

### To Update/Regenerate Assets:
1. **Modify generator**: Edit `asset-generation/generators/generate_*.py`
2. **Run via MCP**: Use Blender MCP tools to execute generator
3. **Validate**: Load in Blender and check appearance/poly count
4. **Compose scene**: Run `compose_game_scene.py` to update `GameScene.glb`
5. **Test in app**: Full app restart required to see changes

### Generator Scripts
- `generate_backdrop.py` - Shoji panels with procedural textures
- `generate_rug.py` - Circular rug with UV mapping
- `generate_fusuma.py` - Simple flat panels
- `generate_books.py` - Stylized book stack (unused)

### Composer Script
- `compose_game_scene.py` - Assembles all assets into final GLB

