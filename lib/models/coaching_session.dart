/// Coaching session tracking and metrics
library;

import 'package:flutter/foundation.dart';

/// A coaching session where parent and child read together
class CoachingSession {
  final String id;
  final String profileId;
  final String storyChapterId;
  final String? epicArcId;
  final DateTime startTime;
  final DateTime? endTime;
  final List<WordAttempt> wordAttempts;
  final List<ChoiceMade> choicesMade;
  final SessionMetrics? metrics;
  
  const CoachingSession({
    required this.id,
    required this.profileId,
    required this.storyChapterId,
    this.epicArcId,
    required this.startTime,
    this.endTime,
    this.wordAttempts = const [],
    this.choicesMade = const [],
    this.metrics,
  });
  
  factory CoachingSession.fromJson(Map<String, dynamic> json) {
    return CoachingSession(
      id: json['id'] ?? '',
      profileId: json['profile_id'] ?? '',
      storyChapterId: json['story_chapter_id'] ?? '',
      epicArcId: json['epic_arc_id'],
      startTime: DateTime.parse(json['start_time'] ?? DateTime.now().toIso8601String()),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      wordAttempts: (json['word_attempts'] as List<dynamic>?)
          ?.map((e) => WordAttempt.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      choicesMade: (json['choices_made'] as List<dynamic>?)
          ?.map((e) => ChoiceMade.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      metrics: json['metrics'] != null
          ? SessionMetrics.fromJson(json['metrics'] as Map<String, dynamic>)
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'story_chapter_id': storyChapterId,
      'epic_arc_id': epicArcId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'word_attempts': wordAttempts.map((w) => w.toJson()).toList(),
      'choices_made': choicesMade.map((c) => c.toJson()).toList(),
      'metrics': metrics?.toJson(),
    };
  }
  
  CoachingSession copyWith({
    DateTime? endTime,
    List<WordAttempt>? wordAttempts,
    List<ChoiceMade>? choicesMade,
    SessionMetrics? metrics,
  }) {
    return CoachingSession(
      id: id,
      profileId: profileId,
      storyChapterId: storyChapterId,
      epicArcId: epicArcId,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      wordAttempts: wordAttempts ?? this.wordAttempts,
      choicesMade: choicesMade ?? this.choicesMade,
      metrics: metrics ?? this.metrics,
    );
  }
  
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
  
  bool get isComplete => endTime != null;
}

/// A word attempt during the session
class WordAttempt {
  final String word;
  final bool correct;
  final DateTime timestamp;
  final double? confidence;  // 0.0-1.0 if speech recognition provides it
  
  const WordAttempt({
    required this.word,
    required this.correct,
    required this.timestamp,
    this.confidence,
  });
  
  factory WordAttempt.fromJson(Map<String, dynamic> json) {
    return WordAttempt(
      word: json['word'] ?? '',
      correct: json['correct'] ?? false,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      confidence: json['confidence']?.toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'correct': correct,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
    };
  }
}

/// A choice made by the child during the story
class ChoiceMade {
  final String choicePointId;
  final String choiceId;
  final DateTime timestamp;
  
  const ChoiceMade({
    required this.choicePointId,
    required this.choiceId,
    required this.timestamp,
  });
  
  factory ChoiceMade.fromJson(Map<String, dynamic> json) {
    return ChoiceMade(
      choicePointId: json['choice_point_id'] ?? '',
      choiceId: json['choice_id'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'choice_point_id': choicePointId,
      'choice_id': choiceId,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Metrics for a coaching session
class SessionMetrics {
  final int wordsAttempted;
  final int wordsCorrect;
  final int celebrationCount;
  final Duration duration;
  final Map<String, double> wordConfidence;  // word -> avg confidence
  
  const SessionMetrics({
    required this.wordsAttempted,
    required this.wordsCorrect,
    this.celebrationCount = 0,
    required this.duration,
    this.wordConfidence = const {},
  });
  
  factory SessionMetrics.fromJson(Map<String, dynamic> json) {
    return SessionMetrics(
      wordsAttempted: json['words_attempted'] ?? 0,
      wordsCorrect: json['words_correct'] ?? 0,
      celebrationCount: json['celebration_count'] ?? 0,
      duration: Duration(seconds: json['duration_seconds'] ?? 0),
      wordConfidence: (json['word_confidence'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'words_attempted': wordsAttempted,
      'words_correct': wordsCorrect,
      'celebration_count': celebrationCount,
      'duration_seconds': duration.inSeconds,
      'word_confidence': wordConfidence,
    };
  }
  
  double get successRate => wordsAttempted > 0 ? wordsCorrect / wordsAttempted : 0.0;
}

/// Journey board position tracking for autonomous practice
class JourneyProgress {
  final String profileId;
  final String epicArcId;
  final int currentPosition;
  final int nextMilestonePosition;
  final int gamesUntilMilestone;
  final List<JourneyEvent> events;
  final DateTime lastUpdated;
  
  const JourneyProgress({
    required this.profileId,
    required this.epicArcId,
    required this.currentPosition,
    required this.nextMilestonePosition,
    required this.gamesUntilMilestone,
    this.events = const [],
    required this.lastUpdated,
  });
  
  factory JourneyProgress.fromJson(Map<String, dynamic> json) {
    return JourneyProgress(
      profileId: json['profile_id'] ?? '',
      epicArcId: json['epic_arc_id'] ?? '',
      currentPosition: json['current_position'] ?? 0,
      nextMilestonePosition: json['next_milestone_position'] ?? 5,
      gamesUntilMilestone: json['games_until_milestone'] ?? 5,
      events: (json['events'] as List<dynamic>?)
          ?.map((e) => JourneyEvent.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'profile_id': profileId,
      'epic_arc_id': epicArcId,
      'current_position': currentPosition,
      'next_milestone_position': nextMilestonePosition,
      'games_until_milestone': gamesUntilMilestone,
      'events': events.map((e) => e.toJson()).toList(),
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
  
  JourneyProgress copyWith({
    int? currentPosition,
    int? nextMilestonePosition,
    int? gamesUntilMilestone,
    List<JourneyEvent>? events,
    DateTime? lastUpdated,
  }) {
    return JourneyProgress(
      profileId: profileId,
      epicArcId: epicArcId,
      currentPosition: currentPosition ?? this.currentPosition,
      nextMilestonePosition: nextMilestonePosition ?? this.nextMilestonePosition,
      gamesUntilMilestone: gamesUntilMilestone ?? this.gamesUntilMilestone,
      events: events ?? this.events,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
  
  double get progressToMilestone {
    final total = nextMilestonePosition;
    return total > 0 ? currentPosition / total : 0.0;
  }
}

/// An event on the journey board
enum JourneyEventType {
  treasure,   // Bonus reward
  challenge,  // Extra practice
  storyBeat,  // Mini cutscene
  choice,     // Pick path
}

class JourneyEvent {
  final String id;
  final JourneyEventType type;
  final int position;
  final String? description;
  final Map<String, dynamic>? data;
  
  const JourneyEvent({
    required this.id,
    required this.type,
    required this.position,
    this.description,
    this.data,
  });
  
  factory JourneyEvent.fromJson(Map<String, dynamic> json) {
    return JourneyEvent(
      id: json['id'] ?? '',
      type: _parseEventType(json['type']),
      position: json['position'] ?? 0,
      description: json['description'],
      data: json['data'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': _eventTypeToString(type),
      'position': position,
      'description': description,
      'data': data,
    };
  }
  
  static JourneyEventType _parseEventType(String? type) {
    switch (type?.toLowerCase()) {
      case 'treasure':
        return JourneyEventType.treasure;
      case 'challenge':
        return JourneyEventType.challenge;
      case 'story_beat':
        return JourneyEventType.storyBeat;
      case 'choice':
        return JourneyEventType.choice;
      default:
        return JourneyEventType.treasure;
    }
  }
  
  static String _eventTypeToString(JourneyEventType type) {
    switch (type) {
      case JourneyEventType.treasure:
        return 'treasure';
      case JourneyEventType.challenge:
        return 'challenge';
      case JourneyEventType.storyBeat:
        return 'story_beat';
      case JourneyEventType.choice:
        return 'choice';
    }
  }
}

