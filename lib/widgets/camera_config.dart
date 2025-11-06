import 'package:thermion_flutter/thermion_flutter.dart';

/// Director-friendly camera configuration
/// All camera positions are calculated from these intuitive parameters
/// 
/// Adjust these values to change camera framing without touching the rest of the code.
/// Think of it like directing a film - you set the shot type, height, and angle.
class CameraConfig {
  // Character reference point (where the character is positioned in 3D space)
  static final Vector3 characterPosition = Vector3(0, 0, 0);
  static const double characterHeight = 2.0; // Character's total height
  static const double characterCenterHeight = 1.1; // Character's center (torso level)
  static const double characterEyeLevel = 1.3; // Character's eye level
  
  // Camera distances (how far the camera is from the character)
  static const double distanceWide = 4.5;      // Wide establishing shot
  static const double distanceMedium = 3.0;     // Medium shot (full body visible)
  static const double distanceClose = 2.0;     // Close-up (torso and head)
  static const double distanceTight = 1.5;    // Very tight (face/upper torso)
  
  // Camera heights (relative to character center)
  static const double heightEyeLevel = 0.0;        // At character's eye level
  static const double heightSlightlyAbove = 0.2;   // Slightly above eye level
  static const double heightAbove = 0.5;           // Above character
  static const double heightBelow = -0.3;          // Below character (looking up)
  
  // Camera angles (horizontal offset from center)
  static const double angleStraight = 0.0;    // Straight on
  static const double angleSlightLeft = -0.3; // Slight angle left
  static const double angleSlightRight = 0.3; // Slight angle right
  static const double angleLeft = -0.5;       // More pronounced left
  static const double angleRight = 0.5;       // More pronounced right
  
  /// Calculate camera position from director-friendly parameters
  static Vector3 calculatePosition({
    required double distance,
    double heightOffset = heightEyeLevel,
    double angleOffset = angleStraight,
  }) {
    // Camera is positioned at distance from character, at height, with optional angle
    return Vector3(
      angleOffset, // X: horizontal angle (left/right)
      characterCenterHeight + heightOffset, // Y: character center + height offset
      distance, // Z: distance from character
    );
  }
  
  // Predefined shot types for easy use
  static Vector3 get wideShot => calculatePosition(
    distance: distanceWide,
    heightOffset: heightSlightlyAbove,
  );
  
  static Vector3 get mediumShot => calculatePosition(
    distance: distanceMedium,
    heightOffset: heightEyeLevel,
  );
  
  static Vector3 get closeUp => calculatePosition(
    distance: distanceClose,
    heightOffset: heightEyeLevel,
  );
  
  static Vector3 get tightShot => calculatePosition(
    distance: distanceTight,
    heightOffset: heightEyeLevel,
  );
  
  // Game state specific shots
  static Vector3 get playingShot => calculatePosition(
    distance: distanceMedium,
    heightOffset: 1.1, // Frame character higher in frame (moved up 2x more: 0.7 + 0.4 = 1.1)
  );
  
  static Vector3 get celebratingShot => calculatePosition(
    distance: distanceMedium, // Wider shot to accommodate jump animations and other dynamic movements
    heightOffset: heightSlightlyAbove, // Slightly above to see jumps better
  );
  
  static Vector3 get failingShot => calculatePosition(
    distance: distanceWide,
    heightOffset: heightSlightlyAbove,
  );
  
  static Vector3 get completedShot => calculatePosition(
    distance: distanceMedium,
    heightOffset: 1.1, // Moved up 2x more: 0.7 + 0.4 = 1.1
    angleOffset: angleSlightRight,
  );
  
  // Splash screen specific shots
  static Vector3 get splashIntroShot => calculatePosition(
    distance: distanceMedium, // Start closer so character is visible
    heightOffset: heightSlightlyAbove,
  );
  
  static Vector3 get splashIdleShot => calculatePosition(
    distance: distanceMedium,
    heightOffset: heightSlightlyAbove,
  );
  
  static Vector3 get splashCloseShot => calculatePosition(
    distance: distanceClose,
    heightOffset: heightEyeLevel,
  );
}

