import 'package:flutter/material.dart';
import 'dart:async';

/// Splash screen shown while app initializes
/// Provides entertaining animation while speech recognizer loads
class SplashScreen extends StatefulWidget {
  final Future<void> initializationFuture;
  final Widget child;

  const SplashScreen({
    Key? key,
    required this.initializationFuture,
    required this.child,
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                        children: [
                          // Spinning letters effect
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildAnimatedLetter('X', 0),
                              _buildAnimatedLetter('E', 0.2),
                              _buildAnimatedLetter('N', 0.4),
                              const SizedBox(width: 20),
                              _buildAnimatedLetter('W', 0.6),
                              _buildAnimatedLetter('O', 0.8),
                              _buildAnimatedLetter('R', 1.0),
                              _buildAnimatedLetter('D', 1.2),
                              _buildAnimatedLetter('S', 1.4),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Learning Sight Words',
                            style: TextStyle(
                              fontSize: 24,
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
              const SizedBox(height: 60),
              
              // Loading indicator with text
              Column(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.blue.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Getting ready...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedLetter(String letter, double delay) {
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
              style: const TextStyle(
                fontSize: 64,
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

