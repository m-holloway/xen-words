import 'package:thermion_flutter/thermion_flutter.dart';
import 'package:vector_math/vector_math_64.dart';
import '../services/director_tuner.dart';
import '../models/tunable_parameter.dart';

/// Central configuration for all rendering quality settings
/// 
/// Controls post-processing effects, anti-aliasing, shadows, bloom, etc.
/// All settings are tunable via DirectorTuner for live adjustment.
/// 
/// Usage:
/// ```dart
/// // Register parameters once at app startup
/// RenderQualityDirector.registerParameters();
/// 
/// // Apply settings to viewer
/// await RenderQualityDirector.applyToViewer(viewer);
/// ```
class RenderQualityDirector {
  
  // ========================================================================
  // 🎚️ POST-PROCESSING (Master Switch)
  // ========================================================================
  
  /// GLOBAL POST-PROCESSING ENABLE
  /// Master switch for ALL post-processing effects
  /// When false, disables bloom, tone mapping, AA, etc. for maximum performance
  /// Only disable if you need absolute maximum FPS
  static bool get postProcessingEnabled => DirectorTuner.instance.getValue('render', 'postProcessingEnabled', true);
  
  // ========================================================================
  // 🌑 SHADOW QUALITY
  // ========================================================================
  
  /// SOFT SHADOW PENUMBRA SCALE
  /// Controls the size/softness of shadow edges
  /// Higher = softer, more blurred shadow edges
  /// Lower = sharper, crisper shadow edges
  /// 
  /// Range: 0.0 - 100.0 (Filament accepts any positive value)
  /// Recommended: 0.5 - 2.0 for realistic shadows
  /// Extreme: 10.0+ for very soft, stylized shadows
  static double get shadowPenumbraScale => DirectorTuner.instance.getValue('render', 'shadowPenumbraScale', 9.31);
  
  /// SOFT SHADOW PENUMBRA RATIO SCALE
  /// Controls how the softness changes with distance
  /// Higher = shadows get softer at distance
  /// Lower = shadows stay uniformly soft/hard
  /// 
  /// Range: 0.0 - 100.0 (Filament accepts any positive value)
  /// Recommended: 0.5 - 2.0 for realistic depth
  /// Extreme: 10.0+ for exaggerated distance softening
  static double get shadowPenumbraRatioScale => DirectorTuner.instance.getValue('render', 'shadowPenumbraRatioScale', 1.0);
  
  // ========================================================================
  // ✨ ANTI-ALIASING (Smooths jagged edges)
  // ========================================================================
  
  /// MSAA - Multi-Sample Anti-Aliasing
  /// Hardware-based, high quality, expensive
  /// Best for static scenes, can impact mobile performance
  static bool get msaaEnabled => DirectorTuner.instance.getValue('render', 'msaaEnabled', true);
  
  /// FXAA - Fast Approximate Anti-Aliasing
  /// Post-process, fast, slight blur
  /// Good for mobile, minimal performance cost
  /// RECOMMENDED for most games
  static bool get fxaaEnabled => DirectorTuner.instance.getValue('render', 'fxaaEnabled', true);
  
  /// TAA - Temporal Anti-Aliasing
  /// Uses previous frames, best quality, slight ghosting
  /// Best for high-end devices with stable 60fps
  static bool get taaEnabled => DirectorTuner.instance.getValue('render', 'taaEnabled', false);
  
  // ========================================================================
  // 🌟 BLOOM (Glow effect)
  // ========================================================================
  
  /// BLOOM ENABLED
  /// Adds glow to bright areas (like sun, fire, magical effects)
  /// Can enhance atmosphere but costs performance
  /// 
  /// NOTE: Bloom requires:
  /// 1. Post-processing enabled
  /// 2. Bright lights in scene (intensity > 100,000 lux)
  /// 3. Strength > 0.0 (higher = more visible, try 0.3-1.0 for testing)
  static bool get bloomEnabled => DirectorTuner.instance.getValue('render', 'bloomEnabled', false);
  
