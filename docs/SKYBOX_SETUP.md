# 🌅 Skybox Setup Guide for Xen Words

## Overview
This guide shows how to add a professional skybox to your Thermion 3D scene with proper fog integration and image-based lighting (IBL).

## 📋 Requirements

### Skybox Format
Thermion requires **KTX format** (Khronos Texture) for both skybox and IBL:
- **Skybox**: `your_sky_skybox.ktx` (visual background)
- **IBL**: `your_sky_ibl.ktx` (environment lighting)

## 🎨 Getting Skybox Assets

### Option 1: Poly Haven (Recommended - Free & High Quality)
1. Visit [polyhaven.com/hdris](https://polyhaven.com/hdris)
2. Choose a sky (e.g., "blue_photo_studio", "kloofendal", "venice_sunset")
3. Download as **HDR format** (16K recommended for quality)

### Option 2: HDRI Haven
1. Visit [hdrihaven.com](https://hdrihaven.com)
2. Similar process to Poly Haven

### Option 3: Pre-converted KTX
- Look for "filament skybox ktx" resources
- Some game asset stores offer pre-converted files

## 🔧 Converting HDR to KTX

### Install Filament Tools
```bash
# Download from GitHub releases
https://github.com/google/filament/releases

# Extract and add to PATH
# macOS/Linux: cmgen tool location
# Windows: cmgen.exe
```

### Convert HDR to KTX
```bash
# Navigate to your HDR file location
cd ~/Downloads

# Generate KTX skybox and IBL
cmgen -x ./output \
  --format=ktx \
  --size=256 \
  --extract-blur=0.1 \
  your_sky.hdr

# This creates in ./output/:
# - your_sky_ibl.ktx (lighting data)
# - your_sky_skybox.ktx (visual background)
```

### Parameters Explained
- `--size=256`: Resolution (256, 512, 1024, 2048)
  - 256: Fast, mobile-friendly
  - 512-1024: Desktop quality
  - 2048: High-end only
- `--extract-blur=0.1`: Blur for diffuse lighting (0.0-1.0)

## 📦 Add to Flutter Project

### 1. Copy Files
```bash
# Create skybox directory
mkdir -p assets/skybox

# Copy generated KTX files
cp output/your_sky_skybox.ktx assets/skybox/
cp output/your_sky_ibl.ktx assets/skybox/
```

### 2. Update pubspec.yaml
```yaml
flutter:
  assets:
    - assets/models/
    - assets/skybox/
    - assets/skybox/your_sky_skybox.ktx
    - assets/skybox/your_sky_ibl.ktx
```

## 🎬 Integration with Xen Words

### Your Current Setup
- **Background**: Flutter gradient (0xFF4A90E2 → 0xFFA8D5FF)
- **Fog**: Configured to match gradient horizon
- **Lighting**: Custom DirectLights

### With Skybox
- **Background**: Skybox replaces gradient
- **Fog**: Auto-matches skybox if `fogColorFromIbl: true`
- **Lighting**: IBL provides realistic ambient + custom DirectLights

## 🎨 Matching Fog to Skybox

### Manual Color Matching
1. Look at skybox horizon color
2. Convert to RGB (0-1 range)
3. Set fog colors in director overlay:
   - `render.fogColorR`
   - `render.fogColorG`
   - `render.fogColorB`

### Automatic Matching
1. Enable `render.fogColorFromIbl: true`
2. Fog automatically samples skybox colors

## 📐 Recommended Skybox Types for Your Scene

### Best for Indoor/Studio Feel:
- **blue_photo_studio** - Clean, professional
- **studio_small** - Warm, soft lighting
- **industrial_sunset** - Dramatic with warm tones

### Best for Outdoor Feel:
- **kloofendal** - Clear day, subtle clouds
- **venice_sunset** - Warm, golden hour
- **kiara_dawn** - Soft morning light

### Sky Color Matching:
Your current gradient: `#4A90E2 → #A8D5FF` (blue gradient)
Recommended skyboxes with similar tones:
- Clear day skies with blue
- Avoid sunset/orange tones unless you change fog

## 🔧 Director Integration

Skybox parameters have been added to `RenderQualityDirector`:
- `render.skyboxEnabled` (bool)
- `render.skyboxPath` (string)
- `render.iblEnabled` (bool)
- `render.iblPath` (string)
- `render.skyboxIntensity` (0-10)
- `render.iblIntensity` (0-10)

All are live-adjustable via the director overlay!

## 🧪 Testing Checklist

1. ✅ Skybox loads without errors
2. ✅ IBL provides natural lighting
3. ✅ Fog blends seamlessly with skybox
4. ✅ No visible seams at horizon
5. ✅ Performance acceptable (check FPS)
6. ✅ Colors match overall scene aesthetic

## 🎯 Quick Start Example

For a simple test with your blue theme:

1. **Download**: "kloofendal_48d_partly_cloudy" from Poly Haven
2. **Convert**: `cmgen -x . --format=ktx --size=512 kloofendal.hdr`
3. **Add**: Copy to `assets/skybox/`
4. **Enable**: 
   - `render.skyboxEnabled: true`
   - `render.skyboxPath: assets/skybox/kloofendal_skybox.ktx`
   - `render.iblEnabled: true`
   - `render.iblPath: assets/skybox/kloofendal_ibl.ktx`
   - `render.fogColorFromIbl: true`

## 📚 Resources

- [Poly Haven HDRIs](https://polyhaven.com/hdris) - Free high-quality HDRs
- [Filament Documentation](https://google.github.io/filament/) - Technical details
- [Filament Releases](https://github.com/google/filament/releases) - Download cmgen
- [KTX Format Info](https://www.khronos.org/ktx/) - About the format

## 💡 Pro Tips

1. **Start Simple**: Use 256x256 for testing, increase later
2. **Match Lighting**: Skybox should match your scene's time of day
3. **Fog Distance**: Adjust `render.fogDistance` to hide horizon seams
4. **IBL Intensity**: Start at 1.0, adjust based on scene brightness
5. **Performance**: Smaller textures = better mobile performance

