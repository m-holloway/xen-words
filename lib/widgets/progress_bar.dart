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
    
    // Calculate how many dots should be filled based on COMPLETED words
    // currentWordIndex is the word currently being shown (0-based)
    // So if we're on word 0, no words are completed yet (0 dots)
    // If we're on word 1, one word is completed (1 dot), etc.
    final completedWords = currentWordIndex; // Words completed = current index
    final progress = completedWords / totalWords;
    final filledDots = (progress * 10).floor().clamp(0, 10);
    
    // Wrap with enhanced visual treatment for better visibility on character background
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        // Semi-transparent background
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        // Subtle glow
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
        // Subtle border
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(10, (index) {
          final isFilled = index < filledDots;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _GlowDot(isFilled: isFilled),
          );
        }),
      ),
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
