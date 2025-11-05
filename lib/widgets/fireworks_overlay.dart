import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/color_generator.dart';

/// A single firework particle
class Particle {
  Offset position;
  Offset velocity;
  Color color;
  double size;
  double life;
  double maxLife;
  double alpha;

  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.maxLife,
  })  : life = maxLife,
        alpha = 1.0;

  void update(double dt) {
    // Apply gravity
    velocity = Offset(
      velocity.dx,
      velocity.dy + 300 * dt, // gravity
    );

    // Apply air resistance
    velocity = Offset(
      velocity.dx * 0.99,
      velocity.dy * 0.99,
    );

    // Update position
    position = Offset(
      position.dx + velocity.dx * dt,
      position.dy + velocity.dy * dt,
    );

    // Update life
    life -= dt;
    alpha = (life / maxLife).clamp(0.0, 1.0);
  }

  bool get isDead => life <= 0;
}

/// Manages a collection of firework particles
class Firework {
  final Offset origin;
  final List<Particle> particles = [];
  final Color color;
  bool hasExploded = false;
  double fuse = 0.8;

  Firework({required this.origin, required this.color});

  void explode() {
    if (hasExploded) return;
    hasExploded = true;

    final random = Random();
    const particleCount = 50;

    for (int i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * pi;
      final speed = 100 + random.nextDouble() * 100;
      final velocity = Offset(
        cos(angle) * speed,
        sin(angle) * speed,
      );

      particles.add(Particle(
        position: origin,
        velocity: velocity,
        color: color,
        size: 3 + random.nextDouble() * 3,
        maxLife: 1.0 + random.nextDouble() * 1.0,
      ));
    }
  }

  void update(double dt) {
    if (!hasExploded) {
      fuse -= dt;
      if (fuse <= 0) {
        explode();
      }
    }

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

  List<Firework> get fireworks => _fireworks;

  bool get isDone => _fireworks.isEmpty || _fireworks.every((f) => f.isDone);

  void launchSingle(Size size) {
    final random = Random();
    final x = size.width * 0.3 + random.nextDouble() * size.width * 0.4;
    final y = size.height * 0.3 + random.nextDouble() * size.height * 0.2;

    _fireworks.add(Firework(
      origin: Offset(x, y),
      color: ColorGenerator.randomColor(),
    ));
    notifyListeners();
  }

  void launchMultiple(Size size, {int count = 5}) {
    final random = Random();
    for (int i = 0; i < count; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (_fireworks.length < count) {
          final x = size.width * 0.2 + random.nextDouble() * size.width * 0.6;
          final y = size.height * 0.2 + random.nextDouble() * size.height * 0.3;

          _fireworks.add(Firework(
            origin: Offset(x, y),
            color: ColorGenerator.randomColor(),
          ));
          notifyListeners();
        }
      });
    }
  }

  void update() {
    final now = DateTime.now();
    if (_lastUpdate == null) {
      _lastUpdate = now;
      return;
    }

    final dt = now.difference(_lastUpdate!).inMicroseconds / 1000000.0;
    _lastUpdate = now;

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

/// Custom painter for rendering fireworks
class FireworksPainter extends CustomPainter {
  final List<Firework> fireworks;

  FireworksPainter({required this.fireworks});

  @override
  void paint(Canvas canvas, Size size) {
    for (var firework in fireworks) {
      for (var particle in firework.particles) {
        final paint = Paint()
          ..color = particle.color.withOpacity(particle.alpha)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

        canvas.drawCircle(
          particle.position,
          particle.size,
          paint,
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

