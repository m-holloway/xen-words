# 🚀 Skybox Quick Start Guide

## ✅ What's Been Added

Skybox and IBL support has been fully integrated into the RenderQualityDirector with live-adjustable parameters!

### New Tunable Parameters:
1. **`render.skyboxEnabled`** (bool) - Toggle skybox on/off
2. **`render.iblEnabled`** (bool) - Toggle image-based lighting
3. **`render.iblIntensity`** (0-10) - Adjust IBL brightness
4. **`render.skyboxRotation`** (0-360) - Rotate skybox alignment
5. **`render.fogColorFromIbl`** (bool) - Auto-match fog to skybox colors

## 📦 Step-by-Step Setup

### 1. Get a Free Skybox from Poly Haven

```bash
# Visit polyhaven.com/hdris and download an HDR
# Recommended for your blue theme: "kloofendal_48d_partly_cloudy"
# Download as HDR format (4K or 8K)
```

### 2. Convert to KTX Format

```bash
# Install Filament tools from:
# https://github.com/google/filament/releases

# Convert (macOS/Linux):
cmgen -x ./output --format=ktx --size=512 kloofendal.hdr

# This creates:
# - output/kloofendal_skybox.ktx (visual background)
# - output/kloofendal_ibl.ktx (lighting data)
```

### 3. Add to Your Project

```bash
# Create directory
mkdir -p assets/skybox

# Copy files
cp output/kloofendal_skybox.ktx assets/skybox/
cp output/kloofendal_ibl.ktx assets/skybox/
```

### 4. Update `pubspec.yaml`

```yaml
flutter:
  assets:
    - assets/models/
    - assets/skybox/
    - assets/skybox/kloofendal_skybox.ktx
    - assets/skybox/kloofendal_ibl.ktx
```

### 5. Add Loading Code to `character_view.dart`

In `_onViewerAvailable` method, add after the existing setup:

```dart
// Load skybox if enabled
if (RenderQualityDirector.skyboxEnabled) {
  try {
    await viewer.loadSkybox(RenderQualityDirector.skyboxPath);
    print('✅ Skybox loaded: ${RenderQualityDirector.skyboxPath}');
    
    // Rotate skybox if needed
    if (RenderQualityDirector.skyboxRotation != 0.0) {
      await viewer.setIndirectLightRotation(
        Matrix3.rotationY(RenderQualityDirector.skyboxRotation * (3.14159 / 180.0))
      );
    }
  } catch (e) {
    print('⚠️ Failed to load skybox: $e');
  }
}

// Load IBL if enabled
if (RenderQualityDirector.iblEnabled) {
  try {
    await viewer.loadIbl(RenderQualityDirector.iblPath, intensity: RenderQualityDirector.iblIntensity);
    print('✅ IBL loaded: ${RenderQualityDirector.iblPath}');
  } catch (e) {
    print('⚠️ Failed to load IBL: $e');
  }
}
```

### 6. Update Defaults (Optional)

In `lib/widgets/render_quality_director.dart`, update the default paths:

```dart
static String get skyboxPath => DirectorTuner.instance.getValue(
  'render', 
  'skyboxPath', 
  'assets/skybox/kloofendal_skybox.ktx'  // Your actual filename
);

static String get iblPath => DirectorTuner.instance.getValue(
  'render', 
  'iblPath', 
  'assets/skybox/kloofendal_ibl.ktx'  // Your actual filename
);
```

## 🎮 Using the Director Overlay

After full app restart:

1. Press **`d`** to open director overlay
2. Navigate to:
   - `render.skyboxEnabled` → **true**
   - `render.iblEnabled` → **true**
   - `render.iblIntensity` → **1.0** (adjust to taste)
   - `render.fogColorFromIbl` → **true** (auto-match fog to skybox)
3. Tune as needed!

## 🎨 Integration with Your Current Setup

### Before (Gradient Background):
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color(0xFF4A90E2),  // Deep blue
        Color(0xFF6BB6FF),  // Mid blue
        Color(0xFFA8D5FF),  // Light blue
      ],
    ),
  ),
)
```

### After (Skybox):
- **Remove** the gradient decoration
- **Set** `background: Colors.transparent` in ViewerWidget
- **Enable** skybox via director
- Gradient is replaced by realistic sky!

## 💡 Recommended Skyboxes for Your Theme

### Blue Sky (Matches Current Gradient):
- **kloofendal_48d_partly_cloudy** - Perfect match!
- **qwantani_dusk** - Slightly warmer
- **blue_photo_studio** - Clean studio look

### Outdoor Feel:
- **kiara_dawn** - Soft morning light
- **venice_sunset** - Golden hour (changes mood)
- **studio_small** - Warm, cozy

## ⚙️ Advanced Configuration

### IBL Intensity Tuning:
- **0.5-0.8**: Subtle ambient light
- **1.0**: Realistic (recommended)
- **2.0-3.0**: Brighter, more vibrant
- **5.0+**: Very bright, stylized

### Skybox Rotation:
- Align sun direction with your scene
- Rotate to match light source positions
- 0° = default, 90° = quarter turn, etc.

### Fog Integration:
- **Manual**: Match `fogColorR/G/B` to horizon
- **Auto**: Enable `fogColorFromIbl: true`
- Adjust `fogDistance` to blend seamlessly

## 🐛 Troubleshooting

### Skybox Not Loading:
1. Check file paths in pubspec.yaml
2. Verify KTX format (not PNG/JPG)
3. Check terminal for error messages
4. Ensure full app restart (not hot reload)

### IBL Not Affecting Scene:
1. Verify `iblEnabled: true`
2. Increase `iblIntensity` (try 2.0-3.0)
3. Check if custom lights are overpowering
4. Reduce `LightingDirector.masterBrightness` if too bright

### Performance Issues:
1. Use 256x256 texture size (fast)
2. Disable bloom if enabled
3. Use smaller KTX files
4. Test on target device

### Fog Doesn't Match Skybox:
1. Enable `fogColorFromIbl: true`
2. Adjust `fogDistance` (10-30 range)
3. Increase `fogMaximumOpacity` (0.5-0.7)
4. Check skybox has visible horizon

## 📊 Performance Impact

| Texture Size | Mobile | Desktop | Quality |
|--------------|--------|---------|---------|
| 256x256      | ✅ Fast | ✅ Fast | Good    |
| 512x512      | ⚠️ OK   | ✅ Fast | Better  |
| 1024x1024    | ❌ Slow | ⚠️ OK   | Great   |
| 2048x2048    | ❌ Very Slow | ⚠️ OK | Best |

**Recommended**: 512x512 for most use cases

## 🎯 Next Steps

1. ✅ Get HDR from Poly Haven
2. ✅ Convert to KTX with cmgen
3. ✅ Add to assets/skybox/
4. ✅ Update pubspec.yaml
5. ✅ Add loading code to character_view.dart
6. ✅ Full app restart
7. ✅ Enable via director overlay (`d` key)
8. ✅ Tune fog and lighting to match

## 📚 Additional Resources

- Full guide: `docs/SKYBOX_SETUP.md`
- Poly Haven: https://polyhaven.com/hdris
- Filament Tools: https://github.com/google/filament/releases
- Thermion Docs: https://thermion.dev/viewer

---

**Questions?** The skybox system is now fully integrated and ready to use!

