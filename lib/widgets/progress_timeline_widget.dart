import 'package:flutter/material.dart';
import '../models/learning_progress.dart';

/// Simple, intuitive timeline showing word attempts over time
/// Green dots = correct, Red dots = incorrect
/// Shows learning progression at a glance with minimal cognitive load
class ProgressTimelineWidget extends StatelessWidget {
  final LearningProgress progress;
  
  const ProgressTimelineWidget({
    Key? key,
    required this.progress,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Get attempts from session history
    final sessions = progress.sessionHistory;
    
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Sort sessions by date
    final sortedSessions = List<SessionHistory>.from(sessions)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.deepPurple.shade50,
            Colors.blue.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100, width: 2),
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
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.timeline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Learning Journey',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Timeline visualization
          SizedBox(
            height: 100,
            child: _buildTimeline(sortedSessions),
          ),
          
          const SizedBox(height: 16),
          
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(Colors.green, 'Correct'),
              const SizedBox(width: 24),
              _buildLegendItem(Colors.red, 'Needs Practice'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTimeline(List<SessionHistory> sessions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sessionWidth = width / sessions.length;
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: sessions.map((session) {
            return SizedBox(
              width: sessionWidth,
              child: _buildSessionBar(session),
            );
          }).toList(),
        );
      },
    );
  }
  
  Widget _buildSessionBar(SessionHistory session) {
    final correct = session.wordsCorrect;
    final incorrect = session.wordsAttempted - session.wordsCorrect;
    final total = session.wordsAttempted;
    
    if (total == 0) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Correct bar (green)
          if (correct > 0)
            Expanded(
              flex: correct,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade500,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ),
            ),
          // Incorrect bar (red)
          if (incorrect > 0)
            Expanded(
              flex: incorrect,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: incorrect == total
                      ? const BorderRadius.vertical(top: Radius.circular(4))
                      : BorderRadius.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

