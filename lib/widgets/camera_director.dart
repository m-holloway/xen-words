import 'dart:math' as math;
import 'package:thermion_flutter/thermion_flutter.dart';

/// 🎬 CAMERA DIRECTOR'S CONTROL PANEL 🎬
/// 
/// All camera behavior parameters in one place for easy tuning.
/// All values are in INTUITIVE, CONTEXTUAL units - no mental math needed!
/// 
/// HOW TO USE:
/// 1. Adjust parameters below
/// 2. Hot reload to see changes
/// 3. Exaggerate values to see effects clearly
/// 4. Tune back to what feels right
class CameraDirector {
  // ========================================================================
  // 📐 CHARACTER REFERENCE (Direct values - no scaling!)
  // ========================================================================
  // 
  // UNITS: Camera working units (different from model bounding box!)
  // 
  // IMPORTANT: characterCenterHeight is WHERE THE CAMERA LOOKS (focus point),
  // NOT where the model's geometric center is!
  // 
  // Model geometric center: 0.0 (from validation)
  // Camera look-at point: 1.1 (torso/chest area for good framing)
  // 
  // heightOffset is relative to the look-at point:
  //   Camera Y = characterCenterHeight + heightOffset
  //   Camera looks at Y = characterCenterHeight
  
  static final Vector3 characterBasePosition = Vector3(0, 0, 0);
  
  // Effective working values (tune these!)
  static const double characterHeight = 2.0;           // Working height for camera
  static const double characterCenterHeight = 1.1;     // WHERE CAMERA LOOKS (torso/chest for framing)
  static const double characterEyeLevel = 1.3;         // Eye level reference
  
  // For reference: Model bounding box from validation
  // (These are in model space, not camera space!)
  // Bounding box height: 44.33 units
  // Bounding box center: 0.00 units
  // Bounding box eye estimate: 11.08 units
  
  // ========================================================================
  // 🎯 SHOT COMPOSITION - How close/far and high/low the camera is
  // ========================================================================
  
  /// NORMAL GAMEPLAY SHOT
  /// This is the "neutral" framing during regular play
  static const ShotComposition playingShot = ShotComposition(
    distance: 3.6,           // Distance from character
    heightOffset: -0.2,       // Height above LOOK-AT point (characterCenterHeight + this)
    angleOffset: -0.2,        // Side angle (+ = right, - = left)
    description: "Natural gameplay framing - comfortable, clear view",
  );
  
  /// SUCCESS SHOT (Celebrating)
  /// Camera response when child gets word RIGHT
  /// Note: Many celebration animations include JUMPING - camera needs to accommodate this!
  static const ShotComposition celebratingShot = ShotComposition(
    distance: 2.8,           // Slightly wider to keep jumps in frame (was 2.0)
    heightOffset: .2,       // Less height difference = more stable during jumps (was 0.5)
    angleOffset: 0.0,        // Straight on
    description: "Push-in close but stable for jumps",
  );
  
  /// Vertical offset for celebration look-at point to track jumping
  static const double celebrationLookAtOffset = -0.1; // Look higher during celebration
  
  /// FAILURE SHOT (Failing)
  /// Camera response when child struggles or gets word wrong
  static const ShotComposition failingShot = ShotComposition(
    distance: 3.5,            // Give space but not too extreme (was 5.0)
    heightOffset: -0.2,       // Eye level = neutral, non-judgmental (was -0.3)
    angleOffset: 0.0,        // Straight on
    description: "Pull-back with neutral angle = 'It's okay, you've got this'",
  );
  
  /// COMPLETION SHOT (All words done)
  /// Celebratory final shot
  static const ShotComposition completedShot = ShotComposition(
    distance: 3.0,
    heightOffset: 0.8,       // Match playing shot framing
    angleOffset: 0.9,        // Slight angle for visual interest
    description: "Victory shot with slight angle",
  );
  
  // ========================================================================
  // ⏱️ TRANSITION TIMING - How fast camera moves between shots
  // ========================================================================
  
  /// SUCCESS TRANSITION
  /// How fast to push in when celebrating
  /// FASTER = more energetic excitemrent
  static const Duration successTransitionSpeed = Duration(milliseconds: 800);
  
  /// FAILURE TRANSITION
  /// How fast to pull back when failing
  /// SLOWER = more empathetic, gentle, patient
  static const Duration failureTransitionSpeed = Duration(milliseconds: 900);
  
  /// NORMAL TRANSITION
  /// Default transition speed
  static const Duration normalTransitionSpeed = Duration(milliseconds: 800);
  
  /// CINEMATIC INTRO ZOOM
  /// Initial zoom-in when game starts
  static const Duration cinematicZoomSpeed = Duration(milliseconds: 1500);
  
  // ========================================================================
  // 🎲 RANDOMNESS & VARIATION - Makes movements feel organic, not robotic
  // ========================================================================
  
