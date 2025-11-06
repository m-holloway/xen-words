import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/game_controller.dart';

/// Widget for displaying the current word with clean, elegant animations
class WordDisplay extends StatefulWidget {
  final String word;
  final GameState gameState;
  final VoidCallback? onTap;
  final Color? celebrationColor; // Optional dynamic color for celebration outline

  const WordDisplay({
    Key? key,
    required this.word,
    required this.gameState,
    this.onTap,
    this.celebrationColor,
  }) : super(key: key);

  @override
  State<WordDisplay> createState() => _WordDisplayState();
}

class _WordDisplayState extends State<WordDisplay> with TickerProviderStateMixin {
  // ============================================================================
  // ANIMATION CONFIGURATION - Adjust these values to tune the animations
  // ============================================================================
  
  // SUCCESS CELEBRATION ANIMATION
  static const int _celebrationOutlineDurationMs = 1800;  // How long the outline scales up (ms)
  static const int _celebrationWordFadeDurationMs = 1600; // How long the old word fades out (ms)
  static const int _celebrationNewWordFadeInMs = 1000;    // How long the new word fades in (ms)
  static const int _celebrationGapMs = 800;                 // Gap between outline end and new word (ms)
  
  static const double _celebrationOutlineScaleMin = 1.0;  // Starting scale for outline
  static const double _celebrationOutlineScaleMax = 2.4;  // Ending scale for outline (1.0 + this multiplier)
  static const double _celebrationOutlineFloatDistance = 140.0; // Pixels to float upward (negative = up)
  static const double _celebrationOutlineOpacityMin = 0.3; // Minimum opacity at end of fade (0.0 = fully transparent, 1.0 = fully opaque)
  
  // FAILURE ANIMATION
  static const int _failureAnimationDurationMs = 1500;     // Total failure animation duration (ms)
  static const double _failureOpacityMin = 1.0;           // Minimum opacity (1.0 - fade amount)
  static const int _failureShakeDurationMs = 800;         // Shake animation duration (ms)
  static const double _failureShakeHz = 4.0;              // Shake frequency
  static const double _failureShakeOffset = 12.0;          // Shake horizontal offset (pixels)
  
  // WORD TRANSITION ANIMATION
  static const int _transitionDurationMs = 500;           // Normal word transition duration (ms)
  
  // TEXT STYLING
  static const double _wordFontSize = 80.0;               // Font size for main word
  static const double _outlineStrokeWidth = 1.0;          // Width of outline stroke (pixels)
  static const int _outlineStrokePasses = 1;             // Number of passes for smooth outline (more = smoother)
  
  // COLORS
  static const Color _normalWordColor = Colors.white;     // Normal word color
  static const Color _celebrationWordColor = Colors.white; // Word color during celebration
  static const Color _celebrationOutlineColor = Colors.cyan; // Outline color during celebration
  static const Color _failureWordColorStart = Color.fromARGB(255, 236, 129, 129); // Word color at start of failure
  static final Color _failureWordColorEnd = Colors.white; // Word color at end of failure
  static const Color _shadowColor = Colors.black45;        // Shadow color for text
  
  // EASING CURVES
  static const Curve _outlineScaleCurve = Curves.easeOutSine;     // Outline scale easing
  static const Curve _wordFadeCurve = Curves.easeOutCubic;          // Word fade easing
  static const Curve _transitionCurve = Curves.easeOutCubic;        // Transition easing
  
  // ============================================================================
  // STATE VARIABLES
  // ============================================================================
  
  late AnimationController _animationController;
  late AnimationController _transitionController;
  late AnimationController _outlineAnimationController;
  late AnimationController _wordFadeInController;
  bool _wasCelebrating = false;
  bool _wasFailing = false;
  
  // Single source of truth: the word currently being displayed
  String _displayWord = '';
  
  // Store the word being celebrated so it doesn't change mid-animation
  String? _celebratedWord;
  
  DateTime? _celebrationStartTime;