  /// BLOOM STRENGTH
  /// How intense the glow effect is
  /// Lower = subtle glow, Higher = intense glow
  /// 
  /// Range: 0.0 - 10.0 (Filament doesn't enforce a hard max)
  /// Recommended: 0.3-0.5 for subtle effect, 1.0-3.0 for obvious bloom
  /// Extreme: 5.0-10.0 for very intense glow effects
  static double get bloomStrength => DirectorTuner.instance.getValue('render', 'bloomStrength', 10.0);
  
  // ========================================================================
  // 🎨 TONE MAPPING (Color/brightness adjustment)
  // ========================================================================
  
  /// TONE MAPPER TYPE
  /// Controls how HDR colors are mapped to display
  /// 
  /// Options:
  /// - LINEAR (0): No tone mapping, raw values (can look washed out)
  /// - ACES (1): Film-like, cinematic look (RECOMMENDED)
  /// - FILMIC (2): Game-like, vibrant colors
  /// 
  /// ACES is generally the best default for most scenes
  static int get toneMapperType => DirectorTuner.instance.getValue('render', 'toneMapperType', 1).toInt();
  
  /// Map integer to ToneMapper enum
  static ToneMapper getToneMapperEnum() {
    switch (toneMapperType) {
      case 0:
        return ToneMapper.LINEAR;
      case 1:
        return ToneMapper.ACES;
      case 2:
        return ToneMapper.FILMIC;
      default:
        return ToneMapper.ACES; // Default to ACES
    }
  }
  
  // ========================================================================
  // 🔲 DITHERING (Reduces color banding)
  // ========================================================================
  
  /// DITHERING ENABLED
  /// Adds subtle noise to prevent visible color bands in gradients
  /// Minimal performance cost, recommended to keep enabled
  /// You'll see banding in skies/gradients if this is off
  static bool get ditheringEnabled => DirectorTuner.instance.getValue('render', 'ditheringEnabled', true);
  
  // ========================================================================
  // 🌫️ FOG (Atmospheric depth)
  // ========================================================================
  
  /// FOG ENABLED
  /// Adds distance fog for atmospheric depth
  /// Creates a sense of depth and atmosphere in your scene
  /// 
  /// ✅ Available via ThermionViewer.view.setFogOptions()
  static bool get fogEnabled => DirectorTuner.instance.getValue('render', 'fogEnabled', true);
  
  /// FOG DISTANCE
  /// How far before fog starts appearing (in world units)
  /// Lower = fog starts closer, Higher = fog starts farther
  /// 
  /// Range: 0.0 - 100.0
  /// Recommended: 5.0 - 20.0 for close fog, 30.0 - 80.0 for distant atmosphere
  static double get fogDistance => DirectorTuner.instance.getValue('render', 'fogDistance', 4.0);
  
  /// FOG CUTOFF DISTANCE
  /// Distance where fog completely stops (beyond this, no fog at all)
  /// Use this to limit fog to a specific area
  /// 
  /// Range: 0.0 - 1000.0 (infinity = no cutoff)
  /// Set very high (e.g., 1000) to effectively disable cutoff
  static double get fogCutoffDistance => DirectorTuner.instance.getValue('render', 'fogCutoffDistance', 1000.0);
  
  /// FOG MAXIMUM OPACITY
  /// Maximum opacity/thickness the fog can reach (0.0 - 1.0)
  /// Controls how opaque the fog gets at its thickest point
  /// 
  /// Range: 0.0 - 1.0
  /// Recommended: 0.3 - 0.7 for visible but not overwhelming fog
  static double get fogMaximumOpacity => DirectorTuner.instance.getValue('render', 'fogMaximumOpacity', 1.0);
  
