/// App settings model for storing user preferences and child personalization
class AppSettings {
  final int currentWeek; // Current week number (1-31)
  final bool autoAdvanceEnabled; // Whether to automatically advance weeks
  final int advanceDayOfWeek; // Day of week to advance (0=Sunday, 6=Saturday)
  final int wordsPerWeek; // Number of words per week
  final DateTime? lastAdvanceDate; // Last date the week was advanced
  final String childName; // Child's first name for personalization
  final String rugFontFamily; // Font family for rug text

  const AppSettings({
    this.currentWeek = 1,
    this.autoAdvanceEnabled = true,
    this.advanceDayOfWeek = 0, // Sunday by default
    this.wordsPerWeek = 2,
    this.lastAdvanceDate,
    this.childName = '',
    this.rugFontFamily = 'Quicksand',
  });

  AppSettings copyWith({
    int? currentWeek,
    bool? autoAdvanceEnabled,
    int? advanceDayOfWeek,
    int? wordsPerWeek,
    DateTime? lastAdvanceDate,
    String? childName,
    String? rugFontFamily,
  }) {
    return AppSettings(
      currentWeek: currentWeek ?? this.currentWeek,
      autoAdvanceEnabled: autoAdvanceEnabled ?? this.autoAdvanceEnabled,
      advanceDayOfWeek: advanceDayOfWeek ?? this.advanceDayOfWeek,
      wordsPerWeek: wordsPerWeek ?? this.wordsPerWeek,
      lastAdvanceDate: lastAdvanceDate ?? this.lastAdvanceDate,
      childName: childName ?? this.childName,
      rugFontFamily: rugFontFamily ?? this.rugFontFamily,
    );
  }

  /// Check if we should advance the week based on auto-advance settings
  bool shouldAdvanceWeek() {
    if (!autoAdvanceEnabled) return false;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // If we've never advanced, check if today is the advance day
    if (lastAdvanceDate == null) {
      return now.weekday == advanceDayOfWeek + 1; // DateTime.weekday is 1-7 (Mon-Sun)
    }
    
    final lastAdvance = DateTime(
      lastAdvanceDate!.year,
      lastAdvanceDate!.month,
      lastAdvanceDate!.day,
    );
    
    // Check if we've already advanced this week
    final daysSinceLastAdvance = today.difference(lastAdvance).inDays;
    if (daysSinceLastAdvance < 7) {
      return false; // Already advanced this week
    }
    
    // Check if today is the advance day
    return now.weekday == advanceDayOfWeek + 1;
  }

  /// Get the day name for the advance day
  String getAdvanceDayName() {
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return days[advanceDayOfWeek];
  }
  
  /// Check if child name is set
  bool get hasChildName => childName.isNotEmpty;
}
