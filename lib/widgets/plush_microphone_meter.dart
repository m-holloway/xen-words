import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlushMicrophoneMeter extends StatefulWidget {
  final Stream<double>? energyStream;
  final bool isListening;
  final bool isMuted;
  final ValueChanged<bool>? onMuteChanged;
  final double size;

  const PlushMicrophoneMeter({
    Key? key,
    this.energyStream,
    this.isListening = false,
    this.isMuted = false,
    this.onMuteChanged,
    this.size = 120.0,
  }) : super(key: key);

  @override
  State<PlushMicrophoneMeter> createState() => _PlushMicrophoneMeterState();
}

class _PlushMicrophoneMeterState extends State<PlushMicrophoneMeter>
    with SingleTickerProviderStateMixin {
  // Physics for the needle
  double _currentValue = 0.0;
  double _targetValue = 0.0;
  
  // Animation
  late AnimationController _controller;
  StreamSubscription<double>? _subscription;

  // Decay factor (0.0 to 1.0) - closer to 1.0 is slower decay
  static const double _decayFactor = 0.98;
  // Attack factor (0.0 to 1.0) - closer to 1.0 is instant attack
  static const double _attackFactor = 0.6;
  
  // Adaptive scaling state
  double _noiseFloor = 0.00005; // ~-43 dB
  double _peakLevel = 0.0015;   // ~-28 dB
  static const double _minDynamicRange = 0.0002;
  static const double _noiseFollowRate = 0.05;
  static const double _noiseRelaxRate = 0.01;
  static const double _peakAttackRate = 0.25;
  static const double _peakDecayRate = 0.02;
  static const double _silenceMargin = 1.6;
  static const int _silenceHoldMs = 120;
  DateTime? _lastVoiceActivity;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps
    )..addListener(_updatePhysics);
    _controller.repeat();

    _subscribeToStream();
  }

  @override
  void didUpdateWidget(PlushMicrophoneMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.energyStream != oldWidget.energyStream) {
      _subscription?.cancel();
      _subscribeToStream();
    }
  }

  void _subscribeToStream() {
    if (widget.energyStream != null) {
      _subscription = widget.energyStream!.listen((energy) {
        _processEnergySample(energy);
      });
    }
  }

  void _processEnergySample(double energy) {
    final double clamped = energy.clamp(1e-8, 1.0);
    final now = DateTime.now();
    final double silenceThreshold = (_noiseFloor * _silenceMargin).clamp(1e-8, 1.0);
    final bool isVoiceActive = clamped > silenceThreshold;

    if (isVoiceActive) {
      _lastVoiceActivity = now;
    }

    final bool allowNoiseUpdate = !isVoiceActive &&
        (_lastVoiceActivity == null ||
            now.difference(_lastVoiceActivity!).inMilliseconds > _silenceHoldMs);

    // Track noise floor (slowly follows downward energy)
    if (allowNoiseUpdate) {
      if (clamped < _noiseFloor) {
        _noiseFloor = _lerp(_noiseFloor, clamped, _noiseFollowRate);
      } else {
        _noiseFloor = _lerp(_noiseFloor, clamped, _noiseRelaxRate);
      }
    } else if (clamped > _noiseFloor) {
      // Only relax upward very slightly during speech so we don't lag far behind
      _noiseFloor = _lerp(_noiseFloor, clamped, _noiseRelaxRate * 0.5);
    }

    // Track recent peak (fast attack, slow decay)
    if (clamped > _peakLevel) {
      _peakLevel = _lerp(_peakLevel, clamped, _peakAttackRate);
    } else {
      _peakLevel = _lerp(_peakLevel, clamped, _peakDecayRate);
    }

    final double dynamicRange = (_peakLevel - _noiseFloor).clamp(_minDynamicRange, 1.0);
    double normalized = ((clamped - _noiseFloor) / dynamicRange).clamp(0.0, 1.0);

    // Apply soft knee / gamma to make mid-levels stand out
    normalized = math.pow(normalized, 0.42).toDouble();
    final luminous = (normalized * 1.35).clamp(0.0, 1.0);

    // Ensure a gentle baseline glow whenever active
    final baseline = widget.isMuted || !widget.isListening ? 0.0 : 0.01;
    _targetValue = widget.isMuted ? 0.0 : math.max(luminous, baseline);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _updatePhysics() {
    if (!mounted) return;
    if (widget.isMuted || !widget.isListening) {
      _targetValue = 0.0;
    }

    // Simple RC filter simulation
    if (_targetValue > _currentValue) {
      // Attack (rising)
      _currentValue += (_targetValue - _currentValue) * _attackFactor;
    } else {
      // Decay (falling)
      _currentValue += (_targetValue - _currentValue) * (1.0 - _decayFactor);
    }

    // Add some jitter/noise if active and not completely silent
    if (widget.isListening && !widget.isMuted && _currentValue > 0.05) {
       // Tiny random jitter for analog feel
       _currentValue += (math.Random().nextDouble() - 0.5) * 0.01; 
    }
    
    _currentValue = _currentValue.clamp(0.0, 1.0);
    
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onMuteChanged != null) {
      widget.onMuteChanged!(!widget.isMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _MeterPainter(
            value: _currentValue,
            isMuted: widget.isMuted,
            isActive: widget.isListening,
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double value;
  final bool isMuted;
  final bool isActive;

  _MeterPainter({
    required this.value,
    required this.isMuted,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey.shade900,
          Colors.grey.shade700,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    final glassPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.9));
    canvas.drawCircle(center, radius * 0.9, glassPaint);

    final glowStrength = isMuted ? 0.0 : value.clamp(0.0, 1.0);

    if (glowStrength > 0) {
      final ambientPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.greenAccent.withOpacity(glowStrength * 0.35),
            Colors.greenAccent.withOpacity(glowStrength * 0.12),
            Colors.transparent,
          ],
          stops: const [0.35, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.95));
      canvas.drawCircle(center, radius * 0.95, ambientPaint);
    }

    final innerRingRadius = radius * (0.56 + glowStrength * 0.08);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Colors.greenAccent.withOpacity(
        isMuted ? 0.0 : (0.22 + glowStrength * 0.65),
      );
    canvas.drawCircle(center, innerRingRadius, ringPaint);

    final bleedPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, 30 * (0.35 + glowStrength))
      ..color = Colors.greenAccent.withOpacity(isMuted ? 0.0 : 0.4 * glowStrength);
    canvas.drawCircle(center, radius * 0.72, bleedPaint);

    final outerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + glowStrength * 10)
      ..color = Colors.greenAccent.withOpacity(isMuted ? 0.0 : 0.2 + glowStrength * 0.5);
    canvas.drawCircle(center, radius * 0.82, outerRingPaint);

    final coreRadius = radius * (0.25 + glowStrength * 0.55);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(isMuted ? 0.0 : 0.55 + glowStrength * 0.35),
          Colors.greenAccent.withOpacity(isMuted ? 0.0 : 0.15 + glowStrength * 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    final filamentPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + glowStrength * 7)
      ..color = Colors.greenAccent.withOpacity(isMuted ? 0.0 : 0.25 + glowStrength * 0.35);
    canvas.drawCircle(center, coreRadius * 0.6, filamentPaint);

    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.transparent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.95));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.95),
      -math.pi / 1.4,
      math.pi / 1.1,
      true,
      highlightPaint,
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.mic_rounded.codePoint),
        style: TextStyle(
          fontSize: radius * 1.1,
          fontFamily: Icons.mic_rounded.fontFamily,
          package: Icons.mic_rounded.fontPackage,
          color: isMuted
              ? Colors.white.withOpacity(0.25)
              : Colors.white.withOpacity(0.95),
          shadows: isMuted
              ? []
              : [
                  Shadow(
                    color: Colors.greenAccent.withOpacity(0.8),
                    blurRadius: 8,
                  ),
                ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.black.withOpacity(0.4);
    canvas.drawCircle(center, radius - 1.5, rimPaint);
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) {
    return oldDelegate.value != value || 
           oldDelegate.isMuted != isMuted ||
           oldDelegate.isActive != isActive;
  }
}