  /// FOG DENSITY (Exponential falloff)
  /// Controls how quickly fog density increases with distance
  /// Higher values = fog thickens more rapidly
  /// 
  /// Range: 0.0 - 1.0
  /// Recommended: 0.0 for linear fog, 0.1 - 0.5 for exponential
  static double get fogDensity => DirectorTuner.instance.getValue('render', 'fogDensity', 0.19);
  
  /// FOG HEIGHT
  /// Altitude where fog is thickest (Y-axis world units)
  /// 0.0 = ground level, negative = below ground, positive = above ground
  /// 
  /// Range: -10.0 - 10.0
  /// Recommended: 0.0 for ground fog, adjust based on scene scale
  static double get fogHeight => DirectorTuner.instance.getValue('render', 'fogHeight', 0.0);
  
  /// FOG HEIGHT FALLOFF
  /// How quickly fog dissipates above/below the fog height
  /// Higher values = fog confined to narrow altitude band
  /// Lower values = fog spreads vertically
  /// 
  /// Range: 0.0 - 10.0
  /// Recommended: 1.0 for even distribution, 3.0 - 5.0 for ground-hugging fog
  static double get fogHeightFalloff => DirectorTuner.instance.getValue('render', 'fogHeightFalloff', 1.0);
  
  /// FOG IN-SCATTERING START
  /// Distance where atmospheric scattering begins
  /// Creates more realistic atmospheric haze effects
  /// 
  /// Range: 0.0 - 100.0
  /// Recommended: Start slightly before fog distance
  static double get fogInScatteringStart => DirectorTuner.instance.getValue('render', 'fogInScatteringStart', 0.0);
  
  /// FOG IN-SCATTERING SIZE
  /// Size/intensity of the atmospheric scattering effect
  /// Higher values = more pronounced scattering halo
  /// 
  /// Range: 0.0 - 10.0
  /// Recommended: 0.0 to disable, 1.0 - 3.0 for subtle effect
  static double get fogInScatteringSize => DirectorTuner.instance.getValue('render', 'fogInScatteringSize', 1.8);
  
  /// FOG COLOR FROM IBL
  /// If true, fog color is derived from the image-based lighting (skybox)
  /// If false, uses the manual fog color (fogColorR/G/B)
  /// 
  /// Enable this if you have a skybox and want automatic color matching
  static bool get fogColorFromIbl => DirectorTuner.instance.getValue('render', 'fogColorFromIbl', true);
  
  /// FOG COLOR (Red component)
  /// RGB color of the fog, 0.0 - 1.0
  /// 
  /// TIP: Match this to your sky/horizon color for seamless blending
  /// Current sky horizon: #A8D5FF = RGB(0.66, 0.84, 1.0)
  static double get fogColorR => DirectorTuner.instance.getValue('render', 'fogColorR', 0.56);
  
  /// FOG COLOR (Green component)
  static double get fogColorG => DirectorTuner.instance.getValue('render', 'fogColorG', 0.59);
  
  /// FOG COLOR (Blue component)
  static double get fogColorB => DirectorTuner.instance.getValue('render', 'fogColorB', 0.97);
  
  // ========================================================================
  // 🎥 VIEW FRUSTUM CULLING (Performance optimization)
  // ========================================================================
  
  /// VIEW FRUSTUM CULLING ENABLED
  /// When enabled, objects outside the camera view are not rendered
  /// Improves performance for large scenes
  /// Only disable for debugging; should normally be enabled
  static bool get frustumCullingEnabled => DirectorTuner.instance.getValue('render', 'frustumCullingEnabled', true);
  
  // ========================================================================
  // 🌅 SKYBOX & IBL (Environmental Background & Lighting)
  // ========================================================================
  
  /// SKYBOX ENABLED
  /// Shows a skybox as the background instead of gradient/solid color
  /// Requires KTX format skybox asset
  /// See docs/SKYBOX_SETUP.md for details
  static bool get skyboxEnabled => DirectorTuner.instance.getValue('render', 'skyboxEnabled', true);
  
