import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/color_generator.dart';

/// 3D vector for position and velocity
class Vector3 {
  double x, y, z;
  
  Vector3(this.x, this.y, this.z);
  
  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) => Vector3(x - other.x, y - other.y, z - other.z);
  Vector3 operator *(double scalar) => Vector3(x * scalar, y * scalar, z * scalar);
  Vector3 operator /(double scalar) => Vector3(x / scalar, y / scalar, z / scalar);
  
  double get length => sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;
  
  Vector3 normalized() {
    final len = length;
    if (len > 0) return this / len;
    return Vector3(0, 0, 0);
  }
  
  Vector3 copy() => Vector3(x, y, z);
}

/// A single firework particle with proper 3D physics
class Particle {
  Vector3 position; // 3D position
  Vector3 velocity; // 3D velocity
  Color color;
  double baseSize; // Base size before perspective scaling
  double life;
  double maxLife;
  double alpha;
  
  // Perspective projection parameters
  static const double cameraDistance = 1000.0; // Distance from camera to projection plane
  static const double nearPlane = 100.0; // Closest visible distance
  static const double farPlane = 2000.0; // Farthest visible distance
  
  // Trail tracking for particle trails effect (simplified for performance)
  final List<Offset> trail = [];
  static const int maxTrailLength = 5;

  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.baseSize,
    required this.maxLife,
  })  : life = maxLife,
        alpha = 1.0;

  /// Project 3D position to 2D screen coordinates using perspective projection
  /// Z is depth (positive = away from camera, negative = toward camera)
  /// We use standard perspective: screen = (x * d / (d + z), y * d / (d + z))
  /// where d is camera distance and z is depth from camera plane
  Offset projectToScreen() {
    // Perspective projection: screen coordinates are scaled by distance factor
    // z = 0 means at camera distance, z > 0 means further away, z < 0 means closer
    final distanceFactor = cameraDistance / (cameraDistance + position.z);
    return Offset(
      position.x * distanceFactor,
      position.y * distanceFactor,
    );
  }

  /// Get distance from camera (for perspective calculations)
  double get distanceFromCamera {
    // Distance from camera is cameraDistance + z
    // z = 0 means at camera plane, z > 0 means further away
    return cameraDistance + position.z;
  }

  /// Get the actual rendered size based on 3D perspective
  /// Uses proper perspective scaling: size scales inversely with distance from camera
  double get perspectiveSize {
    final distance = distanceFromCamera;
    if (distance <= 0) return baseSize * 2.0; // Clamp if too close
    
    // Perspective scaling: size is inversely proportional to distance
    // At cameraDistance, size = baseSize
    // Closer = larger, further = smaller
    final scale = cameraDistance / distance;
    return (baseSize * scale).clamp(baseSize * 0.1, baseSize * 3.0);
  }

  /// Get alpha adjusted for depth (particles further away fade more)
  double get depthAlpha {
    final distance = distanceFromCamera;
    // Fade particles that are very far or very close
    if (distance < nearPlane || distance > farPlane) {
      final fadeFactor = distance < nearPlane 
          ? distance / nearPlane 
          : (farPlane - distance) / (farPlane - cameraDistance);
      return alpha * fadeFactor.clamp(0.0, 1.0);
    }
    return alpha;
  }

  void update(double dt) {
    // Store previous screen position for trail
    final screenPos = projectToScreen();
    trail.add(screenPos);
    if (trail.length > maxTrailLength) {
      trail.removeAt(0);
    }

    // Apply gravity in 3D space (downward in Y direction)
    // Gravity is a 3D force vector pointing downward
    final gravity = Vector3(0, 300, 0); // 300 pixels/sec^2 downward
    velocity = velocity + gravity * dt;

    // Apply air resistance in 3D (affects all velocity components equally)
    // Air resistance is proportional to velocity squared, but we approximate with linear damping
    const airResistanceFactor = 0.98;
    velocity = velocity * airResistanceFactor;

    // Update 3D position using 3D velocity
    position = position + velocity * dt;

    // Update life
    life -= dt;
    alpha = (life / maxLife).clamp(0.0, 1.0);
  }

  bool get isDead => life <= 0;
}

