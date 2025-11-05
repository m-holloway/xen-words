import 'package:flutter/material.dart';
import '../models/word_list.dart';

/// Widget for selecting the number of weeks to practice
class WeekSelector extends StatelessWidget {
  final int numWeeks;
  final Function(int) onWeeksChanged;
  final VoidCallback onStartGame;

  const WeekSelector({
    Key? key,
    required this.numWeeks,
    required this.onWeeksChanged,
    required this.onStartGame,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Select Number of Weeks',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle),
                iconSize: 40,
                color: Colors.blue,
                onPressed: numWeeks > 1 ? () => onWeeksChanged(numWeeks - 1) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$numWeeks',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                iconSize: 40,
                color: Colors.blue,
                onPressed: numWeeks < WordList.maxWeeks
                    ? () => onWeeksChanged(numWeeks + 1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${numWeeks * WordList.wordsPerWeek} words',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: onStartGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 4,
            ),
            child: const Text(
              'Start Game',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