  /// SKYBOX PATH
  /// Path to the skybox KTX file
  /// Example: "assets/skybox/your_sky_skybox.ktx"
  /// Note: Must restart app after changing path
  static String get skyboxPath => DirectorTuner.instance.getValue('render', 'skyboxPath', 'assets/skybox/skybox_skybox.ktx');
  
  /// IBL ENABLED
  /// Enables Image-Based Lighting from environment map
  /// Provides realistic ambient lighting that matches the skybox
  /// Highly recommended when skybox is enabled
  static bool get iblEnabled => DirectorTuner.instance.getValue('render', 'iblEnabled', true);
  
  /// IBL PATH
  /// Path to the IBL KTX file
  /// Example: "assets/skybox/your_sky_ibl.ktx"
  /// Note: Must restart app after changing path
  static String get iblPath => DirectorTuner.instance.getValue('render', 'iblPath', 'assets/skybox/skybox_ibl.ktx');
  
  /// IBL INTENSITY
  /// Brightness for image-based lighting (in lux)
  /// Controls how much the environment contributes to scene lighting
  /// 
  /// Range: 0 - 100,000 lux
  /// - 10,000-30,000: Indoor/studio lighting
  /// - 30,000-50,000: Overcast day
  /// - 50,000-80,000: Bright daylight
  /// - 100,000+: Direct sunlight
  /// Default: 28,000 lux (tuned)
  static double get iblIntensity => DirectorTuner.instance.getValue('render', 'iblIntensity', 28000.0);
  
  /// SKYBOX ROTATION
  /// Rotates the skybox around the Y-axis (in degrees)
  /// Useful for aligning skybox with your scene orientation
  /// 
  /// Range: 0.0 - 360.0
  static double get skyboxRotation => DirectorTuner.instance.getValue('render', 'skyboxRotation', 0.0);
  
  // ========================================================================
  // 📷 CAMERA EXPOSURE (Controls scene brightness)
  // ========================================================================
  
  /// CAMERA APERTURE (f-stop)
  /// Controls lens opening - LOWER values = BRIGHTER scene
  /// 
  /// Range: 0.5 - 64.0 (realistic: 0.95 - 32)
  /// - 1.4-2.8: Very bright (good for skyboxes/indoor)
  /// - 4.0-8.0: Moderate
  /// - 11-22: Outdoor daylight
  /// Default: 5.975 (tuned)
  static double get cameraAperture => DirectorTuner.instance.getValue('render', 'cameraAperture', 5.975);
  
  /// CAMERA SHUTTER SPEED (seconds)
  /// Time the shutter stays open - LOWER values = DARKER scene
  /// 
  /// Range: 1/1000 (0.001) - 1.0 second
  /// - 1/1000 (0.001): Fast, dark (tuned)
  /// - 1/500 (0.002): Action
  /// - 1/125 (0.008): Standard
  /// - 1/60 (0.017): Handheld minimum
  /// - 1/30 (0.033): Low light
  /// - 1 (1.0): Very long exposure, very bright
  /// Default: 0.001 (tuned)
  static double get cameraShutterSpeed => DirectorTuner.instance.getValue('render', 'cameraShutterSpeed', 0.001);
  
  /// CAMERA ISO SENSITIVITY
  /// Light sensitivity - HIGHER values = BRIGHTER scene
  /// 
  /// Range: 50 - 6400 (realistic photography range)
  /// - 50-100: Bright daylight
  /// - 400-800: Indoor/overcast
  /// - 1600-3200: Low light
  /// - 6400: Very dark
  /// Default: 50 (tuned)
  static double get cameraISO => DirectorTuner.instance.getValue('render', 'cameraISO', 50.0);
  
  // ========================================================================
  // 🎛️ PARAMETER REGISTRATION (Called during app initialization)
  // ========================================================================
  
