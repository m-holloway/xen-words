import 'package:flutter/material.dart';
import '../models/learning_progress.dart';

/// Shows 3-5 words that need attention + recently mastered words
/// Clear action items: "Practice these" vs "Celebrate these"
/// Minimal, scannable, actionable
class ActionWordsWidget extends StatelessWidget {
  final LearningProgress progress;
  final Function(String word)? onWordTap;
  
  const ActionWordsWidget({
    Key? key,
    required this.progress,
    this.onWordTap,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final struggling = _getStrugglingWords();
    final recentlyMastered = _getRecentlyMastered();
    
    return Column(
      children: [
        // Struggle words (needs practice)
        if (struggling.isNotEmpty) ...[
          _buildSection(
            context: context,
            title: 'Practice These',
            subtitle: 'Words that need more work',
            icon: Icons.fitness_center,
            iconColor: Colors.orange,
            words: struggling,
            isStruggle: true,
          ),
          const SizedBox(height: 20),
        ],
        
        // Recently mastered (celebration)
        if (recentlyMastered.isNotEmpty)
          _buildSection(
            context: context,
            title: 'Recently Mastered! 🌟',
            subtitle: 'Great progress!',
            icon: Icons.emoji_events,
            iconColor: Colors.amber,
            words: recentlyMastered,
            isStruggle: false,
          ),
      ],
    );
  }
  
  Widget _buildSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<WordProgress> words,
    required bool isStruggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isStruggle ? Colors.orange.shade200 : Colors.green.shade200,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Words as chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: words.map((wordProgress) {
              return _buildWordChip(
                context,
                wordProgress,
                isStruggle,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWordChip(
    BuildContext context,
    WordProgress wordProgress,
    bool isStruggle,
  ) {
    final color = isStruggle ? Colors.orange : Colors.green;
    
    return InkWell(
      onTap: onWordTap != null ? () => onWordTap!(wordProgress.word) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade300, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              wordProgress.word,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color.shade900,
              ),
            ),
            const SizedBox(width: 8),
            if (isStruggle)
              Text(
                '${(wordProgress.successRate * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: color.shade700,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Icon(
                Icons.check_circle,
                size: 16,
                color: color.shade600,
              ),
          ],
        ),
      ),
    );
  }
  
  List<WordProgress> _getStrugglingWords() {
    return progress.wordProgress.values
        .where((w) => !w.isMastered && w.totalAttempts >= 2)
        .toList()
      ..sort((a, b) => a.successRate.compareTo(b.successRate))
      ..take(5).toList();
  }
  
  List<WordProgress> _getRecentlyMastered() {
    final mastered = progress.wordProgress.values
        .where((w) => w.isMastered && w.masteredDate != null)
        .toList()
      ..sort((a, b) => b.masteredDate!.compareTo(a.masteredDate!));
    
    // Show last 5 mastered words
    return mastered.take(5).toList();
  }
}

