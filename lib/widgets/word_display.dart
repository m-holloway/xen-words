import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Widget for displaying the current word with animations
class WordDisplay extends StatelessWidget {
  final String word;
  final bool isShaking;
  final VoidCallback? onTap;

  const WordDisplay({
    Key? key,
    required this.word,
    this.isShaking = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Text(
          word,
          style: const TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Colors.black45,
                offset: Offset(2, 2),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ).animate(
      target: isShaking ? 1 : 0,
    ).shake(
      duration: const Duration(milliseconds: 500),
      hz: 8,
      offset: const Offset(10, 0),
    );
  }
}


