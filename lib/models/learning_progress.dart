/// Learning progress model for tracking child's sight word mastery
class LearningProgress {
  final Map<String, WordProgress> wordProgress; // word -> progress
  final List<SessionHistory> sessionHistory;
  final DateTime firstSessionDate;
  final DateTime lastSessionDate;
  
  const LearningProgress({
    this.wordProgress = const {},
    this.sessionHistory = const [],
    required this.firstSessionDate,
    required this.lastSessionDate,
  });
  
  /// Create from JSON (for SharedPreferences storage)
  factory LearningProgress.fromJson(Map<String, dynamic> json) {
    return LearningProgress(
      wordProgress: (json['wordProgress'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, WordProgress.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      sessionHistory: (json['sessionHistory'] as List?)
          ?.map((e) => SessionHistory.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      firstSessionDate: DateTime.parse(json['firstSessionDate'] as String),
      lastSessionDate: DateTime.parse(json['lastSessionDate'] as String),
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'wordProgress': wordProgress.map((k, v) => MapEntry(k, v.toJson())),
      'sessionHistory': sessionHistory.map((s) => s.toJson()).toList(),
      'firstSessionDate': firstSessionDate.toIso8601String(),
      'lastSessionDate': lastSessionDate.toIso8601String(),
    };
  }
  
  /// Get words mastered count
  int get wordsMastered => wordProgress.values
      .where((w) => w.isMastered)
      .length;
  
  /// Get total sessions count
  int get totalSessions => sessionHistory.length;
  
  /// Get total words attempted
  int get totalWordsAttempted => wordProgress.length;
  
  /// Get success rate
  double get overallSuccessRate {
    if (wordProgress.isEmpty) return 0.0;
    final totalAttempts = wordProgress.values
        .fold<int>(0, (sum, w) => sum + w.totalAttempts);
    final correctAttempts = wordProgress.values
        .fold<int>(0, (sum, w) => sum + w.correctAttempts);
    return totalAttempts > 0 ? correctAttempts / totalAttempts : 0.0;
  }
  
  /// Get days since first session
  int get daysSinceFirstSession {
    return DateTime.now().difference(firstSessionDate).inDays;
  }
  
  /// Copy with updated values
  LearningProgress copyWith({
    Map<String, WordProgress>? wordProgress,
    List<SessionHistory>? sessionHistory,
    DateTime? firstSessionDate,
    DateTime? lastSessionDate,
  }) {
    return LearningProgress(
      wordProgress: wordProgress ?? this.wordProgress,
      sessionHistory: sessionHistory ?? this.sessionHistory,
      firstSessionDate: firstSessionDate ?? this.firstSessionDate,
      lastSessionDate: lastSessionDate ?? this.lastSessionDate,
    );
  }
  
  /// Record a word attempt
  LearningProgress recordAttempt({
    required String word,
    required bool correct,
  }) {
    final now = DateTime.now();
    final existing = wordProgress[word] ?? WordProgress(word: word);
    final updated = existing.recordAttempt(correct: correct);
    
    return copyWith(
      wordProgress: {...wordProgress, word: updated},
      lastSessionDate: now,
    );
  }
  
  /// Record a completed session
  LearningProgress recordSession({
    required int weekNumber,
    required int wordsAttempted,
    required int wordsCorrect,
    required Duration sessionDuration,
  }) {
    final now = DateTime.now();
    final session = SessionHistory(
      timestamp: now,
      weekNumber: weekNumber,
      wordsAttempted: wordsAttempted,
      wordsCorrect: wordsCorrect,
      sessionDuration: sessionDuration,
    );
    
    return copyWith(
      sessionHistory: [...sessionHistory, session],
      lastSessionDate: now,
    );
  }
}

/// Progress for a single word
class WordProgress {
  final String word;
  final int totalAttempts;
  final int correctAttempts;
  final DateTime? firstAttemptDate;
  final DateTime? lastAttemptDate;
  final DateTime? masteredDate;
  
  const WordProgress({
    required this.word,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    this.firstAttemptDate,
    this.lastAttemptDate,
    this.masteredDate,
  });
  
  factory WordProgress.fromJson(Map<String, dynamic> json) {
    return WordProgress(
      word: json['word'] as String,
      totalAttempts: json['totalAttempts'] as int? ?? 0,
      correctAttempts: json['correctAttempts'] as int? ?? 0,
      firstAttemptDate: json['firstAttemptDate'] != null 
          ? DateTime.parse(json['firstAttemptDate'] as String) 
          : null,
      lastAttemptDate: json['lastAttemptDate'] != null
          ? DateTime.parse(json['lastAttemptDate'] as String)
          : null,
      masteredDate: json['masteredDate'] != null
          ? DateTime.parse(json['masteredDate'] as String)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'totalAttempts': totalAttempts,
      'correctAttempts': correctAttempts,
      'firstAttemptDate': firstAttemptDate?.toIso8601String(),
      'lastAttemptDate': lastAttemptDate?.toIso8601String(),
      'masteredDate': masteredDate?.toIso8601String(),
    };
  }
  
  /// Success rate for this word
  double get successRate {
    return totalAttempts > 0 ? correctAttempts / totalAttempts : 0.0;
  }
  
  /// Consider mastered after 3 correct attempts
  bool get isMastered => correctAttempts >= 3;
  
  /// Record an attempt
  WordProgress recordAttempt({required bool correct}) {
    final now = DateTime.now();
    final newCorrect = correctAttempts + (correct ? 1 : 0);
    final wasMastered = masteredDate != null;
    final nowMastered = newCorrect >= 3;
    
    return WordProgress(
      word: word,
      totalAttempts: totalAttempts + 1,
      correctAttempts: newCorrect,
      firstAttemptDate: firstAttemptDate ?? now,
      lastAttemptDate: now,
      masteredDate: (!wasMastered && nowMastered) ? now : masteredDate,
    );
  }
}

/// History of a single session
class SessionHistory {
  final DateTime timestamp;
  final int weekNumber;
  final int wordsAttempted;
  final int wordsCorrect;
  final Duration sessionDuration;
  
  const SessionHistory({
    required this.timestamp,
    required this.weekNumber,
    required this.wordsAttempted,
    required this.wordsCorrect,
    required this.sessionDuration,
  });
  
  factory SessionHistory.fromJson(Map<String, dynamic> json) {
    return SessionHistory(
      timestamp: DateTime.parse(json['timestamp'] as String),
      weekNumber: json['weekNumber'] as int,
      wordsAttempted: json['wordsAttempted'] as int,
      wordsCorrect: json['wordsCorrect'] as int,
      sessionDuration: Duration(seconds: json['sessionDurationSeconds'] as int),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'weekNumber': weekNumber,
      'wordsAttempted': wordsAttempted,
      'wordsCorrect': wordsCorrect,
      'sessionDurationSeconds': sessionDuration.inSeconds,
    };
  }
  
  /// Success rate for this session
  double get successRate {
    return wordsAttempted > 0 ? wordsCorrect / wordsAttempted : 0.0;
  }
}