  /// Register all tunable parameters with DirectorTuner
  static void registerParameters() {
    // Master switches
    DirectorTuner.register('render', 'postProcessingEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    
    // Shadow quality
    DirectorTuner.register('render', 'shadowPenumbraScale', min: 0.0, max: 100.0, defaultValue: 9.31, unit: 'scale');
    DirectorTuner.register('render', 'shadowPenumbraRatioScale', min: 0.0, max: 100.0, defaultValue: 1.0, unit: 'scale');
    
    // Anti-aliasing
    DirectorTuner.register('render', 'msaaEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'fxaaEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'taaEnabled', min: 0.0, max: 1.0, defaultValue: false, type: ParameterType.bool);
    
    // Bloom
    DirectorTuner.register('render', 'bloomEnabled', min: 0.0, max: 1.0, defaultValue: false, type: ParameterType.bool);
    DirectorTuner.register('render', 'bloomStrength', min: 0.0, max: 10.0, defaultValue: 10.0, unit: 'intensity');
    
    // Tone mapping
    DirectorTuner.register('render', 'toneMapperType', min: 0.0, max: 2.0, defaultValue: 1.0, type: ParameterType.int, unit: '0=LINEAR,1=ACES,2=FILMIC');
    
    // Dithering
    DirectorTuner.register('render', 'ditheringEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    
    // Fog (colors match current sky horizon: #A8D5FF)
    DirectorTuner.register('render', 'fogEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'fogDistance', min: 0.0, max: 100.0, defaultValue: 4.0, unit: 'units');
    DirectorTuner.register('render', 'fogCutoffDistance', min: 0.0, max: 1000.0, defaultValue: 1000.0, unit: 'units');
    DirectorTuner.register('render', 'fogMaximumOpacity', min: 0.0, max: 1.0, defaultValue: 1.0, unit: 'opacity');
    DirectorTuner.register('render', 'fogDensity', min: 0.0, max: 1.0, defaultValue: 0.19, unit: 'exponential');
    DirectorTuner.register('render', 'fogHeight', min: -10.0, max: 10.0, defaultValue: 0.0, unit: 'Y');
    DirectorTuner.register('render', 'fogHeightFalloff', min: 0.0, max: 10.0, defaultValue: 1.0, unit: 'falloff');
    DirectorTuner.register('render', 'fogInScatteringStart', min: 0.0, max: 100.0, defaultValue: 0.0, unit: 'units');
    DirectorTuner.register('render', 'fogInScatteringSize', min: 0.0, max: 10.0, defaultValue: 1.8, unit: 'size');
    DirectorTuner.register('render', 'fogColorFromIbl', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'fogColorR', min: 0.0, max: 1.0, defaultValue: 0.56, unit: 'R');
    DirectorTuner.register('render', 'fogColorG', min: 0.0, max: 1.0, defaultValue: 0.59, unit: 'G');
    DirectorTuner.register('render', 'fogColorB', min: 0.0, max: 1.0, defaultValue: 0.97, unit: 'B');
    
    // View frustum culling
    DirectorTuner.register('render', 'frustumCullingEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    
    // Skybox & IBL (Note: paths require app restart to take effect)
    DirectorTuner.register('render', 'skyboxEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'iblEnabled', min: 0.0, max: 1.0, defaultValue: true, type: ParameterType.bool);
    DirectorTuner.register('render', 'iblIntensity', min: 0.0, max: 100000.0, defaultValue: 28000.0, unit: 'lux');
    DirectorTuner.register('render', 'skyboxRotation', min: 0.0, max: 360.0, defaultValue: 0.0, unit: 'degrees');
    
    // Camera Exposure
    DirectorTuner.register('render', 'cameraAperture', min: 0.5, max: 64.0, defaultValue: 5.975, unit: 'f-stop');
    DirectorTuner.register('render', 'cameraShutterSpeed', min: 0.001, max: 1.0, defaultValue: 0.001, unit: 'seconds');
    DirectorTuner.register('render', 'cameraISO', min: 50.0, max: 6400.0, defaultValue: 50.0, unit: 'ISO');
    
    // Note: skyboxPath and iblPath are string parameters - not registered as they require special handling
  }
  
  // ========================================================================
  // 🚀 APPLICATION METHODS
  // ========================================================================
  
  /// Apply all render quality settings to a ThermionViewer
  /// Call this once at scene startup, or whenever settings change
  static Future<void> applyToViewer(ThermionViewer viewer) async {
    print('');
    print('═══════════════════════════════════════');
    print('🎨 RENDER QUALITY SETUP');
    print('═══════════════════════════════════════');
    
    // Master post-processing switch
    await viewer.setPostProcessing(postProcessingEnabled);
    print('📊 Post-Processing: $postProcessingEnabled');
    
    // Soft shadow options
    await viewer.setSoftShadowOptions(shadowPenumbraScale, shadowPenumbraRatioScale);
    print('🌑 Soft Shadows: penumbra=$shadowPenumbraScale, ratio=$shadowPenumbraRatioScale');
    
    // Anti-aliasing
    await viewer.setAntiAliasing(msaaEnabled, fxaaEnabled, taaEnabled);
    print('✨ Anti-Aliasing: MSAA=$msaaEnabled, FXAA=$fxaaEnabled, TAA=$taaEnabled');
    
    // Bloom (requires post-processing + bright lights)
    await viewer.setBloom(bloomEnabled, bloomStrength);
    print('🌟 Bloom: enabled=$bloomEnabled, strength=$bloomStrength');
    if (bloomEnabled && bloomStrength < 0.3) {
      print('   ⚠️  Note: Bloom strength <0.3 may be too subtle to see');
    }
    if (bloomEnabled && !postProcessingEnabled) {
      print('   ⚠️  Warning: Bloom requires post-processing to be enabled!');
    }
    
    // Tone mapping
    final toneMapper = getToneMapperEnum();
    await viewer.setToneMapping(toneMapper);
    print('🎨 Tone Mapping: $toneMapper');
    
    // Dithering (NOT exposed on ThermionViewer - would need View access)
    // await viewer.setDithering(ditheringEnabled);
    print('🔲 Dithering: $ditheringEnabled');
    print('   ⚠️  Not configurable - requires View object access');
    
    // Fog (accessed via viewer.view)
    if (fogEnabled) {
      final fogOptions = FogOptions(
        enabled: true,
        distance: fogDistance,
        cutOffDistance: fogCutoffDistance,
        maximumOpacity: fogMaximumOpacity,
        density: fogDensity,
        height: fogHeight,
        heightFalloff: fogHeightFalloff,
        inScatteringStart: fogInScatteringStart,
        inScatteringSize: fogInScatteringSize,
        fogColorFromIbl: fogColorFromIbl,
        linearColor: Vector3(fogColorR, fogColorG, fogColorB),
      );
      await viewer.view.setFogOptions(fogOptions);
      print('🌫️  Fog: ENABLED');
      print('   Distance: $fogDistance → ${fogCutoffDistance == 1000.0 ? "∞" : fogCutoffDistance}');
      print('   Opacity: $fogMaximumOpacity, Density: $fogDensity');
      print('   Height: $fogHeight, Falloff: $fogHeightFalloff');
      print('   Scattering: start=$fogInScatteringStart, size=$fogInScatteringSize');
      print('   Color: ${fogColorFromIbl ? "FROM IBL" : "RGB($fogColorR, $fogColorG, $fogColorB)"}');
    } else {
      await viewer.view.setFogOptions(FogOptions(enabled: false));
      print('🌫️  Fog: DISABLED');
    }
    
    // View frustum culling
    await viewer.setViewFrustumCulling(frustumCullingEnabled);
    print('🎥 Frustum Culling: $frustumCullingEnabled');
    
    print('═══════════════════════════════════════');
    print('');
  }
}

