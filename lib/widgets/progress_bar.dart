import 'package:flutter/material.dart';

/// Progress bar showing word progress with 10 glowy blue dots
class WordProgressBar extends StatelessWidget {
  final int currentWordIndex;
  final int totalWords;

  const WordProgressBar({
    Key? key,
    required this.currentWordIndex,
    required this.totalWords,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (totalWords == 0) return const SizedBox.shrink();
    
    // Calculate how many dots should be filled
    // Map progress (0.0 to 1.0) to number of filled dots (0 to 10)
    final progress = (currentWordIndex + 1) / totalWords;
    final filledDots = (progress * 10).floor().clamp(0, 10);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(10, (index) {
        final isFilled = index < filledDots;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _GlowDot(isFilled: isFilled),
        );
      }),
    );
  }
}

/// Individual dot with glow effect
class _GlowDot extends StatelessWidget {
  final bool isFilled;

  const _GlowDot({
    Key? key,
    required this.isFilled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFilled ? Colors.blue.shade400 : Colors.white.withOpacity(0.2),
        boxShadow: isFilled
            ? [
                // Outer glow
                BoxShadow(
                  color: Colors.blue.withOpacity(0.6),
                  blurRadius: 12,
                  spreadRadius: 8,
                ),
                // Inner glow
                BoxShadow(
                  color: Colors.blue.shade300.withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