  @override
  void initState() {
    super.initState();
    _displayWord = widget.word;
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _failureAnimationDurationMs),
    );
    _transitionController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _transitionDurationMs),
    );
    _outlineAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _celebrationOutlineDurationMs),
    );
    _wordFadeInController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _celebrationNewWordFadeInMs),
    );
  }

  @override
  void didUpdateWidget(WordDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Detect word change and trigger transition
    // BUT: Don't transition if we're currently celebrating - wait until celebration completes
    if (widget.word != oldWidget.word && widget.word.isNotEmpty && !_wasCelebrating) {
      // Start transition immediately - old word stays visible until transition completes
      _transitionController.reset();
      _transitionController.forward().then((_) {
        if (mounted) {
          _displayWord = widget.word; // Update display word after transition
          setState(() {});
        }
      });
    }
    
    // Trigger success animation when state changes to celebrating
    if (widget.gameState == GameState.celebrating && 
        oldWidget.gameState != GameState.celebrating &&
        !_wasCelebrating) {
      _wasCelebrating = true;
      _wasFailing = false;
      // Capture the word being celebrated - use this throughout the animation
      _celebratedWord = oldWidget.word.isNotEmpty ? oldWidget.word : widget.word;
      _celebrationStartTime = DateTime.now();
      
      // Timeline:
      // 0-${_celebrationWordFadeDurationMs}ms: Old word fades out (handled in build method)
      // 0-${_celebrationOutlineDurationMs}ms: Outline scales up and floats away
      // ${_celebrationOutlineDurationMs}ms: Immediately fade in new word (no gap)
      // ${_celebrationOutlineDurationMs}-${_celebrationOutlineDurationMs + _celebrationNewWordFadeInMs}ms: New word fades in
      
      // Start outline scaling animation
      _outlineAnimationController.reset();
      _outlineAnimationController.forward();
      
      // After outline completes, fade in new word (with optional gap)
      final delayBeforeNewWord = _celebrationOutlineDurationMs + _celebrationGapMs;
      Future.delayed(Duration(milliseconds: delayBeforeNewWord), () {
        if (mounted) {
          _outlineAnimationController.reset();
          _wasCelebrating = false;
          _celebrationStartTime = null;
          
          // Check if word changed during celebration
          if (_celebratedWord != null && widget.word != _celebratedWord && widget.word.isNotEmpty) {
            // Fade in new word over 800ms
            _celebratedWord = null;
            _wordFadeInController.reset();
            _wordFadeInController.forward().then((_) {
              if (mounted) {
                _displayWord = widget.word; // Update display word after fade-in
                _animationController.reset();
                setState(() {});
              }
            });
          } else {
            // No word change
            _celebratedWord = null;
            _displayWord = widget.word;
            _animationController.reset();
            setState(() {});
          }
        }
      });
    }
    
    // Trigger failure animation when state changes to failing
    if (widget.gameState == GameState.failing && 
        oldWidget.gameState != GameState.failing &&
        !_wasFailing) {
      _wasFailing = true;
      _wasCelebrating = false;
      _animationController.reset();
      _animationController.forward();
      Future.delayed(Duration(milliseconds: _failureAnimationDurationMs), () {
        if (mounted) {
          _wasFailing = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transitionController.dispose();
    _outlineAnimationController.dispose();
    _wordFadeInController.dispose();
    super.dispose();
  }
  
  Widget _buildWordText(String text, Color color, List<Shadow> shadows) {
    return Text(
      text,
      style: TextStyle(
        fontSize: _wordFontSize,
        fontWeight: FontWeight.bold,
        color: color,
        shadows: shadows,
        letterSpacing: 0.0,
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
      ),
      textAlign: TextAlign.center,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }
  
  /// Builds a clean text outline (STROKE ONLY, no fill) for the scaling animation
  Widget _buildTextOutline(String text, double scale, double opacity, Color? dynamicColor) {
    // Create true stroke outline by using Paint with stroke style
    // Use LayoutBuilder to get proper size constraints
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a large but finite size that can accommodate scaled text
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 2000,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 1000,
        );
        return CustomPaint(
          size: size,
          painter: _TextOutlinePainter(
            text: text,
            scale: scale,
            opacity: opacity,
            color: dynamicColor ?? _celebrationOutlineColor,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFailing = widget.gameState == GameState.failing;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_animationController, _transitionController, _outlineAnimationController, _wordFadeInController]),
        builder: (context, child) {
          // Word transition - New word fades in gently while old word stays invisible
          // Check if we're transitioning (controller is animating and word changed)
          final isTransitioning = _transitionController.status == AnimationStatus.forward ||
                                  (_transitionController.value > 0 && _transitionController.value < 1);
          
          if (isTransitioning && widget.word != _displayWord) {
            final progress = _transitionController.value;
            
            // NEW WORD: Fades in gently from fully transparent
            final newWordOpacity = _transitionCurve.transform(progress);
            
            return Container(
              padding: const EdgeInsets.all(24),
              child: Opacity(
                opacity: newWordOpacity,
                child: _buildWordText(
                  widget.word, // Show new word, not display word
                  _normalWordColor,
                  [
                    Shadow(
                      blurRadius: 10.0,
                      color: _shadowColor,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Normal animations (success/failure)
          // Success: Gentle scale with soft color transition
          Color textColor = _normalWordColor;
          double opacity = 1.0;
          List<Shadow> shadows = [
            Shadow(
              blurRadius: 10.0,
              color: _shadowColor,
              offset: const Offset(2, 2),
            ),
          ];

          if (_wasCelebrating) {
            // Calculate elapsed time for old word fade
            final elapsed = _celebrationStartTime != null 
                ? DateTime.now().difference(_celebrationStartTime!).inMilliseconds
                : 0;
            
            final outlineProgress = _outlineAnimationController.value;
            final outlineEased = _outlineScaleCurve.transform(outlineProgress);
            
            // Old word: fade out over configured duration, then COMPLETELY invisible
            final wordFadeProgress = (elapsed / _celebrationWordFadeDurationMs).clamp(0.0, 1.0);
            final wordOpacity = (1.0 - wordFadeProgress).clamp(0.0, 1.0);
            final showOldWord = elapsed < _celebrationWordFadeDurationMs;
            
            // Outline: scale from min to max over configured duration, fade out
            final scaleRange = _celebrationOutlineScaleMax - _celebrationOutlineScaleMin;
            final outlineScale = _celebrationOutlineScaleMin + (outlineEased * scaleRange);
            // Fade from 1.0 to configured minimum opacity
            final opacityRange = 1.0 - _celebrationOutlineOpacityMin;
            final outlineOpacity = (1.0 - (outlineEased * opacityRange)).clamp(_celebrationOutlineOpacityMin, 1.0);
            
            // Float upward: ghost outline moves by configured distance
            final upwardOffset = _celebrationOutlineFloatDistance * outlineEased;
            
            final wordToShow = _celebratedWord ?? widget.word;
            
            return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Ghost outline: scales up and floats upward
                    // Use Positioned.fill to ensure proper sizing
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(0, upwardOffset),
                        child: Transform.scale(
                          scale: outlineScale,
                          child: Opacity(
                            opacity: outlineOpacity,
                            child: _buildTextOutline(wordToShow, outlineScale, outlineOpacity, widget.celebrationColor),
                          ),
                        ),
                      ),
                    ),
                    // Old word: fades out over 500ms, then NEVER shows again
                    if (showOldWord)
                      Opacity(
                        opacity: wordOpacity,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          child: _buildWordText(wordToShow, _celebrationWordColor, shadows),
                        ),
                      ),
                  ],
                );
          }
          
          // Check if we're in the fade-in phase after celebration
          if (_wordFadeInController.status == AnimationStatus.forward ||
              (_wordFadeInController.value > 0 && _wordFadeInController.value < 1)) {
            final fadeProgress = _wordFadeInController.value;
            final fadeOpacity = _wordFadeCurve.transform(fadeProgress);
            
            return Container(
              padding: const EdgeInsets.all(24),
              child: Opacity(
                opacity: fadeOpacity,
                child: _buildWordText(widget.word, _normalWordColor, shadows),
              ),
            );
          }
          
          // Failure: Subtle fade and desaturation
          if (_wasFailing) {
            final progress = _animationController.value;
            opacity = 1.0 - (progress * (1.0 - _failureOpacityMin)); // Fade to configured min opacity
            textColor = Color.lerp(_failureWordColorStart, _failureWordColorEnd, progress)!;
          }

          // Only apply base transform if not celebrating (celebrating has its own transforms)
          // And not transitioning (transition has its own rendering)
          if (!_wasCelebrating) {
            // Show the display word (single source of truth)
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: 1.0, // Always reset to 1.0 for next word
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: _buildWordText(_displayWord, textColor, shadows),
                ),
              ),
            );
          }
          // Celebrating case returns its own transform (already handled above)
          return const SizedBox.shrink(); // Should never reach here, but safety return
        },
      ),
    ).animate(
      target: isFailing && !_wasFailing ? 1 : 0,
    ).shake(
      duration: Duration(milliseconds: _failureShakeDurationMs),
      hz: _failureShakeHz,
      offset: Offset(_failureShakeOffset, 0),
    );
  }
}

