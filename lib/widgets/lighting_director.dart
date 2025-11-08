import 'package:thermion_flutter/thermion_flutter.dart';

/// 🎨 LIGHTING DIRECTOR'S CONTROL PANEL 🎨
/// 
/// All scene lighting parameters in one place for easy exploration and tuning.
/// All values use INTUITIVE, NATURAL descriptions - no mental math needed!
/// 
/// HOW TO USE:
/// 1. Adjust parameters below
/// 2. Hot reload to see changes instantly
/// 3. Exaggerate values to understand their effect
/// 4. Tune back to what feels right
/// 
/// COORDINATE SYSTEM REMINDER:
/// - X-axis: Left (-) to Right (+)
/// - Y-axis: Down (-) to Up (+)
/// - Z-axis: Far (-) to Near (+) [toward camera]
/// - Character at origin (0, 0, 0)
/// - Backdrop at Z ≈ -3.5 (behind)
/// - Camera at Z ≈ 3.0 (front)
class LightingDirector {
  // ========================================================================
  // ☀️ PRIMARY LIGHT (Main Scene Illumination - Key Light)
  // ========================================================================
  // This is your main KEY LIGHT - illuminates the character from the front
  // Think of this as the primary studio light that lights the character's face/body
  // 
  // IMPORTANT COORDINATE CLARIFICATION:
  // - Character at origin (0, 0, 0)
  // - Camera at Z ≈ +3.0 (positive Z, in front)
  // - Backdrop at Z ≈ -3.5 (negative Z, behind)
  // 
  // Light direction is where rays TRAVEL (the direction they point):
  // - NEGATIVE Z = rays travel from camera side toward backdrop (front lighting)
  // - POSITIVE Z = rays travel from backdrop toward camera (back lighting)
  // - NEGATIVE Y = rays travel downward (from above)
  /// 
  /// Presets you can try:
  /// - fromFrontAbove: Main key light (standard)
  /// - fromSide: Dramatic side lighting
  /// - fromAboveBehind: Rim/backlight effect
  static const LightDirection primaryDirection = LightDirection(
    x: 0.3,              // More from right for visible direction (was 0.2)
    y: -0.5,             // Less steep - more natural angle (was -0.7)
    z: -0.7,             // From FRONT (negative Z = from camera side)
    description: "Natural front-right key light, gentler angle",
  );
  
  /// COLOR TEMPERATURE: How warm or cool the light feels
  /// 
  /// Reference guide:
  /// - 2000-3000K: Warm candlelight, sunset, cozy
  /// - 3500-4500K: Warm white, morning sun
  /// - 5000-5500K: Neutral daylight (balanced)
  /// - 6000-7000K: Cool daylight, overcast
  /// - 8000+K: Very cool, blue hour
  /// 
  /// For zen/cozy aesthetic: Try 3500-4500K range
  static const double primaryColorTemp = 4400.0; // Warm, inviting daylight
  
  /// INTENSITY: How bright the light is
  /// 
  /// Reference guide:
  /// - 20,000-50,000: Subtle, moody
  /// - 50,000-100,000: Moderate, natural
  /// - 100,000-150,000: Bright, clear
  /// - 150,000+: Very bright, high contrast
  /// 
  /// Start moderate, increase until you see clear depth
  static const double primaryIntensity = 120000.0;
  
  /// SHADOWS: Enable/disable shadow casting
  /// 
  /// Shadows are CRITICAL for:
  /// - Grounding the character (not floating)
  /// - Creating depth and dimension
  /// - Making the space feel real
  /// 
  /// Performance note: Shadows have a cost, but modern devices handle it well
  /// NOTE: Starting with shadows OFF for Phase 1 - can enable once basic lighting looks good
  static const bool primaryCastsShadows = true;
  
  // ========================================================================
  // 💡 FILL LIGHT (Lifts Shadows, Adds Detail)
  // ========================================================================
  // Softens harsh shadows from primary light
  // Typically cooler and less intense than primary
  
  /// FILL DIRECTION: Opposite side from primary
  /// Classic 3-point lighting: Fill comes from front-opposite side
  static const LightDirection fillDirection = LightDirection(
    x: -0.2,             // From left (opposite of primary's right bias)
    y: -0.2,             // From above
    z: -0.75,            // From front (negative Z = from camera direction)
    description: "Soft front-left fill to soften shadows",
  );
  
  /// FILL COLOR TEMPERATURE
  /// Often cooler than primary for natural look
  /// Cool fill + warm key = dimensional, realistic lighting
  static const double fillColorTemp = 4600.0; // Slightly cooler than primary
  
  /// FILL INTENSITY
  /// Should be LESS than primary (typically 30-50% of primary)
  /// Too bright = flattens the scene (defeats the purpose!)
  /// Higher value = softer, lighter shadows
  /// Lower value = darker, more dramatic shadows
  static const double fillIntensity = 80000.0; // About 60% of primary for softer shadows
  
