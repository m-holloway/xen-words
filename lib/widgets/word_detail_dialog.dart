import 'package:flutter/material.dart';
import '../models/learning_progress.dart';

/// Detailed view of a single word's progress
class WordDetailDialog extends StatelessWidget {
  final String word;
  final WordProgress? progress;
  
  const WordDetailDialog({
    Key? key,
    required this.word,
    this.progress,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (progress == null) {
      return AlertDialog(
        title: Text(
          word,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Not attempted yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              word,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          _buildMasteryBadge(progress!),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSuccessRateCard(context, progress!),
            const SizedBox(height: 16),
            _buildAttemptsCard(context, progress!),
            const SizedBox(height: 16),
            _buildTimelineCard(context, progress!),
            if (!progress!.isMastered) ...[
              const SizedBox(height: 16),
              _buildEncouragementCard(context, progress!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
  
  Widget _buildMasteryBadge(WordProgress progress) {
    if (progress.isMastered) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade600, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.green.shade600, size: 16),
            const SizedBox(width: 4),
            Text(
              'Mastered',
              style: TextStyle(
                color: Colors.green.shade600,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade600, width: 2),
        ),
        child: Text(
          'Learning',
          style: TextStyle(
            color: Colors.orange.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }
  }
  
  Widget _buildSuccessRateCard(BuildContext context, WordProgress progress) {
    final successRate = progress.successRate * 100;
    final color = successRate >= 75
        ? Colors.green
        : successRate >= 50
            ? Colors.orange
            : Colors.red;
    
    return Card(
      color: color.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: color.shade700),
                const SizedBox(width: 8),
                Text(
                  'Success Rate',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress.successRate,
                    minHeight: 20,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color.shade600),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${successRate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color.shade900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAttemptsCard(BuildContext context, WordProgress progress) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatColumn(
                icon: Icons.check_circle,
                label: 'Correct',
                value: progress.correctAttempts.toString(),
                color: Colors.green.shade600,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.shade300,
            ),
            Expanded(
              child: _buildStatColumn(
                icon: Icons.cancel,
                label: 'Incorrect',
                value: (progress.totalAttempts - progress.correctAttempts).toString(),
                color: Colors.red.shade600,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.shade300,
            ),
            Expanded(
              child: _buildStatColumn(
                icon: Icons.replay,
                label: 'Total',
                value: progress.totalAttempts.toString(),
                color: Colors.blue.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatColumn({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildTimelineCard(BuildContext context, WordProgress progress) {
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: Colors.deepPurple.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Timeline',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (progress.firstAttemptDate != null)
              _buildTimelineItem(
                icon: Icons.play_circle_outline,
                label: 'First Attempt',
                date: _formatDate(progress.firstAttemptDate!),
                time: _formatTime(progress.firstAttemptDate!),
              ),
            if (progress.masteredDate != null) ...[
              const SizedBox(height: 8),
              _buildTimelineItem(
                icon: Icons.star,
                label: 'Mastered',
                date: _formatDate(progress.masteredDate!),
                time: _formatTime(progress.masteredDate!),
                color: Colors.green.shade600,
              ),
            ],
            if (progress.lastAttemptDate != null) ...[
              const SizedBox(height: 8),
              _buildTimelineItem(
                icon: Icons.access_time,
                label: 'Last Attempt',
                date: _formatDate(progress.lastAttemptDate!),
                time: _formatTime(progress.lastAttemptDate!),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimelineItem({
    required IconData icon,
    required String label,
    required String date,
    required String time,
    Color? color,
  }) {
    final itemColor = color ?? Colors.grey.shade700;
    return Row(
      children: [
        Icon(icon, color: itemColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                '$date at $time',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: itemColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildEncouragementCard(BuildContext context, WordProgress progress) {
    final attemptsToMastery = 3 - progress.correctAttempts;
    final message = attemptsToMastery == 1
        ? 'Just 1 more correct attempt to master this word! 🌟'
        : '$attemptsToMastery more correct attempts to master this word! 💪';
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.blue.shade600, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
  
  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

