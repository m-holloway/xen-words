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
    
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        // Detect landscape mode (width > height) or constrained height
        final isLandscape = outerConstraints.maxWidth > outerConstraints.maxHeight;
        final availableHeight = outerConstraints.maxHeight;
        
        // Responsive padding based on available space
        final containerPadding = isLandscape 
            ? EdgeInsets.symmetric(horizontal: 32, vertical: (availableHeight * 0.05).clamp(12.0, 24.0))
            : const EdgeInsets.all(32);
        
        return Container(
          padding: containerPadding,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive font sizes based on container width and height
              final weekFontSize = isLandscape
                  ? (constraints.maxWidth * 0.12).clamp(36.0, 48.0)
                  : (constraints.maxWidth * 0.16).clamp(48.0, 64.0);
              final wordsFontSize = isLandscape
                  ? (constraints.maxWidth * 0.04).clamp(14.0, 18.0)
                  : (constraints.maxWidth * 0.055).clamp(18.0, 22.0);
              
              // Responsive spacing based on available height
              final spacingBetweenElements = isLandscape
                  ? (availableHeight * 0.04).clamp(8.0, 16.0)
                  : 48.0;
              final spacingAfterWords = isLandscape
                  ? (availableHeight * 0.02).clamp(4.0, 12.0)
                  : 12.0;
              
              // Responsive button sizes
              final buttonSize = isLandscape
                  ? (availableHeight * 0.2).clamp(50.0, 70.0)
                  : 80.0;
              final buttonIconSize = buttonSize * 0.5;
              
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Week Number Display - Large and clear
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Week $_currentWeek',
                        style: TextStyle(
                          fontSize: weekFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    SizedBox(height: spacingAfterWords),
                    Text(
                      '$wordsInWeek words',
                      style: TextStyle(
                        fontSize: wordsFontSize,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: spacingBetweenElements),
                    
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
                              width: buttonSize,
                              height: buttonSize,
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
                                size: buttonIconSize,
                                color: _currentWeek > 1 
                                    ? Colors.blue 
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        
                        SizedBox(width: isLandscape ? 24.0 : 40.0),
                        
                        // Next week button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _currentWeek < WordList.maxWeeks
                                ? () => _handleWeekChange(_currentWeek + 1)
                                : null,
                            borderRadius: BorderRadius.circular(50),
                            child: Container(
                              width: buttonSize,
                              height: buttonSize,
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
                                size: buttonIconSize,
                                color: _currentWeek < WordList.maxWeeks 
                                    ? Colors.blue 
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: spacingBetweenElements),
                    
                    // Start Game Button - Large and prominent
                    LayoutBuilder(
                      builder: (context, innerConstraints) {
                        // Responsive font size based on container width and landscape mode
                        final buttonFontSize = isLandscape
                            ? (innerConstraints.maxWidth * 0.065).clamp(20.0, 28.0)
                            : (innerConstraints.maxWidth * 0.085).clamp(24.0, 32.0);
                        final verticalPadding = isLandscape
                            ? (availableHeight * 0.04).clamp(12.0, 18.0)
                            : (innerConstraints.maxWidth * 0.06).clamp(16.0, 24.0);
                        
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: widget.isStarting ? null : widget.onStartGame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isStarting 
                                  ? Colors.grey 
                                  : Colors.green,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: verticalPadding),
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
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Start Game',
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.visible,
                                      style: TextStyle(
                                        fontSize: buttonFontSize,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
