/// Story data models for parent-child coaching sessions
library;

import 'package:flutter/material.dart';

/// Types of story beats
enum BeatType {
  narration,      // Parent reads
  childTurn,      // Child says word
  coachIntervention,  // Coach helps
  celebration,    // Group celebration
}

/// Speaker in the story
enum Speaker {
  parent,
  coach,
  child,
}

/// A single beat (1-2 sentences) in the story
class StoryBeat {
  final String id;
  final BeatType type;
  final String text;
  final Speaker? speaker;
  final List<String> targetWords;
  final String? coachPhrase;
  
  const StoryBeat({
    required this.id,
    required this.type,
    required this.text,
    this.speaker,
    this.targetWords = const [],
    this.coachPhrase,
  });
  
  factory StoryBeat.fromJson(Map<String, dynamic> json) {
    return StoryBeat(
      id: json['id'] ?? '',
      type: _parseBeatType(json['type']),
      text: json['text'] ?? '',
      speaker: _parseSpeaker(json['speaker']),
      targetWords: (json['target_words'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      coachPhrase: json['coach_phrase'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': _beatTypeToString(type),
      'text': text,
      'speaker': speaker != null ? _speakerToString(speaker!) : null,
      'target_words': targetWords,
      'coach_phrase': coachPhrase,
    };
  }
  
  static BeatType _parseBeatType(String? type) {
    switch (type?.toLowerCase()) {
      case 'narration':
        return BeatType.narration;
      case 'child_turn':
        return BeatType.childTurn;
      case 'coaching':
      case 'coach_intervention':
        return BeatType.coachIntervention;
      case 'celebration':
        return BeatType.celebration;
      default:
        return BeatType.narration;
    }
  }
  
  static Speaker? _parseSpeaker(String? speaker) {
    switch (speaker?.toLowerCase()) {
      case 'parent':
        return Speaker.parent;
      case 'coach':
        return Speaker.coach;
      case 'child':
        return Speaker.child;
      default:
        return null;
    }
  }
  
  static String _beatTypeToString(BeatType type) {
    switch (type) {
      case BeatType.narration:
        return 'narration';
      case BeatType.childTurn:
        return 'child_turn';
      case BeatType.coachIntervention:
        return 'coaching';
      case BeatType.celebration:
        return 'celebration';
    }
  }
  
  static String _speakerToString(Speaker speaker) {
    switch (speaker) {
      case Speaker.parent:
        return 'parent';
      case Speaker.coach:
        return 'coach';
      case Speaker.child:
        return 'child';
    }
  }
}

/// A choice the child can make in the story
class StoryChoice {
  final String id;
  final String previewText;
  final String choiceText;
  
  const StoryChoice({
    required this.id,
    required this.previewText,
    required this.choiceText,
  });
  
  factory StoryChoice.fromJson(Map<String, dynamic> json) {
    return StoryChoice(
      id: json['id'] ?? '',
      previewText: json['preview_text'] ?? '',
      choiceText: json['choice_text'] ?? '',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'preview_text': previewText,
      'choice_text': choiceText,
    };
  }
}

/// A point in the story where the child makes a choice
class ChoicePoint {
  final String id;
  final int beatIndex;
  final String promptText;
  final List<StoryChoice> choices;
  
  const ChoicePoint({
    required this.id,
    required this.beatIndex,
    required this.promptText,
    required this.choices,
  });
  
  factory ChoicePoint.fromJson(Map<String, dynamic> json) {
    return ChoicePoint(
      id: json['id'] ?? '',
      beatIndex: json['beat_index'] ?? 0,
      promptText: json['prompt_text'] ?? '',
      choices: (json['choices'] as List<dynamic>?)
          ?.map((e) => StoryChoice.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'beat_index': beatIndex,
      'prompt_text': promptText,
      'choices': choices.map((c) => c.toJson()).toList(),
    };
  }
}

/// A complete story chapter
class StoryChapter {
  final String id;
  final String title;
  final List<StoryBeat> beats;
  final List<ChoicePoint> choicePoints;
  final Map<String, dynamic>? metadata;
  
  const StoryChapter({
    required this.id,
    required this.title,
    required this.beats,
    this.choicePoints = const [],
    this.metadata,
  });
  
  factory StoryChapter.fromJson(Map<String, dynamic> json) {
    return StoryChapter(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled Story',
      beats: (json['beats'] as List<dynamic>?)
          ?.map((e) => StoryBeat.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      choicePoints: (json['choice_points'] as List<dynamic>?)
          ?.map((e) => ChoicePoint.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'beats': beats.map((b) => b.toJson()).toList(),
      'choice_points': choicePoints.map((c) => c.toJson()).toList(),
      'metadata': metadata,
    };
  }
  
  /// Get the chapter number from metadata
  int get chapterNum => metadata?['chapter_num'] ?? 1;
  
  /// Get the theme from metadata
  String get theme => metadata?['theme'] ?? 'adventure';
  
  /// Get the tone from metadata
  String get tone => metadata?['tone'] ?? 'encouraging';
}

/// Progress through a story arc
class StoryProgress {
  final String arcId;
  final int currentChapter;
  final List<String> completedChapters;
  final Map<String, String> choicesMade;  // choice_point_id -> choice_id
  final DateTime lastPlayedDate;
  
  const StoryProgress({
    required this.arcId,
    required this.currentChapter,
    this.completedChapters = const [],
    this.choicesMade = const {},
    required this.lastPlayedDate,
  });
  
  factory StoryProgress.fromJson(Map<String, dynamic> json) {
    return StoryProgress(
      arcId: json['arc_id'] ?? '',
      currentChapter: json['current_chapter'] ?? 1,
      completedChapters: (json['completed_chapters'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      choicesMade: Map<String, String>.from(json['choices_made'] ?? {}),
      lastPlayedDate: DateTime.parse(json['last_played_date'] ?? DateTime.now().toIso8601String()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'arc_id': arcId,
      'current_chapter': currentChapter,
      'completed_chapters': completedChapters,
      'choices_made': choicesMade,
      'last_played_date': lastPlayedDate.toIso8601String(),
    };
  }
  
  StoryProgress copyWith({
    String? arcId,
    int? currentChapter,
    List<String>? completedChapters,
    Map<String, String>? choicesMade,
    DateTime? lastPlayedDate,
  }) {
    return StoryProgress(
      arcId: arcId ?? this.arcId,
      currentChapter: currentChapter ?? this.currentChapter,
      completedChapters: completedChapters ?? this.completedChapters,
      choicesMade: choicesMade ?? this.choicesMade,
      lastPlayedDate: lastPlayedDate ?? this.lastPlayedDate,
    );
  }
}

/// An epic story arc spanning multiple chapters
class EpicArc {
  final String id;
  final String title;
  final String theme;
  final int totalChapters;
  final List<Milestone> milestones;
  final Map<String, dynamic>? metadata;
  
  const EpicArc({
    required this.id,
    required this.title,
    required this.theme,
    required this.totalChapters,
    this.milestones = const [],
    this.metadata,
  });
  
  factory EpicArc.fromJson(Map<String, dynamic> json) {
    return EpicArc(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Epic Adventure',
      theme: json['theme'] ?? 'adventure',
      totalChapters: json['total_chapters'] ?? 10,
      milestones: (json['milestones'] as List<dynamic>?)
          ?.map((e) => Milestone.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'theme': theme,
      'total_chapters': totalChapters,
      'milestones': milestones.map((m) => m.toJson()).toList(),
      'metadata': metadata,
    };
  }
}

/// A milestone in the epic arc
class Milestone {
  final String id;
  final int wordsRequired;
  final int chapterNum;
  final String title;
  final String description;
  final String reward;
  final int durationMinutes;
  final bool unlocked;
  
  const Milestone({
    required this.id,
    required this.wordsRequired,
    required this.chapterNum,
    required this.title,
    required this.description,
    required this.reward,
    this.durationMinutes = 5,
    this.unlocked = false,
  });
  
  factory Milestone.fromJson(Map<String, dynamic> json) {
    return Milestone(
      id: json['id'] ?? '',
      wordsRequired: json['words_required'] ?? 5,
      chapterNum: json['chapter_num'] ?? 1,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      reward: json['reward'] ?? '',
      durationMinutes: json['story_duration_minutes'] ?? 5,
      unlocked: json['unlocked'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'words_required': wordsRequired,
      'chapter_num': chapterNum,
      'title': title,
      'description': description,
      'reward': reward,
      'story_duration_minutes': durationMinutes,
      'unlocked': unlocked,
    };
  }
  
  Milestone copyWith({bool? unlocked}) {
    return Milestone(
      id: id,
      wordsRequired: wordsRequired,
      chapterNum: chapterNum,
      title: title,
      description: description,
      reward: reward,
      durationMinutes: durationMinutes,
      unlocked: unlocked ?? this.unlocked,
    );
  }
}

