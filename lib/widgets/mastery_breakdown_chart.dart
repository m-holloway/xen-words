import 'package:flutter/material.dart';
import '../models/learning_progress.dart';

/// Chart showing distribution of words across mastery levels
class MasteryBreakdownChart extends StatelessWidget {
  final LearningProgress progress;
  final List<String> vocabulary;
  
  const MasteryBreakdownChart({
    Key? key,
    required this.progress,
    required this.vocabulary,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final breakdown = _calculateBreakdown();
    final total = vocabulary.length;
    
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
              const Icon(Icons.bar_chart, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(
                'Mastery Breakdown',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProgressBar(
            context: context,
            mastered: breakdown.mastered,
            learning: breakdown.learning,
            struggling: breakdown.struggling,
            notAttempted: breakdown.notAttempted,
            total: total,
          ),
          const SizedBox(height: 16),
          _buildLegendGrid(breakdown, total),
        ],
      ),
    );
  }
  
  Widget _buildProgressBar({
    required BuildContext context,
    required int mastered,
    required int learning,
    required int struggling,
    required int notAttempted,
    required int total,
  }) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                if (mastered > 0)
                  Expanded(
                    flex: mastered,
                    child: Container(
                      color: Colors.green.shade600,
                      alignment: Alignment.center,
                      child: mastered > 0
                          ? Text(
                              mastered.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                if (learning > 0)
                  Expanded(
                    flex: learning,
                    child: Container(
                      color: Colors.orange.shade600,
                      alignment: Alignment.center,
                      child: learning > 0
                          ? Text(
                              learning.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                if (struggling > 0)
                  Expanded(
                    flex: struggling,
                    child: Container(
                      color: Colors.red.shade600,
                      alignment: Alignment.center,
                      child: struggling > 0
                          ? Text(
                              struggling.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                if (notAttempted > 0)
                  Expanded(
                    flex: notAttempted,
                    child: Container(
                      color: Colors.grey.shade300,
                      alignment: Alignment.center,
                      child: notAttempted > 0
                          ? Text(
                              notAttempted.toString(),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildLegendGrid(_MasteryBreakdown breakdown, int total) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _buildLegendItem(
          icon: Icons.star,
          label: 'Mastered',
          count: breakdown.mastered,
          total: total,
          color: Colors.green.shade600,
        ),
        _buildLegendItem(
          icon: Icons.trending_up,
          label: 'Learning',
          count: breakdown.learning,
          total: total,
          color: Colors.orange.shade600,
        ),
        _buildLegendItem(
          icon: Icons.warning,
          label: 'Struggling',
          count: breakdown.struggling,
          total: total,
          color: Colors.red.shade600,
        ),
        _buildLegendItem(
          icon: Icons.help_outline,
          label: 'Not Tried',
          count: breakdown.notAttempted,
          total: total,
          color: Colors.grey.shade600,
        ),
      ],
    );
  }
  
  Widget _buildLegendItem({
    required IconData icon,
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final percentage = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$count ($percentage%)',
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  _MasteryBreakdown _calculateBreakdown() {
    int mastered = 0;
    int learning = 0;
    int struggling = 0;
    int notAttempted = 0;
    
    for (final word in vocabulary) {
      final wordKey = word.toLowerCase();
      final wordProgress = progress.wordProgress[wordKey];
      
      if (wordProgress == null) {
        notAttempted++;
      } else if (wordProgress.isMastered && wordProgress.successRate >= 0.9) {
        mastered++;
      } else if (wordProgress.successRate >= 0.5) {
        learning++;
      } else {
        struggling++;
      }
    }
    
    return _MasteryBreakdown(
      mastered: mastered,
      learning: learning,
      struggling: struggling,
      notAttempted: notAttempted,
    );
  }
}

class _MasteryBreakdown {
  final int mastered;
  final int learning;
  final int struggling;
  final int notAttempted;
  
  _MasteryBreakdown({
    required this.mastered,
    required this.learning,
    required this.struggling,
    required this.notAttempted,
  });
}

