import 'dart:math' as math;
import 'package:thermion_flutter/thermion_flutter.dart';
import '../services/director_tuner.dart';

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
  static double get characterHeight => DirectorTuner.instance.getValue('camera', 'characterHeight', 2.0);
  static double get characterCenterHeight => DirectorTuner.instance.getValue('camera', 'characterCenterHeight', 1.1);
  static double get characterEyeLevel => DirectorTuner.instance.getValue('camera', 'characterEyeLevel', 1.3);
  
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
  static ShotComposition get playingShot {
    final tuner = DirectorTuner.instance;
    return ShotComposition(
      distance: tuner.getValue('camera', 'playingShot.distance', 2.96),
      heightOffset: tuner.getValue('camera', 'playingShot.heightOffset', 0.84),
      angleOffset: tuner.getValue('camera', 'playingShot.angleOffset', -0.44),
      description: "Natural gameplay framing - comfortable, clear view",
    );
  }
  
  /// SUCCESS SHOT (Celebrating)
  /// Camera response when child gets word RIGHT
  /// Note: Many celebration animations include JUMPING - camera needs to accommodate this!
  static ShotComposition get celebratingShot {
    final tuner = DirectorTuner.instance;
    return ShotComposition(
      distance: tuner.getValue('camera', 'celebratingShot.distance', 3.0),
      heightOffset: tuner.getValue('camera', 'celebratingShot.heightOffset', 0.2),
      angleOffset: tuner.getValue('camera', 'celebratingShot.angleOffset', 0.0),
      description: "Push-in close but stable for jumps",
    );
  }
  
  /// Vertical offset for celebration look-at point to track jumping
  static double get celebrationLookAtOffset => DirectorTuner.instance.getValue('camera', 'celebrationLookAtOffset', -0.1);
  
  /// FAILURE SHOT (Failing)
  /// Camera response when child struggles or gets word wrong
  static ShotComposition get failingShot {
    final tuner = DirectorTuner.instance;
    return ShotComposition(
      distance: tuner.getValue('camera', 'failingShot.distance', 3.5),
      heightOffset: tuner.getValue('camera', 'failingShot.heightOffset', -0.2),
      angleOffset: tuner.getValue('camera', 'failingShot.angleOffset', 0.0),
      description: "Pull-back with neutral angle = 'It's okay, you've got this'",
    );
  }
  
  /// COMPLETION SHOT (All words done)
  /// Celebratory final shot
  static ShotComposition get completedShot {
    final tuner = DirectorTuner.instance;
    return ShotComposition(
      distance: tuner.getValue('camera', 'completedShot.distance', 5.0),
      heightOffset: tuner.getValue('camera', 'completedShot.heightOffset', 0.8),
      angleOffset: tuner.getValue('camera', 'completedShot.angleOffset', 0.9),
      description: "Victory shot with slight angle",
    );
  }
  
  // ========================================================================
  // ⏱️ TRANSITION TIMING - How fast camera moves between shots
  // ========================================================================
  
  /// SUCCESS TRANSITION
  /// How long the camera takes to push in when celebrating
  /// FASTER = more energetic excitemrent
  static Duration get successTransitionTime {
    final ms = DirectorTuner.instance.getValue('camera', 'successTransitionTime', 800);
    return Duration(milliseconds: ms.toInt());
  }
  
  /// FAILURE TRANSITION
  /// How long the camera takes to pull back when failing
  /// SLOWER = more empathetic, gentle, patient
  static Duration get failureTransitionTime {
    final ms = DirectorTuner.instance.getValue('camera', 'failureTransitionTime', 900);
    return Duration(milliseconds: ms.toInt());
  }
  
  /// NORMAL TRANSITION
  /// Default transition time
  static Duration get normalTransitionTime {
    final ms = DirectorTuner.instance.getValue('camera', 'normalTransitionTime', 800);
    return Duration(milliseconds: ms.toInt());
  }
  
  /// INITIAL GAME TRANSITION
  /// Duration of the opening cinematic zoom when game first starts
  /// (Only happens once at the beginning)
  static Duration get initialGameTransitionTime {
    final ms = DirectorTuner.instance.getValue('camera', 'initialGameTransitionTime', 1500);
    return Duration(milliseconds: ms.toInt());
  }
  
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
  static BreathingLayer get primaryBreathing {
    final tuner = DirectorTuner.instance;
    return BreathingLayer(
      frequency: tuner.getValue('camera', 'primaryBreathing.frequency', 0.512),
      amplitude: tuner.getValue('camera', 'primaryBreathing.amplitude', 0.032),
      description: "Main breathing rhythm - like operator breathing",
    );
  }
  
  /// SLOW DRIFT
  /// Very slow wandering movement
  static BreathingLayer get slowDrift {
    final tuner = DirectorTuner.instance;
    return BreathingLayer(
      frequency: tuner.getValue('camera', 'slowDrift.frequency', 0.2199),
      amplitude: tuner.getValue('camera', 'slowDrift.amplitude', 0.051),
      description: "Slow drift - like operator shifting weight",
    );
  }
  
  /// MICRO SHAKE
  /// Tiny high-frequency tremor
  static BreathingLayer get microShake {
    final tuner = DirectorTuner.instance;
    return BreathingLayer(
      frequency: tuner.getValue('camera', 'microShake.frequency', 6.43),
      amplitude: tuner.getValue('camera', 'microShake.amplitude', 0.0029),
      description: "Micro-shake - like human hand-held tremor",
    );
  }
  
  /// BREATHING INTENSITY MULTIPLIER
  /// Multiply all breathing by this value to exaggerate or reduce
  /// 1.0 = normal, 2.0 = double intensity, 0.5 = half intensity
  static double get breathingIntensityMultiplier => DirectorTuner.instance.getValue('camera', 'breathingIntensityMultiplier', 1.2);
  
  // ========================================================================
  // 🎛️ PARAMETER REGISTRATION (Called during app initialization)
  // ========================================================================
  
  /// Register all tunable parameters with DirectorTuner
  static void registerParameters() {
    // Character reference
    DirectorTuner.register('camera', 'characterHeight', min: 0.5, max: 5.0, defaultValue: 2.0, unit: 'units');
    DirectorTuner.register('camera', 'characterCenterHeight', min: 0.5, max: 3.0, defaultValue: 0.7, unit: 'units');
    DirectorTuner.register('camera', 'characterEyeLevel', min: 0.5, max: 3.0, defaultValue: 1.3, unit: 'units');
    
    // Playing shot
    DirectorTuner.register('camera', 'playingShot.distance', min: 1.0, max: 20.0, defaultValue: 2.77, unit: 'units');
    DirectorTuner.register('camera', 'playingShot.heightOffset', min: -2.0, max: 2.0, defaultValue: 0.44, unit: 'units');
    DirectorTuner.register('camera', 'playingShot.angleOffset', min: -2.0, max: 2.0, defaultValue: -0.44, unit: 'units');
    
    // Celebrating shot
    DirectorTuner.register('camera', 'celebratingShot.distance', min: 1.0, max: 20.0, defaultValue: 3.0, unit: 'units');
    DirectorTuner.register('camera', 'celebratingShot.heightOffset', min: -2.0, max: 2.0, defaultValue: 0.2, unit: 'units');
    DirectorTuner.register('camera', 'celebratingShot.angleOffset', min: -2.0, max: 2.0, defaultValue: 0.0, unit: 'units');
    DirectorTuner.register('camera', 'celebrationLookAtOffset', min: -1.0, max: 1.0, defaultValue: -0.1, unit: 'units');
    
    // Failing shot
    DirectorTuner.register('camera', 'failingShot.distance', min: 1.0, max: 20.0, defaultValue: 3.5, unit: 'units');
    DirectorTuner.register('camera', 'failingShot.heightOffset', min: -2.0, max: 2.0, defaultValue: -0.2, unit: 'units');
    DirectorTuner.register('camera', 'failingShot.angleOffset', min: -2.0, max: 2.0, defaultValue: 0.0, unit: 'units');
    
    // Completed shot
    DirectorTuner.register('camera', 'completedShot.distance', min: 1.0, max: 20.0, defaultValue: 5.0, unit: 'units');
    DirectorTuner.register('camera', 'completedShot.heightOffset', min: -2.0, max: 2.0, defaultValue: 0.8, unit: 'units');
    DirectorTuner.register('camera', 'completedShot.angleOffset', min: -2.0, max: 2.0, defaultValue: 0.9, unit: 'units');
    
    // Transition times (in milliseconds)
    DirectorTuner.register('camera', 'successTransitionTime', min: 100.0, max: 3000.0, defaultValue: 1148.0, unit: 'ms');
    DirectorTuner.register('camera', 'failureTransitionTime', min: 100.0, max: 3000.0, defaultValue: 900.0, unit: 'ms');
    DirectorTuner.register('camera', 'normalTransitionTime', min: 100.0, max: 3000.0, defaultValue: 800.0, unit: 'ms');
    DirectorTuner.register('camera', 'initialGameTransitionTime', min: 100.0, max: 5000.0, defaultValue: 2235.0, unit: 'ms');
    
    // Breathing layers
    DirectorTuner.register('camera', 'primaryBreathing.frequency', min: 0.1, max: 5.0, defaultValue: 0.512, unit: 'Hz');
    DirectorTuner.register('camera', 'primaryBreathing.amplitude', min: 0.0, max: 0.1, defaultValue: 0.032, unit: 'units');
    DirectorTuner.register('camera', 'slowDrift.frequency', min: 0.01, max: 2.0, defaultValue: 0.2199, unit: 'Hz');
    DirectorTuner.register('camera', 'slowDrift.amplitude', min: 0.0, max: 0.1, defaultValue: 0.051, unit: 'units');
    DirectorTuner.register('camera', 'microShake.frequency', min: 1.0, max: 10.0, defaultValue: 6.43, unit: 'Hz');
    DirectorTuner.register('camera', 'microShake.amplitude', min: 0.0, max: 0.01, defaultValue: 0.0029, unit: 'units');
    DirectorTuner.register('camera', 'breathingIntensityMultiplier', min: 0.0, max: 3.0, defaultValue: 0.63, unit: 'multiplier');
  }
  
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