/// Manages a collection of firework particles
class Firework {
  final Offset origin; // Explosion position
  final List<Particle> particles = [];
  final Color color;
  final int particleCount; // Number of particles per firework (tunable)
  bool hasExploded = false;
  
  // Launch trajectory state - pre-calculated velocity that particles will inherit
  late final Vector3 explosionVelocity; // Pre-calculated launch velocity at explosion time (inherited by particles)
  
  // Launch parameters
  static const double launchSpeed = 800.0; // Initial launch speed in pixels/sec
  static const double launchDepth = 200.0; // Launch starts away from camera (positive Z = away)
  static const double launchAngleVariation = 0.3; // Random variation in launch angle (radians)
  static const double fuseTime = 0.8; // Simulated fuse time for velocity calculation

  Firework({
    required this.origin, 
    required this.color,
    this.particleCount = 35, // Default particle count
  }) {
    // Calculate what the launch velocity would be at explosion time (without simulating)
    // This simulates a rocket launched upward that has been traveling for fuseTime seconds
    explosionVelocity = _calculateLaunchVelocity();
    
    // Explode immediately with pre-calculated velocity
    explode();
  }
  
  /// Calculate what the launch velocity would be at explosion time
  /// This simulates a rocket launched upward that has been traveling for fuseTime seconds
  /// The velocity accounts for gravity and air resistance over the fuse period
  Vector3 _calculateLaunchVelocity() {
    final random = Random();
    
    // Calculate initial launch velocity (mostly upward, with some horizontal component)
    // Add some horizontal randomness to the launch angle
    final angleVariation = (random.nextDouble() - 0.5) * launchAngleVariation;
    final verticalAngle = pi / 2 - 0.3 + angleVariation; // Mostly upward, slight angle
    
    // Initial launch velocity components
    final initialVelocityX = launchSpeed * sin(angleVariation) * 0.5;
    final initialVelocityY = -launchSpeed * cos(verticalAngle); // Negative Y = upward
    final initialVelocityZ = launchSpeed * 0.3; // Going away from camera (positive Z)
    
    // Simulate physics over fuseTime to get velocity at explosion
    // We integrate gravity and air resistance over the fuse period
    final gravity = Vector3(0, 300, 0); // 300 pixels/sec^2 downward
    const airResistanceFactor = 0.99;
    
    // Approximate velocity after fuseTime seconds
    // v(t) ≈ (v0 * r^t) + (g * (1 - r^t) / (1 - r))
    // where r is air resistance factor
    // For simplicity, we'll use: v(t) = v0 * r^t + g * t * (1 - r^t/2)
    final resistanceFactor = pow(airResistanceFactor, fuseTime);
    final velocityX = initialVelocityX * resistanceFactor;
    final velocityY = initialVelocityY * resistanceFactor + gravity.y * fuseTime * (1 - resistanceFactor / 2);
    final velocityZ = initialVelocityZ * resistanceFactor; // Z velocity also affected by air resistance
    
    return Vector3(velocityX, velocityY, velocityZ);
  }

