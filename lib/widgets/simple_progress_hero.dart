import 'package:flutter/material.dart';
import '../models/learning_progress.dart';

/// Hero section showing THE most important metric at a glance
/// Large number + trend + one-sentence summary
/// Minimal cognitive load - tells the story in 3 seconds
class SimpleProgressHero extends StatelessWidget {
  final LearningProgress progress;
  final String childName;
  
  const SimpleProgressHero({
    Key? key,
    required this.progress,
    required this.childName,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final recentSession = progress.sessionHistory.isNotEmpty
        ? progress.sessionHistory.last
        : null;
    
    final todaySuccessRate = recentSession != null
        ? recentSession.successRate
        : progress.overallSuccessRate;
    
    final wordsMastered = progress.wordsMastered;
    final totalAttempted = progress.totalWordsAttempted;
    
    // Determine trend (comparing recent vs overall)
    final isImproving = recentSession != null &&
        recentSession.successRate > progress.overallSuccessRate;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.deepPurple,
            Colors.deepPurple.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The Big Number
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$wordsMastered',
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'words',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'mastered',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Trend indicator
              if (recentSession != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isImproving
                        ? Colors.green.shade400
                        : Colors.orange.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isImproving ? Icons.trending_up : Icons.trending_flat,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isImproving ? 'Improving!' : 'Steady',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Divider
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.1),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Summary sentence
          Text(
            _buildSummary(recentSession, totalAttempted, childName),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.4,
            ),
          ),
          
          // Success rate (secondary metric)
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      color: Colors.amber.shade300,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(todaySuccessRate * 100).toStringAsFixed(0)}% success rate',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _buildSummary(SessionHistory? recentSession, int totalAttempted, String name) {
    if (recentSession == null) {
      return '$name is ready to start learning!';
    }
    
    final wordsAttempted = recentSession.wordsAttempted;
    final wordsCorrect = recentSession.wordsCorrect;
    
    if (wordsCorrect == wordsAttempted) {
      return '$name got all $wordsAttempted words correct in the last session! 🎉';
    } else if (wordsCorrect >= wordsAttempted * 0.8) {
      return '$name did great! $wordsCorrect out of $wordsAttempted correct.';
    } else {
      return '$name practiced $wordsAttempted words. Keep it up!';
    }
  }
}

