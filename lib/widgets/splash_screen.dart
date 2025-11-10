import 'package:flutter/material.dart';
import 'dart:async';
import 'splash_character_view.dart';

/// Splash screen shown while app initializes
/// Provides entertaining animation while speech recognizer loads
class SplashScreen extends StatefulWidget {
  final Future<void> initializationFuture;
  final Widget child;
  final Function()? onModelLoaded; // Called when 3D model is fully loaded

  const SplashScreen({
    Key? key,
    required this.initializationFuture,
    required this.child,
    this.onModelLoaded,
  }) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    
    // Create animation controller
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    // Fade animation for pulsing effect
    _fadeAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // Scale animation for breathing effect
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // Rotation animation for spinning letters
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: widget.initializationFuture,
      builder: (context, snapshot) {
        // Show splash screen while loading
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildSplashContent();
        }

        // Once loaded, show main app
        return widget.child;
      },
    );
  }

  Widget _buildSplashContent() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.black,
              const Color(0xFF1A0033),
              const Color(0xFF2D0047),
            ],
            stops: const [0.0, 0.33, 0.6, 1.0],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Detect landscape mode
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final availableHeight = constraints.maxHeight;
            
            // Responsive sizing based on orientation and available space
            final letterFontSize = isLandscape
                ? (availableHeight * 0.12).clamp(32.0, 48.0)
                : (availableHeight * 0.08).clamp(48.0, 64.0);
            
            final subtitleFontSize = isLandscape
                ? (availableHeight * 0.04).clamp(14.0, 18.0)
                : (availableHeight * 0.03).clamp(18.0, 24.0);
            
            final loadingFontSize = isLandscape
                ? (availableHeight * 0.035).clamp(12.0, 16.0)
                : (availableHeight * 0.025).clamp(14.0, 18.0);
            
            final characterSize = isLandscape
                ? (availableHeight * 0.35).clamp(120.0, 160.0)
                : (availableHeight * 0.25).clamp(150.0, 200.0);
            
            final spacingAfterTitle = isLandscape
                ? (availableHeight * 0.03).clamp(8.0, 16.0)
                : (availableHeight * 0.025).clamp(12.0, 20.0);
            
            final spacingAfterLogo = isLandscape
                ? (availableHeight * 0.05).clamp(16.0, 24.0)
                : (availableHeight * 0.05).clamp(24.0, 40.0);
            
            final spacingAfterCharacter = isLandscape
                ? (availableHeight * 0.04).clamp(12.0, 20.0)
                : (availableHeight * 0.04).clamp(20.0, 30.0);
            
            return Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated logo/title
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Spinning letters effect
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildAnimatedLetter('X', 0, letterFontSize),
                                      _buildAnimatedLetter('E', 0.2, letterFontSize),
                                      _buildAnimatedLetter('N', 0.4, letterFontSize),
                                      SizedBox(width: letterFontSize * 0.3),
                                      _buildAnimatedLetter('W', 0.6, letterFontSize),
                                      _buildAnimatedLetter('O', 0.8, letterFontSize),
                                      _buildAnimatedLetter('R', 1.0, letterFontSize),
                                      _buildAnimatedLetter('D', 1.2, letterFontSize),
                                      _buildAnimatedLetter('S', 1.4, letterFontSize),
                                    ],
                                  ),
                                ),
                                SizedBox(height: spacingAfterTitle),
                                Text(
                                  'Learning Sight Words',
                                  style: TextStyle(
                                    fontSize: subtitleFontSize,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: spacingAfterLogo),
                    
                    // 3D Character with continuous animation
                    SplashCharacterView(
                      size: characterSize,
                      onModelLoaded: widget.onModelLoaded,
                    ),
                    
                    SizedBox(height: spacingAfterCharacter),
                    
                    // Loading text (no spinner - character provides visual interest)
                    Text(
                      'Getting ready...',
                      style: TextStyle(
                        fontSize: loadingFontSize,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedLetter(String letter, double delay, double fontSize) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final rotation = (_rotationAnimation.value * 2 * 3.14159) + (delay * 2 * 3.14159);
        final offset = (rotation % (2 * 3.14159)) / (2 * 3.14159);
        final scale = 1.0 + (0.2 * (0.5 - (offset - 0.5).abs()));
        final opacity = 0.7 + (0.3 * (1.0 - (offset - 0.5).abs() * 2));
        
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Text(
              letter,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
                letterSpacing: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