  /// FILL SHADOWS: Usually disabled to keep it soft
  static const bool fillCastsShadows = false;
  
  // ========================================================================
  // ✨ RIM/BACK LIGHT (Separation & Depth)
  // ========================================================================
  // Creates edge highlights on character
  // Separates character from background
  // Adds that professional "pop"
  
  /// RIM DIRECTION: From behind/above character
  /// This creates a bright edge/halo effect
  /// POSITIVE Z = rays travel from backdrop toward camera (backlight)
  static const LightDirection rimDirection = LightDirection(
    x: 0.0,              // Center for even rim
    y: -0.3,             // From above
    z: 0.95,             // Strongly from behind (positive Z = backlight)
    description: "Back light for edge highlights and separation",
  );
  
  /// RIM COLOR TEMPERATURE
  /// Can be warm (golden) or cool (blue) for creative effect
  /// Warmer than primary = glowing, magical
  /// Cooler than primary = crisp, clean separation
  static const double rimColorTemp = 3500.0; // Warm gold
  
  /// RIM INTENSITY
  /// Moderate intensity - enough to see the edge, not overpower
  static const double rimIntensity = 65000.0;
  
  /// RIM SHADOWS: Usually disabled (it's a subtle accent)
  static const bool rimCastsShadows = false;
  
  // ========================================================================
  // 🌅 AMBIENT / ENVIRONMENT (Base Scene Illumination)
  // ========================================================================
  // Prevents areas from going completely black
  // Simulates bounced light and sky light
  
  /// AMBIENT INTENSITY
  /// Very subtle - just enough to see detail in shadows
  /// Too high = flattens everything (bad!)
  /// Too low = shadows become pure black (also bad!)
  /// 
  /// Good range: 5,000-20,000 (much less than directional lights)
  /// Increased to lift shadows and create softer, more inviting feel
  static const double ambientIntensity = 20000.0;
  
  /// AMBIENT COLOR TEMPERATURE
  /// Sky light is typically cool (blue-ish)
  /// Contrasts nicely with warm primary light
  static const double ambientColorTemp = 6500.0; // Cool sky blue
  
  // ========================================================================
  // 🎚️ GLOBAL ADJUSTMENTS (Master Controls)
  // ========================================================================
  
  /// MASTER BRIGHTNESS: Multiply all light intensities by this
  /// Quick way to make entire scene brighter/darker
  /// 1.0 = normal, 1.5 = 50% brighter, 0.7 = 30% dimmer
  static const double masterBrightness = 1.0;
  
  /// ENABLE/DISABLE ENTIRE LIGHTING SETUP
  /// Useful for A/B testing: see scene with vs without custom lighting
  static const bool useCustomLighting = true;
  
  // ========================================================================
  // 🏠 SCENE OBJECT POSITIONING (For Shadow Accuracy)
  // ========================================================================
  
  /// RUG VERTICAL OFFSET
  /// How far above/below ground plane the rug sits
  /// Negative = lower (toward floor), Positive = higher (elevated)
  /// 
  /// The rug should be VERY thin, almost flush with floor
  /// Too high = shadows look disconnected
  /// Too low = might clip through floor
  /// 
  /// Good range: -0.01 to -0.05 (1-5cm below origin)
  static const double rugYOffset = -0.02; // 2cm below origin - nearly flush with floor
  
  // ========================================================================
  // 🌑 SHADOW CONFIGURATION
  // ========================================================================
  
  /// GLOBAL SHADOW ENABLE
  /// Master switch for ALL shadows in the scene
  /// Must be true for any shadows to render (even if lights have castShadows = true)
  static const bool shadowsEnabled = true;
  
  /// SHADOW MAP SIZE
  /// Resolution of shadow texture (higher = sharper shadows, more memory)
  /// Common values: 512, 1024, 2048, 4096
  /// Start with 1024, increase if shadows look blocky
  static const int shadowMapSize = 4096;
  
  /// SHADOW TYPE
  /// PCF = Percentage Closer Filtering (soft shadows) - RECOMMENDED
  /// VSM = Variance Shadow Maps (very soft, can have artifacts/light bleeding)
  /// PCSS = PCF with Soft Shadows (high quality, more expensive)
  /// Start with PCF for most natural look
  /// Note: Uses Thermion's ShadowType enum, not our local one
  static const String shadowType = 'PCF'; // Will be mapped to Thermion's ShadowType.PCF
  
  /// SHADOW SOFTNESS (for PCF shadows)
  /// How soft/hard shadow edges appear
  /// 0.0 = hard shadows, 1.0 = very soft shadows
  /// Good range: 0.3-0.7 for natural look
  static const double shadowSoftness = 0.5;
  
  // ========================================================================
  // 🎭 LIGHTING SCENARIOS (Presets for Different Moods)
  // ========================================================================
  // Switch between these to quickly try different atmospheres
  
  static const LightingScenario currentScenario = LightingScenario.warmCozy;
  
  // Scenario presets (expand these as you experiment!)
  // TODO: Implement scenario switching system if desired
  