/// Custom painter for text outline (STROKE ONLY, no fill)
class _TextOutlinePainter extends CustomPainter {
  final String text;
  final double scale;
  final double opacity;
  final Color color;
  
  _TextOutlinePainter({
    required this.text,
    required this.scale,
    required this.opacity,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    // Measure text size
    final textStyle = TextStyle(
      fontSize: _WordDisplayState._wordFontSize,
      fontWeight: FontWeight.bold,
      color: color, // Use dynamic color
    );
    
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final textWidth = textPainter.width;
    final textHeight = textPainter.height;
    
    final textOffset = Offset(
      centerX - textWidth / 2,
      centerY - textHeight / 2,
    );
    
    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.scale(scale);
    canvas.translate(-centerX, -centerY);
    
    // Create TRUE stroke-only outline
    // Draw text at perimeter offsets to create stroke effect
    final strokeRadius = _WordDisplayState._outlineStrokeWidth;
    final numPasses = _WordDisplayState._outlineStrokePasses;
    
    // Stroke color
    final strokeColor = color.withOpacity(opacity);
    
    for (var i = 0; i < numPasses; i++) {
      final angle = (i / numPasses) * 2 * pi;
      final offsetX = cos(angle) * strokeRadius;
      final offsetY = sin(angle) * strokeRadius;
      
      // Create stroke text painter with white color
      final strokeTextStyle = TextStyle(
        fontSize: _WordDisplayState._wordFontSize,
        fontWeight: FontWeight.bold,
        color: strokeColor,
      );
      
      final strokeTextPainter = TextPainter(
        text: TextSpan(text: text, style: strokeTextStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      strokeTextPainter.layout();
      
      strokeTextPainter.paint(canvas, textOffset + Offset(offsetX, offsetY));
    }
    
    canvas.restore();
  }
  
  @override
  bool shouldRepaint(_TextOutlinePainter oldDelegate) {
    return oldDelegate.scale != scale || 
           oldDelegate.opacity != opacity || 
           oldDelegate.text != text ||
           oldDelegate.color != color;
  }
}