  void explode() {
    if (hasExploded) return;
    hasExploded = true;

    // Explosion happens at the origin point, at a reasonable depth away from camera
    // Z is positive = away from camera
    final explosionCenter = Vector3(origin.dx, origin.dy, launchDepth);

    final random = Random();
    
    // Starting radius for the explosion - particles start distributed within this sphere
    // Use a larger radius for a more visible initial burst
    final startRadius = 80.0; // User can adjust this - larger = more spread

    for (int i = 0; i < particleCount; i++) {
      // Create a true 3D spherical explosion
      // Use spherical coordinates: theta (azimuth), phi (elevation)
      // Add small random variation to angles for natural spread
      final baseTheta = random.nextDouble() * 2 * pi; // Horizontal angle (0 to 2π)
      final basePhi = random.nextDouble() * pi; // Vertical angle (0 to π)
      
      // Add small random variation to angles for natural spread (about ±10% variation)
      final angleVariation = 0.1; // 10% variation
      final theta = baseTheta + (random.nextDouble() - 0.5) * angleVariation * 2 * pi;
      final phi = basePhi + (random.nextDouble() - 0.5) * angleVariation * pi;
      
      // Initial position: distribute particles within a sphere volume (not just on surface)
      // Use random radius within the sphere for more natural distribution
      final randomRadius = startRadius * (0.75 + random.nextDouble() * 0.25); // 75-100% of startRadius
      
      // Calculate initial 3D position using spherical coordinates relative to explosion center
      // X and Y are screen coordinates, Z is depth (positive = away from camera)
      final startX = explosionCenter.x + randomRadius * sin(basePhi) * cos(baseTheta);
      final startY = explosionCenter.y + randomRadius * sin(basePhi) * sin(baseTheta);
      final startZ = explosionCenter.z + randomRadius * cos(basePhi);
      
      final startPosition3D = Vector3(startX, startY, startZ);
      
      // Calculate velocity in the radial direction from explosion center to initial position
      // Direction vector from explosion center to start position in 3D
      final directionX = startX - explosionCenter.x;
      final directionY = startY - explosionCenter.y;
      final directionZ = startZ - explosionCenter.z;
      
      final direction = Vector3(directionX, directionY, directionZ);
      
      // Speed with some randomness
      final speed = 400 + random.nextDouble() * 800; // Broader speed range for more spread
      
      // Radial velocity is in the direction outward from explosion center
      Vector3 radialVelocity;
      if (direction.length > 0.001) {
        final normalized = direction.normalized();
        radialVelocity = normalized * speed;
      } else {
        // Fallback: use spherical coordinates if direction is zero
        radialVelocity = Vector3(
          speed * sin(phi) * cos(theta),
          speed * sin(phi) * sin(theta),
          speed * cos(phi),
        );
      }
      
      // CRITICAL: Add the pre-calculated launch velocity at explosion time
      // This makes particles continue in the direction of the launch trajectory
      // The radial explosion velocity is added to the trajectory velocity
      // This simulates a firework that was launched and is now exploding mid-flight
      final particleVelocity = radialVelocity + explosionVelocity;

      particles.add(Particle(
        position: startPosition3D,
        velocity: particleVelocity,
        color: color,
        baseSize: 2.5 + random.nextDouble() * 3.5, // Smaller base size
        maxLife: 1.2 + random.nextDouble() * 1.5,
      ));
    }
  }

  void update(double dt) {
    // No fuse simulation needed - explosion happens immediately
    // Just update existing particles

    particles.removeWhere((p) => p.isDead);
    for (var particle in particles) {
      particle.update(dt);
    }
  }

  bool get isDone => hasExploded && particles.isEmpty;
}

/// Controller for managing multiple fireworks
class FireworksController extends ChangeNotifier {
  final List<Firework> _fireworks = [];
  DateTime? _lastUpdate;
  Size? _screenSize;
  Offset? _wordPosition;
  Color? _lastFireworkColor; // Store the last firework color

  // Tunable parameters for firework effects
  static const int defaultParticleCount = 35; // Particles per firework for single launches
  static const int finaleParticleCount = 25; // Particles per firework for multi-launch finale (~30% reduction)

  List<Firework> get fireworks => _fireworks;
  Color? get lastFireworkColor => _lastFireworkColor;

  bool get isDone => _fireworks.isEmpty || _fireworks.every((f) => f.isDone);
  
  /// Update screen size and word position for better firework placement
  void updateScreenSize(Size screenSize, Offset wordPosition) {
    _screenSize = screenSize;
    _wordPosition = wordPosition;
  }

