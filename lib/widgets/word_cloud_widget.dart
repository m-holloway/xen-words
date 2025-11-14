import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/learning_progress.dart';

/// Interactive word cloud visualization showing mastery levels
/// 
/// Color coding:
/// - Green: Mastered (3+ correct attempts, high success rate)
/// - Yellow/Orange: Learning (attempted, moderate success)
/// - Red: Struggling (attempted, low success rate)
/// - Gray: Not attempted yet
/// 
/// Size based on performance percentile across all attempted words
class WordCloudWidget extends StatelessWidget {
  final LearningProgress progress;
  final List<String> vocabulary; // All words from current week(s)
  final Function(String word)? onWordTap;
  
  const WordCloudWidget({
    Key? key,
    required this.progress,
    required this.vocabulary,
    this.onWordTap,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final wordStats = _calculateWordStats();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(
                'Word Mastery Cloud',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildLegend(context),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: wordStats.map((stat) => _buildWordChip(context, stat)).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem('Mastered', Colors.green.shade600),
        _buildLegendItem('Learning', Colors.orange.shade600),
        _buildLegendItem('Struggling', Colors.red.shade600),
        _buildLegendItem('Not Tried', Colors.grey.shade400),
      ],
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
  
  Widget _buildWordChip(BuildContext context, _WordStat stat) {
    return GestureDetector(
      onTap: onWordTap != null ? () => onWordTap!(stat.word) : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 8 + (stat.sizeFactor * 8),
          vertical: 4 + (stat.sizeFactor * 4),
        ),
        decoration: BoxDecoration(
          color: stat.color.withOpacity(0.15),
          border: Border.all(
            color: stat.color,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          stat.word,
          style: TextStyle(
            fontSize: 12 + (stat.sizeFactor * 8),
            fontWeight: stat.isMastered ? FontWeight.bold : FontWeight.normal,
            color: stat.color,
          ),
        ),
      ),
    );
  }
  
  List<_WordStat> _calculateWordStats() {
    final stats = <_WordStat>[];
    
    // Calculate percentiles for sizing
    final attemptedWords = vocabulary
        .where((word) => progress.wordProgress.containsKey(word.toLowerCase()))
        .toList();
    
    final successRates = attemptedWords
        .map((word) => progress.wordProgress[word.toLowerCase()]?.successRate ?? 0.0)
        .toList()
      ..sort();
    
    for (final word in vocabulary) {
      final wordKey = word.toLowerCase();
      final wordProgress = progress.wordProgress[wordKey];
      
      if (wordProgress == null) {
        // Not attempted - gray
        stats.add(_WordStat(
          word: word,
          color: Colors.grey.shade400,
          sizeFactor: 0.0,
          isMastered: false,
          successRate: 0.0,
          attempts: 0,
        ));
      } else {
        // Calculate percentile for sizing
        final percentile = successRates.isEmpty
            ? 0.5
            : successRates.where((r) => r <= wordProgress.successRate).length / successRates.length;
        
        // Determine color based on mastery level
        final Color color;
        final bool isMastered = wordProgress.isMastered;
        
        if (isMastered && wordProgress.successRate >= 0.9) {
          // Mastered - Green
          color = Colors.green.shade600;
        } else if (wordProgress.successRate >= 0.7) {
          // Learning well - Light green
          color = Colors.green.shade400;
        } else if (wordProgress.successRate >= 0.5) {
          // Learning with struggles - Orange
          color = Colors.orange.shade600;
        } else if (wordProgress.successRate >= 0.3) {
          // Struggling - Orange-red
          color = Colors.deepOrange.shade600;
        } else {
          // Really struggling - Red
          color = Colors.red.shade600;
        }
        
        stats.add(_WordStat(
          word: word,
          color: color,
          sizeFactor: percentile,
          isMastered: isMastered,
          successRate: wordProgress.successRate,
          attempts: wordProgress.totalAttempts,
        ));
      }
    }
    
    // Shuffle for visual interest (but keep deterministic with word as seed)
    stats.shuffle(math.Random(vocabulary.join().hashCode));
    
    return stats;
  }
}

class _WordStat {
  final String word;
  final Color color;
  final double sizeFactor; // 0.0 to 1.0, based on percentile
  final bool isMastered;
  final double successRate;
  final int attempts;
  
  _WordStat({
    required this.word,
    required this.color,
    required this.sizeFactor,
    required this.isMastered,
    required this.successRate,
    required this.attempts,
  });
}

