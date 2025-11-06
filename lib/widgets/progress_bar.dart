import 'package:flutter/material.dart';

/// Simple progress bar showing word progress
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
    
    final progress = (currentWordIndex + 1) / totalWords;
    
    return Container(
      width: 300,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