  void launchSingle(Size? size, {Offset? wordPosition}) {
    final random = Random();
    final screenSize = size ?? _screenSize ?? const Size(800, 600);
    final wordPos = wordPosition ?? _wordPosition;
    
    // If word position is provided, launch above the word
    // Otherwise use intentional placement in upper-middle area
    Offset origin;
    if (wordPos != null) {
      // Launch above the word, with broader horizontal variation
      // Word is typically centered, so position above center with more variation
      final x = wordPos.dx + (random.nextDouble() - 0.5) * screenSize.width * 0.35; // ±17.5% variation (broader)
      // Position above word - typically word is at ~40% height, so place at 25-35%
      final y = (wordPos.dy - screenSize.height * 0.15).clamp(
        screenSize.height * 0.15, // At least 15% from top
        screenSize.height * 0.45,  // At most 45% from top (above word)
      );
      origin = Offset(x.clamp(screenSize.width * 0.15, screenSize.width * 0.85), y);
    } else {
      // Fallback: intentional placement in upper-middle area
      final x = screenSize.width * 0.3 + random.nextDouble() * screenSize.width * 0.4;
      final y = screenSize.height * 0.35 + random.nextDouble() * screenSize.height * 0.2;
      origin = Offset(x, y);
    }
    
    // Ensure origin stays well within screen bounds (accounting for starting radius)
    final startRadius = 15.0;
    origin = Offset(
      origin.dx.clamp(startRadius + 10, screenSize.width - startRadius - 10),
      origin.dy.clamp(startRadius + 10, screenSize.height - startRadius - 10),
    );

    final fireworkColor = ColorGenerator.randomColor();
    _lastFireworkColor = fireworkColor; // Store the color
    _fireworks.add(Firework(
      origin: origin,
      color: fireworkColor,
      particleCount: defaultParticleCount, // Use full particle count for single launches
    ));
    notifyListeners();
  }

  void launchMultiple(Size? size, {int count = 7, Offset? wordPosition}) {
    final screenSize = size ?? _screenSize ?? const Size(800, 600);
    final wordPos = wordPosition ?? _wordPosition;
    final startRadius = 40.0;
    
    // Launch fireworks with randomized spacing for a more organic, natural finale feel
    const baseDelayBetweenLaunches = 750; // Base delay in ms between fireworks
    const delayVariation = 200; // Random variation range (±100ms)
    
    final random = Random();
    int cumulativeDelay = 0;
    
    for (int i = 0; i < count; i++) {
      // Add random variation to each launch time for organic feel
      final randomOffset = (random.nextDouble() - 0.5) * delayVariation; // ±100ms
      final thisDelay = (baseDelayBetweenLaunches + randomOffset).round().clamp(400, 1000);
      cumulativeDelay += thisDelay;
      
      Future.delayed(Duration(milliseconds: cumulativeDelay), () {
        // Create a new Random instance inside the delayed callback for position randomness
        final random = Random();
        
        Offset origin;
        if (wordPos != null) {
          // Launch above the word with broader variation
          final x = wordPos.dx + (random.nextDouble() - 0.5) * screenSize.width * 0.4; // Broader horizontal spread
          final y = (wordPos.dy - screenSize.height * 0.15).clamp(
            screenSize.height * 0.15,
            screenSize.height * 0.5,
          );
          origin = Offset(x.clamp(startRadius + 10, screenSize.width - startRadius - 10), y);
        } else {
          // Fallback placement
          final x = screenSize.width * 0.3 + random.nextDouble() * screenSize.width * 0.4;
          final y = screenSize.height * 0.35 + random.nextDouble() * screenSize.height * 0.2;
          origin = Offset(x, y);
        }
        
        // Ensure origin stays well within screen bounds
        origin = Offset(
          origin.dx.clamp(startRadius + 10, screenSize.width - startRadius - 10),
          origin.dy.clamp(startRadius + 10, screenSize.height - startRadius - 10),
        );

        final fireworkColor = ColorGenerator.randomColor();
        _lastFireworkColor = fireworkColor; // Store the color
        _fireworks.add(Firework(
          origin: origin,
          color: fireworkColor,
          particleCount: finaleParticleCount, // Use reduced particle count for finale (~30% less)
        ));
        notifyListeners();
      });
    }
  }

