import 'package:flutter/material.dart';
import '../models/word_list.dart';
import '../models/app_settings.dart';

/// Super simple kid-friendly widget for displaying and adjusting the current week
class WeekSelector extends StatefulWidget {
  final int currentWeek;
  final AppSettings settings;
  final Function(int) onWeekChanged;
  final VoidCallback onStartGame;
  final bool isStarting; // Whether game is currently starting

  const WeekSelector({
    Key? key,
    required this.currentWeek,
    required this.settings,
    required this.onWeekChanged,
    required this.onStartGame,
    this.isStarting = false,
  }) : super(key: key);

  @override
  State<WeekSelector> createState() => _WeekSelectorState();
}

class _WeekSelectorState extends State<WeekSelector> {
  late int _currentWeek;

  @override
  void initState() {
    super.initState();
    _currentWeek = widget.currentWeek;
  }

  @override
  void didUpdateWidget(WeekSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentWeek != _currentWeek) {
      _currentWeek = widget.currentWeek;
    }
  }

  void _handleWeekChange(int newWeek) {
    if (newWeek >= 1 && newWeek <= WordList.maxWeeks) {
      setState(() {
        _currentWeek = newWeek;
      });
      widget.onWeekChanged(newWeek);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wordsInWeek = _currentWeek * WordList.wordsPerWeek;
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Week Number Display - Large and clear
          Text(
            'Week $_currentWeek',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$wordsInWeek words',
            style: TextStyle(
              fontSize: 22,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 48),
          
          // Simple week adjustment buttons - large and intuitive
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous week button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _currentWeek > 1
                      ? () => _handleWeekChange(_currentWeek - 1)
                      : null,
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _currentWeek > 1 
                          ? Colors.blue.shade100 
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _currentWeek > 1 
                            ? Colors.blue 
                            : Colors.grey.shade400,
                        width: 4,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: 40,
                      color: _currentWeek > 1 
                          ? Colors.blue 
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 40),
              
              // Next week button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _currentWeek < WordList.maxWeeks
                      ? () => _handleWeekChange(_currentWeek + 1)
                      : null,
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _currentWeek < WordList.maxWeeks 
                          ? Colors.blue.shade100 
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _currentWeek < WordList.maxWeeks 
                            ? Colors.blue 
                            : Colors.grey.shade400,
                        width: 4,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 40,
                      color: _currentWeek < WordList.maxWeeks 
                          ? Colors.blue 
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 48),
          
          // Start Game Button - Large and prominent
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.isStarting ? null : widget.onStartGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isStarting 
                    ? Colors.grey 
                    : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: widget.isStarting ? 2 : 6,
                shadowColor: widget.isStarting 
                    ? Colors.grey.withOpacity(0.2)
                    : Colors.green.withOpacity(0.4),
              ),
              child: widget.isStarting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Start Game',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
