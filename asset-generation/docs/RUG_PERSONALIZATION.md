# Rug Personalization System

## Overview

The personalized rug displays the child's name woven into a fabric texture. Currently, this uses a pre-generated GLB approach due to Thermion's asset path limitations.

## Current Implementation (v1.0)

### Workflow

1. **Texture Generation** (`lib/utils/rug_texture_generator.dart`)
   - Creates a 1024×1024 PNG with personalized name
   - Three-layer composition: base weave, name text, fabric overlay
   - Saved to cache directory

2. **Blender Script** (`asset-generation/generators/apply_rug_texture.py`)
   - Loads rug geometry from `Rug.blend`
   - Applies the PNG texture to the rug material
   - Exports as GLB with texture baked in

3. **Asset Loading** (`lib/widgets/character_view.dart`)
   - Loads pre-generated `PersonalizedRug.glb` from assets
   - Positions rug in front of character on floor

### Generating a Personalized Rug

```bash
# 1. Generate texture (manual Python example)
python3 << 'EOF'
from PIL import Image, ImageDraw, ImageFont

size = 1024
img = Image.new('RGB', (size, size), color=(139, 69, 19))
draw = ImageDraw.Draw(img)

# Draw pattern
for i in range(0, size*2, 20):
    draw.line([(i, 0), (0, i)], fill=(160, 82, 45), width=2)

# Draw name
font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 120)
text = "YOUR NAME"
bbox = draw.textbbox((0, 0), text, font=font)
x = (size - bbox[2] + bbox[0]) // 2
y = (size - bbox[3] + bbox[1]) // 2
draw.text((x, y), text, fill=(255, 228, 181), font=font)

img.save('/tmp/rug_texture.png')
EOF

# 2. Apply texture with Blender
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
  asset-generation/generators/apply_rug_texture.py -- \
  --texture-path /tmp/rug_texture.png \
  --output-path assets/models/library/PersonalizedRug.glb
```

### Positioning

The rug is positioned using Thermion's coordinate system:
- **Position**: `(0, -0.01, -0.5)`
  - `X=0`: Centered horizontally
  - `Y=-0.01`: Slightly below floor level
  - `Z=-0.5`: In front of character (Blender's +Y becomes Thermion's -Z)

## Limitations & Future Improvements

### Current Limitations

1. **Static Asset**: Rug is pre-generated, not personalized per user
2. **Single Name**: Only one name ("XEN WORDS") is baked in
3. **Manual Process**: Requires manual script execution to change

### Future v2.0 Approach

**Option A: Build-Time Generation**
- Generate multiple rug variants during build
- Select appropriate rug based on user preferences
- Pros: Fast loading, no runtime overhead
- Cons: Limited to pre-defined names

**Option B: Server-Side Generation**
- Generate personalized GLBs on server
- Download and cache on device
- Pros: Truly dynamic, unlimited names
- Cons: Requires internet, server infrastructure

**Option C: Runtime Material Modification** (requires Thermion API support)
- Load blank rug GLB
- Apply texture at runtime using Thermion API
- Pros: Most flexible
- Cons: Requires Thermion API that may not exist

## Files

- **Texture Generator**: `lib/utils/rug_texture_generator.dart`
- **Blender Script**: `asset-generation/generators/apply_rug_texture.py`
- **Rug Geometry**: `assets/models/library/Rug.blend`
- **Personalized GLB**: `assets/models/library/PersonalizedRug.glb`
- **Loading Code**: `lib/widgets/character_view.dart` (`_createPersonalizedRug`)

## Testing

To verify the rug appears correctly:
1. Hot reload the app
2. Check console for: `✅ Personalized rug loaded and positioned`
3. Visually inspect the floor in front of the character
4. Should see a circular rug with "XEN WORDS" text

## Troubleshooting

**Rug not visible?**
- Check console logs for loading errors
- Verify `PersonalizedRug.glb` exists in `assets/models/library/`
- Check `pubspec.yaml` includes `assets/models/`
- Try regenerating GLB with Blender script

**Wrong texture/name?**
- Regenerate texture PNG with desired name
- Re-run Blender script to bake into GLB
- Hot reload app (may need full restart)