  /// Add random variation to shot composition targets
  /// This prevents every success/failure from looking exactly the same
  static const RandomVariation shotVariation = RandomVariation(
    distanceVariation: 0.1,      // ±10cm distance variation
    heightVariation: 0.05,       // ±5cm height variation
    angleVariation: 0.05,        // ±5cm side angle variation
    enabled: true,
  );
  
  /// Add random "overshoot" to transitions (like momentum)
  /// Makes camera feel like it has weight and a human operator
  static const RandomOvershoot transitionOvershoot = RandomOvershoot(
    overshootAmount: 0.15,       // How much to overshoot (5% of distance)
    overshootProbability: 0.8,   // 30% chance of overshoot on any transition
    enabled: false,               // TODO: Enable when implementing momentum
  );
  
  // ========================================================================
  // 🌊 ORGANIC BREATHING - Multi-frequency camera movement during idle
  // ========================================================================
  
  /// PRIMARY BREATHING
  /// Main slow breathing rhythm (most noticeable)
  static const BreathingLayer primaryBreathing = BreathingLayer(
    frequency:1.1,              // Cycles per second (slower = more dramatic)
    amplitude: 0.006,            // Movement distance (60% of total)
    description: "Main breathing rhythm - like operator breathing",
  );
  
  /// SLOW DRIFT
  /// Very slow wandering movement
  static const BreathingLayer slowDrift = BreathingLayer(
    frequency: 0.2,              // Very slow
    amplitude: 0.006,            // Movement distance (30% of total)
    description: "Slow drift - like operator shifting weight",
  );
  
  /// MICRO SHAKE
  /// Tiny high-frequency tremor
  static const BreathingLayer microShake = BreathingLayer(
    frequency: 4.0,              // Fast
    amplitude: 0.002,            // Movement distance (10% of total)
    description: "Micro-shake - like human hand-held tremor",
  );
  
  /// BREATHING INTENSITY MULTIPLIER
  /// Multiply all breathing by this value to exaggerate or reduce
  /// 1.0 = normal, 2.0 = double intensity, 0.5 = half intensity
  static const double breathingIntensityMultiplier = 1.2;
  
  // ========================================================================
  // 📊 HELPER METHODS - Don't edit these, edit values above
  // ========================================================================
  
  static final math.Random _random = math.Random();
  
  /// Apply random variation to a shot composition
  static Vector3 getVariedShot(ShotComposition shot) {
    if (!shotVariation.enabled) {
      return _shotToVector3(shot);
    }
    
    final distanceVar = ((_random.nextDouble() * 2 - 1) * shotVariation.distanceVariation);
    final heightVar = ((_random.nextDouble() * 2 - 1) * shotVariation.heightVariation);
    final angleVar = ((_random.nextDouble() * 2 - 1) * shotVariation.angleVariation);
    
    // Direct values - no scaling
    return Vector3(
      shot.angleOffset + angleVar,
      characterCenterHeight + shot.heightOffset + heightVar,
      shot.distance + distanceVar,
    );
  }
  
  /// Convert shot composition to Vector3 (no variation)
  static Vector3 _shotToVector3(ShotComposition shot) {
    return Vector3(
      shot.angleOffset,
      characterCenterHeight + shot.heightOffset,
      shot.distance,
    );
  }
  
  /// Get character center position in world space
  /// Optionally offset for animations that move vertically (like jumping)
  static Vector3 getCharacterCenter(Vector3 characterWorldPos, {double verticalOffset = 0.0}) {
    return characterWorldPos + Vector3(0, characterCenterHeight + verticalOffset, 0);
  }
}

// ========================================================================
// 📦 DATA CLASSES - Type-safe parameter groupings
// ========================================================================

/// Defines a camera shot composition
class ShotComposition {
  final double distance;        // Distance from character (Z-axis)
  final double heightOffset;    // Height relative to character center (Y-axis)
  final double angleOffset;     // Side angle (X-axis)
  final String description;     // What this shot communicates
  
  const ShotComposition({
    required this.distance,
    required this.heightOffset,
    required this.angleOffset,
    required this.description,
  });
}

/// Defines random variation parameters
class RandomVariation {
  final double distanceVariation;   // ± variation in distance
  final double heightVariation;     // ± variation in height
  final double angleVariation;      // ± variation in angle
  final bool enabled;
  
  const RandomVariation({
    required this.distanceVariation,
    required this.heightVariation,
    required this.angleVariation,
    required this.enabled,
  });
}

/// Defines random overshoot parameters (for momentum feel)
class RandomOvershoot {
  final double overshootAmount;        // How much to overshoot
  final double overshootProbability;   // Chance of overshoot (0.0 to 1.0)
  final bool enabled;
  
  const RandomOvershoot({
    required this.overshootAmount,
    required this.overshootProbability,
    required this.enabled,
  });
}

/// Defines a breathing/drift layer
class BreathingLayer {
  final double frequency;       // Cycles per second
  final double amplitude;       // Movement amount
  final String description;
  
  const BreathingLayer({
    required this.frequency,
    required this.amplitude,
    required this.description,
  });
}

