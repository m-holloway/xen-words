# Task: Add Polish Assets to Game Scene

## 🎯 Objective

Enhance the game scene with three new assets that create a "cozy learning corner" atmosphere:
1. **Backdrop/Wall** - Creates sense of room vs floating in space
2. **Personalized Rug** - Defines play area with child's name woven in
3. **Stylized Books** - Reinforces learning theme, adds color and personality

**Target**: <300 additional polygons (staying well under 5,000 total budget)

---

## 📚 Required Reading (Start Here!)

Before beginning, familiarize yourself with our pipeline:

1. **[STATUS.md](STATUS.md)** - Current state of pipeline (what's working vs templates)
2. **[docs/PROCEDURAL_WORKFLOW.md](docs/PROCEDURAL_WORKFLOW.md)** - How to use the pipeline
3. **[docs/ASSET_PARAMETERS.md](docs/ASSET_PARAMETERS.md)** - Parameter documentation examples
4. **[generators/generate_pot.py](generators/generate_pot.py)** - Working generator to use as template

**Key Insight**: The pot generator is fully functional. Use it as your reference for creating new generators.

---

## 🎨 Asset Specifications

### Asset 1: Backdrop/Wall

**Purpose**: Create subtle curved wall behind character to frame scene and create "room" feel

**Geometry Requirements**:
- **Type**: Procedural generator
- **Shape**: Curved plane (subtle concave curve facing character)
- **Poly Budget**: ~50-100 polygons
- **Dimensions**: 
  - Width: 5.0m (wide enough to fill camera view)
  - Height: 3.0m (tall enough for framing)
  - Curve: 0.3m depth (subtle, not dramatic)
  - Position: Y = -3.0 to -4.0 (behind character)

**Material**:
- Base color: Soft off-white/cream (0.95, 0.95, 0.92, 1.0)
- Roughness: 0.9 (matte finish)
- Optional: Very subtle noise/texture

**Implementation**:
```python
# Create: asset-generation/generators/generate_backdrop.py

BACKDROP_CONFIG = {
    'width': 5.0,
    'height': 3.0,
    'curve_depth': 0.3,     # How far it curves (concave)
    'segments_width': 8,     # Horizontal subdivisions
    'segments_height': 4,    # Vertical subdivisions
    'base_color': (0.95, 0.95, 0.92, 1.0),
    'roughness': 0.9,
}
```

**Technical Approach**:
- Create grid of vertices with curved X positions
- Use smooth shading
- Simple Principled BSDF material
- Save to `assets/models/library/Backdrop.blend`

---

### Asset 2: Personalized Rug (Two-Part Asset)

**Purpose**: Define play area with child's name woven into fabric texture

**This asset has TWO components:**

#### Part A: Geometry (Procedural Generator)

**Geometry Requirements**:
- **Type**: Procedural generator
- **Shape**: Circle (or rounded rectangle)
- **Poly Budget**: ~32-50 polygons
- **Dimensions**:
  - Radius: 1.5m (covers play area in front of character)
  - Position: Y = 0.5 to 1.0, Z = -0.01 (on floor, in front)
  - Segments: 32 (smooth circle)

**Material**: 
- Will be overridden by runtime texture
- Default: Simple gray placeholder

**Implementation**:
```python
# Create: asset-generation/generators/generate_rug.py

RUG_CONFIG = {
    'shape': 'circle',        # or 'rounded_rect'
    'radius': 1.5,            # meters
    'segments': 32,           # more = smoother
    'thickness': 0.002,       # slight thickness for realism
    'base_color': (0.8, 0.8, 0.8, 1.0),  # placeholder
}
```

**Technical Approach**:
- Create circle/disc with proper UV mapping (crucial for texture!)
- UV coordinates should map 0-1 across circle
- Save to `assets/models/library/Rug.blend`

#### Part B: Texture Generator (Dart/Flutter)

**Purpose**: Generate personalized texture at runtime with child's name

**File Location**: `lib/utils/rug_texture_generator.dart`

**Requirements**:
- Generate 1024×1024 PNG texture
- Three-layer composition:
  1. **Base weave pattern** (subtle diagonal/crosshatch)
  2. **Personalized name** (colored "fibers" woven in)
  3. **Fabric texture overlay** (noise/variation for realism)

**API**:
```dart
class RugTextureGenerator {
  /// Generate personalized rug texture
  /// Returns: Path to cached PNG file
  static Future<String> generate({
    required String childName,
    Color primaryColor = const Color(0xFF8B4513),  // Warm brown
    Color accentColor = const Color(0xFFD2691E),   // Lighter brown
    Color nameColor = const Color(0xFFFFE4B5),     // Cream for name
  }) async {
    // 1. Create 1024x1024 canvas
    // 2. Paint base weave pattern
    // 3. Paint name with "woven fiber" effect
    // 4. Apply fabric texture overlay
    // 5. Save to cache: /app_cache/rug_{name_hash}.png
    // 6. Return file path
  }
}
```

**Weave Pattern Guidelines**:
```dart
void paintWeavePattern(Canvas canvas, Size size) {
  // Subtle diagonal lines at 45° angles
  // Use two slightly different shades
  // Line thickness: 2-4 pixels
  // Spacing: 8-12 pixels between lines
  // Creates "woven fabric" look
}

void paintWovenName(Canvas canvas, String name, Size size) {
  // Use bold, rounded font (good legibility)
  // Font size: ~180pt for 1024px texture
  // Center on canvas
  // Draw with "fiber bundle" effect:
  //   - Multiple offset copies in accent colors
  //   - Creates appearance of colored threads
  // Uppercase for clarity: name.toUpperCase()
}

void applyFabricTexture(Canvas canvas, Size size) {
  // Add subtle noise/grain
  // Very light (opacity: 0.2-0.3)
  // Creates "handmade" feel without obscuring name
}
```

**Caching Strategy**:
```dart
class RugTextureCache {
  static String? _currentName;
  static String? _cachedPath;
  
  static Future<String> getOrGenerate(String name) async {
    // Check if already generated for this name
    if (_currentName == name && _cachedPath != null) {
      if (await File(_cachedPath!).exists()) {
        return _cachedPath!;
      }
    }
    
    // Generate new texture
    _cachedPath = await RugTextureGenerator.generate(childName: name);
    _currentName = name;
    return _cachedPath!;
  }
}
```

**Integration with Thermion**:
```dart
// In character_view.dart, add method:
Future<void> _createPersonalizedRug(ThermionViewer viewer) async {
  // 1. Get child's name from settings (default: "Xen Words" or "Addy")
  final childName = await UserPreferences.getChildName() ?? "Xen Words";
  
  // 2. Generate or retrieve cached texture
  final texturePath = await RugTextureCache.getOrGenerate(childName);
  
  // 3. Load rug geometry
  final rug = await viewer.loadGltf(
    'assets/models/library/Rug.glb',
    addToScene: true,
  );
  
  // 4. Apply personalized texture
  await viewer.setTexture(
    rug,
    textureType: TextureType.baseColor,
    texturePath: texturePath,
  );
  
  // 5. Position on floor
  await viewer.setPosition(rug, Vector3(0, 0.5, -0.01));
}
```

**Default Names**: Use "Xen Words" or "Addy" as default/placeholder

---

### Asset 3: Stylized Books

**Purpose**: Add color, personality, and reinforce learning theme

**Geometry Requirements**:
- **Type**: Blender MCP (interactive creation) + documentation
- **Count**: 5-7 books
- **Poly Budget**: ~100-150 polygons total
- **Style**: Simple, stylized (children's book illustration aesthetic)

**Book Specifications**:
- **Geometry**: Simple boxes with slight variations
  - Heights: 0.15m to 0.20m (varied)
  - Widths: 0.06m to 0.09m (varied)
  - Depth: 0.03m to 0.04m (consistent spine)
  
- **Arrangement**: Stacked and/or leaning pile
  - Position: Near one of the potted plants
  - Should look natural, not rigid

- **Materials**: Bright, solid colors
  - Red, green, blue, yellow, purple
  - Slight roughness variation (0.5-0.8)
  - Optional: Simple "page" texture on fore-edge

**Implementation Approach**:

1. **Use Blender MCP** to create interactively:
   ```python
   # Example MCP commands to document:
   
   # Create book 1 (red)
   bpy.ops.mesh.primitive_cube_add()
   book1 = bpy.context.active_object
   book1.scale = (0.07, 0.03, 0.18)
   # ... position, material, etc.
   
   # Create book 2 (green)
   # ... etc.
   ```

2. **Document ALL commands** in a file: `asset-generation/docs/BOOKS_CREATION_LOG.md`

3. **Save as**: `assets/models/library/Books.blend`

**Why Blender MCP instead of generator**:
- Books need artistic arrangement
- Color/style choices are subjective
- Interactive is faster for this type of asset
- Can always create generator later if needed

**Documentation Requirements**:
- Save all MCP commands used
- Include screenshots of process
- Note material colors and positions
- Enables reproducibility

---

## 🔧 Implementation Workflow

### Step 1: Create Generators

Follow this order (simplest → most complex):

1. **Backdrop** (~1 hour)
   - Copy `generate_pot.py` as template
   - Modify to create curved plane
   - Test generation
   - Run analyzer

2. **Rug Geometry** (~1 hour)
   - Copy `generate_pot.py` as template
   - Create circle with proper UV mapping
   - Test generation
   - Run analyzer

3. **Rug Texture Generator** (~2 hours)
   - Create Dart utility class
   - Implement three-layer painting
   - Test with "Xen Words" and "Addy"
   - Verify texture quality

4. **Books** (~1-2 hours)
   - Use Blender MCP interactively
   - Document commands as you go
   - Create 5-7 varied books
   - Export to library/

### Step 2: Validate Assets

After creating each asset:

```bash
# Run asset analyzer
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python asset-generation/tools/asset_analyzer.py \
  -- assets/models/library/AssetName.blend
```

**Check for**:
- Poly count within budget
- Clean geometry (no non-manifold edges)
- Materials properly assigned
- Correct dimensions

### Step 3: Update Scene Composition

Edit `asset-generation/composers/compose_game_scene.py`:

```python
def compose_scene():
    # ... existing code ...
    
    # Add backdrop
    print("\nAdding backdrop...")
    backdrop = append_asset("Backdrop", "Backdrop")
    if backdrop:
        backdrop.location = (0, -3.5, 0.5)
    
    # Add rug
    print("\nAdding rug...")
    rug = append_asset("Rug", "Rug")
    if rug:
        rug.location = (0, 0.5, -0.01)
    
    # Add books
    print("\nAdding books...")
    books = append_asset("Books", "Books")
    if books:
        books.location = (-1.2, 2.8, -0.1)  # Near left plant
```

### Step 4: Integrate Rug Texture in Flutter

Add to `lib/widgets/character_view.dart`:

```dart
// In _setupScene method, after creating ground plane:
await _createPersonalizedRug(_viewer!);

// Add new method:
Future<void> _createPersonalizedRug(ThermionViewer viewer) async {
  // Implementation from Asset 2 spec above
}
```

### Step 5: Test in Game

```bash
# Regenerate scene
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python asset-generation/composers/compose_game_scene.py

# Run Flutter
flutter run
```

**Visual Check**:
- ✅ Backdrop visible behind character
- ✅ Rug on floor with child's name clearly visible
- ✅ Books add color and personality
- ✅ No clipping or Z-fighting
- ✅ Performance remains smooth

---

## 📊 Success Criteria

### Technical Requirements

- [ ] Backdrop generator creates clean geometry (~50-100 polys)
- [ ] Rug generator creates circle with proper UV mapping (~32-50 polys)
- [ ] Rug texture generator produces 1024×1024 PNG with clear, readable name
- [ ] Books asset is stylized and colorful (~100-150 polys)
- [ ] Total scene poly count: <4,200 (within 5,000 budget)
- [ ] All assets pass analyzer with no geometry issues
- [ ] Scene composes and exports successfully

### Visual/Polish Requirements

- [ ] Backdrop creates subtle "room" feel without being obtrusive
- [ ] Rug name is clearly legible and looks "woven" not "printed"
- [ ] Books look stylized/artistic, not janky or placeholder
- [ ] Assets positioned naturally (no floating, clipping)
- [ ] Color palette cohesive (warm, welcoming)
- [ ] Word card doesn't feel out of place in "room" setting

### Documentation Requirements

- [ ] Backdrop generator added to `generators/`
- [ ] Rug generator added to `generators/`
- [ ] Rug texture generator added to `lib/utils/`
- [ ] Books creation documented in `docs/BOOKS_CREATION_LOG.md`
- [ ] Parameters documented in `docs/ASSET_PARAMETERS.md`
- [ ] Scene composer updated with new assets
- [ ] Testing notes added to this file

---

## 🛠️ Tools & Commands Reference

### Generate Asset
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python asset-generation/generators/generate_backdrop.py
```

### Analyze Asset
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python asset-generation/tools/asset_analyzer.py \
  -- assets/models/library/Backdrop.blend
```

### Rebuild Scene
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python asset-generation/composers/compose_game_scene.py
```

### Test in Flutter
```bash
flutter run
```

---

## 💡 Tips & Best Practices

### For Generators

1. **Start from generate_pot.py** - It works! Copy and modify.
2. **Parameters at top** - Make everything adjustable
3. **Clear variable names** - Future you will thank you
4. **Test frequently** - Generate → Analyze → Iterate
5. **Keep it simple** - Don't over-engineer

### For Rug Texture

1. **Test text rendering early** - Make sure font looks good
2. **Use high-quality font** - Google Fonts work great
3. **Cache aggressively** - Only regenerate when name changes
4. **Consider performance** - 1024×1024 is sweet spot (quality/size)
5. **Fallback gracefully** - If generation fails, use solid color

### For Books

1. **Variety is key** - Different heights, widths, colors
2. **Slight imperfection** - Books shouldn't be perfectly aligned
3. **Color psychology** - Bright, cheerful colors for kids
4. **Document everything** - You might need to recreate later

### For Scene Composition

1. **Position thoughtfully** - Think about camera views
2. **Avoid clipping** - Check from all game state camera angles
3. **Depth ordering** - Z-fighting is the enemy
4. **Test in motion** - Watch during character animations

---

## 🎯 Expected Results

### Before
- Wood floor
- Two potted plants
- Character
- Word card floating in "void"

### After
- Wood floor ✓
- Personalized rug with child's name
- Two potted plants ✓
- **Subtle backdrop creating "room" feel**
- **Colorful books reinforcing learning theme**
- Character ✓
- Word card (now feels natural in "learning corner" setting)

**Overall vibe**: Cozy, personal, learning-focused environment

---

## 📝 Deliverables Checklist

### Code/Assets
- [ ] `generators/generate_backdrop.py`
- [ ] `generators/generate_rug.py`
- [ ] `lib/utils/rug_texture_generator.dart`
- [ ] `assets/models/library/Backdrop.blend`
- [ ] `assets/models/library/Rug.blend`
- [ ] `assets/models/library/Books.blend`
- [ ] Updated `composers/compose_game_scene.py`
- [ ] Updated `lib/widgets/character_view.dart`

### Documentation
- [ ] `docs/BOOKS_CREATION_LOG.md` (new)
- [ ] Updated `docs/ASSET_PARAMETERS.md` (add new assets)
- [ ] Testing notes in this file

### Validation
- [ ] All assets analyzed (no issues)
- [ ] Scene compiles and exports
- [ ] Flutter app runs without errors
- [ ] Visual quality acceptable
- [ ] Performance remains smooth

---

## 🚀 Ready to Start?

1. Read STATUS.md and PROCEDURAL_WORKFLOW.md
2. Study generate_pot.py as reference
3. Start with backdrop (simplest)
4. Work through each asset systematically
5. Test frequently
6. Document as you go

**Good luck! You've got this.** 🎨

---

## 📞 Questions/Issues?

If you encounter problems:

1. Check STATUS.md for current working state
2. Review generate_pot.py for working patterns
3. Use asset_analyzer.py to diagnose geometry issues
4. Refer to PROCEDURAL_WORKFLOW.md for process guidance

**Remember**: The pot generator works perfectly. When in doubt, follow its patterns.