  void update() {
    final now = DateTime.now();
    if (_lastUpdate == null) {
      _lastUpdate = now;
      return;
    }

    // Calculate delta time and clamp it to prevent large time jumps
    // This prevents animation from running too fast if there's a delay
    var dt = now.difference(_lastUpdate!).inMicroseconds / 1000000.0;
    dt = dt.clamp(0.0, 0.05); // Clamp to max 50ms (20 FPS minimum)
    _lastUpdate = now;

    // Only update if we have fireworks to avoid unnecessary work
    if (_fireworks.isEmpty) return;

    for (var firework in _fireworks) {
      firework.update(dt);
    }

    _fireworks.removeWhere((f) => f.isDone);
    notifyListeners();
  }

  void clear() {
    _fireworks.clear();
    _lastUpdate = null;
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}

/// Custom painter for rendering fireworks with additive blending and trails
class FireworksPainter extends CustomPainter {
  final List<Firework> fireworks;

  FireworksPainter({required this.fireworks});

  @override
  void paint(Canvas canvas, Size size) {
    // Enhanced rendering with blurry glow and hot center
    // Reuse Paint objects to avoid allocation overhead
    
    final outerGlowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8) // Nice blurry glow
      ..blendMode = BlendMode.plus;
    
    final innerGlowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..blendMode = BlendMode.plus;
    
    final corePaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;

    for (var firework in fireworks) {
      for (var particle in firework.particles) {
        // Project 3D position to 2D screen coordinates using perspective projection
        final screenPosition = particle.projectToScreen();
        
        // Get perspective-adjusted size and alpha
        final size = particle.perspectiveSize;
        final alpha = particle.depthAlpha;
        
        // Draw trails with blurred colored line and hot center line
        if (particle.trail.length >= 2) {
          final startPoint = particle.trail.first;
          final endPoint = particle.trail.last;
          
          // Draw blurred colored trail (outer glow) - size scales with perspective
          final blurredTrailPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 1.7 // Scale trail width with particle size
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
            ..blendMode = BlendMode.plus
            ..color = particle.color.withValues(alpha: alpha * 0.9);
          
          canvas.drawLine(startPoint, endPoint, blurredTrailPaint);
          
          // Draw hot center line (bright, sharp) - size scales with perspective
          final hotTrailPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.3
            ..strokeCap = StrokeCap.round
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(alpha: alpha*.7);
          
          canvas.drawLine(startPoint, endPoint, hotTrailPaint);
        }

        // Draw outer blurry glow (nice soft halo) - scales with perspective
        outerGlowPaint.color = particle.color.withValues(alpha: alpha * 0.6);
        canvas.drawCircle(
          screenPosition,
          size * 3,
          outerGlowPaint,
        );

        // Draw inner glow (medium blur) - scales with perspective
        innerGlowPaint.color = particle.color.withValues(alpha: alpha * 0.8);
        canvas.drawCircle(
          screenPosition,
          size * 1.9,
          innerGlowPaint,
        );

        // Draw core particle (bright center) - scales with perspective
        corePaint.color = particle.color.withValues(alpha: alpha);
        canvas.drawCircle(
          screenPosition,
          size,
          corePaint,
        );
        
        // Draw hot white center (the really nice bright spot) - scales with perspective
        final hotPaint = Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.97)
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.plus;
        canvas.drawCircle(
          screenPosition,
          size * 0.55,
          hotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FireworksPainter oldDelegate) => true;
}

/// Widget that displays fireworks overlay
class FireworksOverlay extends StatefulWidget {
  final FireworksController controller;

  const FireworksOverlay({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<FireworksOverlay> createState() => _FireworksOverlayState();
}

class _FireworksOverlayState extends State<FireworksOverlay>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      widget.controller.update();
    });
    _ticker.start();
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FireworksPainter(fireworks: widget.controller.fireworks),
        size: Size.infinite,
      ),
    );
  }
}