  // ========================================================================
  // 🛠️ HELPER METHODS (Don't edit these, edit values above)
  // ========================================================================
  
  /// Create the primary (sun/window) light
  static DirectLight createPrimaryLight() {
    final direction = primaryDirection.normalized();
    return DirectLight.sun(
      color: primaryColorTemp * masterBrightness,
      intensity: primaryIntensity * masterBrightness,
      castShadows: primaryCastsShadows,
      direction: direction,
    );
  }
  
  /// Create the fill light
  static DirectLight createFillLight() {
    final direction = fillDirection.normalized();
    return DirectLight.sun(
      color: fillColorTemp * masterBrightness,
      intensity: fillIntensity * masterBrightness,
      castShadows: fillCastsShadows,
      direction: direction,
    );
  }
  
  /// Create the rim/back light
  static DirectLight createRimLight() {
    final direction = rimDirection.normalized();
    return DirectLight.sun(
      color: rimColorTemp * masterBrightness,
      intensity: rimIntensity * masterBrightness,
      castShadows: rimCastsShadows,
      direction: direction,
    );
  }
  
  /// Get ambient light intensity
  static double getAmbientIntensity() {
    return ambientIntensity * masterBrightness;
  }
  
  /// Get ambient light color temperature
  static double getAmbientColorTemp() {
    return ambientColorTemp;
  }
}

// ========================================================================
// 📦 DATA CLASSES (Type-safe parameter groupings)
// ========================================================================

/// Defines a light direction in intuitive terms
/// Will be normalized automatically when used
class LightDirection {
  final double x;           // Left (-) to Right (+)
  final double y;           // Down (-) to Up (+)
  final double z;           // Far (-) to Near (+)
  final String description; // What this direction represents
  
  const LightDirection({
    required this.x,
    required this.y,
    required this.z,
    required this.description,
  });
  
  /// Return normalized direction vector for Thermion
  Vector3 normalized() {
    final length = Math.sqrt(x * x + y * y + z * z);
    if (length == 0) return Vector3(0, -1, 0); // Default: from above
    return Vector3(x / length, y / length, z / length);
  }
  
  /// Convenience getters for common directions
  static const LightDirection fromAbove = LightDirection(
    x: 0.0, y: -1.0, z: 0.0,
    description: "Straight down from above",
  );
  
  static const LightDirection fromAboveBehind = LightDirection(
    x: 0.0, y: -0.5, z: 0.8,
    description: "From above and behind (natural window light)",
  );
  
  static const LightDirection fromBehind = LightDirection(
    x: 0.0, y: 0.0, z: 1.0,
    description: "Straight from behind (strong rim light)",
  );
  
  static const LightDirection fromFrontAbove = LightDirection(
    x: 0.0, y: -0.5, z: -0.8,
    description: "From front and above (studio key light)",
  );
  
  static const LightDirection fromSideRight = LightDirection(
    x: 1.0, y: -0.3, z: 0.0,
    description: "From right side, slightly above",
  );
  
  static const LightDirection fromSideLeft = LightDirection(
    x: -1.0, y: -0.3, z: 0.0,
    description: "From left side, slightly above",
  );
}

/// Lighting scenarios for different moods/times
enum LightingScenario {
  warmCozy,       // Warm, inviting learning space (default)
  brightClear,    // Bright, energetic, high visibility
  softDreamy,     // Soft, gentle, calming
  dramaticContrast, // High contrast, bold shadows
  goldenHour,     // Warm sunset glow
  overcastNeutral, // Cool, even, neutral
}

// ========================================================================
// 📚 QUICK REFERENCE GUIDE
// ========================================================================
// 
// STARTING POINTS FOR EXPERIMENTATION:
// 
// Want more depth/dimension?
// → Increase primaryIntensity (try 150,000)
// → Decrease fillIntensity (try 30,000)
// 
// Too dark in shadows?
// → Increase fillIntensity
// → Increase ambientIntensity
// 
// Character not grounded?
// → Ensure primaryCastsShadows = true
// → Check primaryDirection has positive Y (from above)
// 
// Want warmer/cozier feel?
// → Decrease primaryColorTemp (try 3500)
// → Decrease rimColorTemp (try 3000)
// 
// Want cooler/crisper feel?
// → Increase primaryColorTemp (try 5500)
// → Increase ambientColorTemp (try 7000)
// 
// Scene too bright overall?
// → Decrease masterBrightness (try 0.8)
// 
// Scene too dark overall?
// → Increase masterBrightness (try 1.2)
// 
// Want more dramatic lighting?
// → Move lights to more extreme angles
// → Increase contrast (high primary, low fill)
// 
// Want softer/flatter lighting?
// → Reduce light angle differences
// → Increase fill closer to primary intensity
// 
// ========================================================================

class Math {
  static double sqrt(double x) => x < 0 ? 0 : x == 0 ? 0 : _sqrt(x);
  
  static double _sqrt(double x) {
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

