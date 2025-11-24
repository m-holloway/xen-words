import 'dart:convert';

import '../utils/reading_level_helper.dart';
import 'story_models.dart';

const _generatedStoryRecordUndefined = Object();

enum StoryReadingMode { parent, child }

extension StoryReadingModeX on StoryReadingMode {
  String get label =>
      this == StoryReadingMode.parent ? 'Parent Mode' : 'Child Mode';
}

/// Form inputs for the Story Lab feature.
class StoryGenerationRequest {
  final int readingLevel;
  final ReadingBand readingBand;
  final int durationMinutes;
  final String parentPrompt;
  final String childContext;
  final String? storyConcept;
  final String? childName;
  final String? profileId;
  /// Optional natural language description of Story World characters
  /// (the \"cast\") that should appear in this story.
  final String? castContext;
  /// IDs of Story World character entities selected for this story.
  final List<String> castCharacterIds;
  final String model;
  final DateTime requestedAt;
  final bool includeChildName;

  StoryGenerationRequest({
    required this.readingLevel,
    required this.readingBand,
    required this.durationMinutes,
    required this.parentPrompt,
    required this.childContext,
    this.storyConcept,
    this.childName,
    this.profileId,
    this.castContext,
    this.castCharacterIds = const [],
    this.model = StoryGenerationDefaults.defaultModelId,
    this.includeChildName = false,
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'reading_level': readingLevel,
      'reading_band': readingBand.toJson(),
      'duration_minutes': durationMinutes,
      'parent_prompt': parentPrompt,
      'child_context': childContext,
      'story_concept': storyConcept,
      'child_name': childName,
      'profile_id': profileId,
      'cast_context': castContext,
      'cast_character_ids': castCharacterIds,
      'model': model,
      'requested_at': requestedAt.toIso8601String(),
      'include_child_name': includeChildName,
    };
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  StoryGenerationRequest copyWith({
    int? readingLevel,
    int? durationMinutes,
    String? parentPrompt,
    String? childContext,
    ReadingBand? readingBand,
    String? storyConcept,
    String? childName,
    String? profileId,
    String? castContext,
    List<String>? castCharacterIds,
    String? model,
    DateTime? requestedAt,
    bool? includeChildName,
  }) {
    return StoryGenerationRequest(
      readingLevel: readingLevel ?? this.readingLevel,
      readingBand: readingBand ?? this.readingBand,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      parentPrompt: parentPrompt ?? this.parentPrompt,
      childContext: childContext ?? this.childContext,
      storyConcept: storyConcept ?? this.storyConcept,
      childName: childName ?? this.childName,
      profileId: profileId ?? this.profileId,
      castContext: castContext ?? this.castContext,
      castCharacterIds: castCharacterIds ?? this.castCharacterIds,
      model: model ?? this.model,
      includeChildName: includeChildName ?? this.includeChildName,
      requestedAt: requestedAt ?? this.requestedAt,
    );
  }
}

/// Persisted story metadata + chapter payload.
class GeneratedStoryRecord {
  final String id;
  final StoryChapter chapter;
  final String summary;
  final int readingLevel;
  final int durationMinutes;
  final List<String> focusWords;
  final double familiarWordRatio;
  final int familiarWordCount;
  final int totalWordCount;
  final String parentPrompt;
  final String childContext;
  final String? storyConcept;
  final String model;
  final DateTime createdAt;
  final bool includeChildName;
  final Map<String, dynamic>? requestInputs;
  final bool isFavorite;
  final int readCount;
  final DateTime? lastReadAt;
  final int? childRating;
  final List<DateTime> readMoments;
  final bool isBuiltIn;
  final int version;
  final List<StoryRevision> revisions;
  final String? coverImagePath;
  final StoryPanelArtMetadata? panelArt;

  GeneratedStoryRecord({
    required this.id,
    required this.chapter,
    required this.summary,
    required this.readingLevel,
    required this.durationMinutes,
    required this.focusWords,
    required this.familiarWordRatio,
    required this.familiarWordCount,
    required this.totalWordCount,
    required this.parentPrompt,
    required this.childContext,
    required this.storyConcept,
    required this.model,
    required this.createdAt,
    this.includeChildName = false,
    this.requestInputs,
    this.isFavorite = false,
    this.readCount = 0,
    this.lastReadAt,
    this.childRating,
    List<DateTime>? readMoments,
    this.isBuiltIn = false,
    this.version = 1,
    List<StoryRevision>? revisions,
    this.coverImagePath,
    this.panelArt,
  }) : readMoments = readMoments ?? const [],
       revisions = revisions ?? const [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chapter': chapter.toJson(),
      'summary': summary,
      'reading_level': readingLevel,
      'duration_minutes': durationMinutes,
      'focus_words': focusWords,
      'familiar_word_ratio': familiarWordRatio,
      'familiar_word_count': familiarWordCount,
      'total_word_count': totalWordCount,
      'parent_prompt': parentPrompt,
      'child_context': childContext,
      'story_concept': storyConcept,
      'model': model,
      'created_at': createdAt.toIso8601String(),
      'include_child_name': includeChildName,
      'request_inputs': requestInputs,
      'is_favorite': isFavorite,
      'read_count': readCount,
      'last_read_at': lastReadAt?.toIso8601String(),
      'child_rating': childRating,
      'read_moments': readMoments.map((d) => d.toIso8601String()).toList(),
      'is_built_in': isBuiltIn,
      'version': version,
      'revisions': revisions.map((r) => r.toJson()).toList(),
      'cover_image_path': coverImagePath,
      'panel_art': panelArt?.toJson(),
    };
  }

  factory GeneratedStoryRecord.fromJson(Map<String, dynamic> json) {
    return GeneratedStoryRecord(
      id: json['id'] as String,
      chapter: StoryChapter.fromJson(json['chapter'] as Map<String, dynamic>),
      summary: json['summary'] as String? ?? '',
      readingLevel:
          json['reading_level'] as int? ??
          StoryGenerationDefaults.defaultReadingLevel,
      durationMinutes:
          json['duration_minutes'] as int? ??
          StoryGenerationDefaults.defaultMinutes,
      focusWords: (json['focus_words'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      familiarWordRatio: (json['familiar_word_ratio'] as num?)?.toDouble() ?? 0,
      familiarWordCount: json['familiar_word_count'] as int? ?? 0,
      totalWordCount: json['total_word_count'] as int? ?? 0,
      parentPrompt: json['parent_prompt'] as String? ?? '',
      childContext: json['child_context'] as String? ?? '',
      storyConcept: json['story_concept'] as String?,
      model: json['model'] as String? ?? StoryGenerationDefaults.defaultModelId,
      createdAt: DateTime.parse(json['created_at'] as String),
      includeChildName: json['include_child_name'] as bool? ?? false,
      requestInputs: json['request_inputs'] is Map
          ? Map<String, dynamic>.from(json['request_inputs'] as Map)
          : null,
      isFavorite: json['is_favorite'] as bool? ?? false,
      readCount: json['read_count'] as int? ?? 0,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'] as String)
          : null,
      childRating: json['child_rating'] as int?,
      readMoments: (json['read_moments'] as List<dynamic>? ?? [])
          .map((value) => DateTime.tryParse(value as String))
          .whereType<DateTime>()
          .toList(),
      isBuiltIn: json['is_built_in'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
      revisions: (json['revisions'] as List<dynamic>? ?? [])
          .map((value) => StoryRevision.fromJson(value as Map<String, dynamic>))
          .toList(),
      coverImagePath: json['cover_image_path'] as String?,
      panelArt: json['panel_art'] is Map<String, dynamic>
          ? StoryPanelArtMetadata.fromJson(
              json['panel_art'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  GeneratedStoryRecord copyWith({
    StoryChapter? chapter,
    String? summary,
    int? readingLevel,
    int? durationMinutes,
    List<String>? focusWords,
    double? familiarWordRatio,
    int? familiarWordCount,
    int? totalWordCount,
    String? parentPrompt,
    String? childContext,
    String? storyConcept,
    String? model,
    DateTime? createdAt,
    bool? includeChildName,
    Map<String, dynamic>? requestInputs,
    bool? isFavorite,
    int? readCount,
    DateTime? lastReadAt,
    int? childRating,
    List<DateTime>? readMoments,
    bool? isBuiltIn,
    int? version,
    List<StoryRevision>? revisions,
    Object? coverImagePath = _generatedStoryRecordUndefined,
    Object? panelArt = _generatedStoryRecordUndefined,
  }) {
    final coverImageValue =
        identical(coverImagePath, _generatedStoryRecordUndefined)
        ? this.coverImagePath
        : coverImagePath as String?;
    final panelArtValue =
        identical(panelArt, _generatedStoryRecordUndefined)
            ? this.panelArt
            : panelArt as StoryPanelArtMetadata?;
    return GeneratedStoryRecord(
      id: id,
      chapter: chapter ?? this.chapter,
      summary: summary ?? this.summary,
      readingLevel: readingLevel ?? this.readingLevel,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      focusWords: focusWords ?? this.focusWords,
      familiarWordRatio: familiarWordRatio ?? this.familiarWordRatio,
      familiarWordCount: familiarWordCount ?? this.familiarWordCount,
      totalWordCount: totalWordCount ?? this.totalWordCount,
      parentPrompt: parentPrompt ?? this.parentPrompt,
      childContext: childContext ?? this.childContext,
      storyConcept: storyConcept ?? this.storyConcept,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
      includeChildName: includeChildName ?? this.includeChildName,
      requestInputs: requestInputs ?? this.requestInputs,
      isFavorite: isFavorite ?? this.isFavorite,
      readCount: readCount ?? this.readCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      childRating: childRating ?? this.childRating,
      readMoments: readMoments ?? this.readMoments,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      version: version ?? this.version,
      revisions: revisions ?? this.revisions,
      coverImagePath: coverImageValue,
      panelArt: panelArtValue,
    );
  }
}

class StoryPanelArtMetadata {
  final int columns;
  final int rows;
  final List<String> panelImagePaths;
  final String sheetImagePath;
  final DateTime importedAt;
  final Map<int, String> assignments; // narrationBeatIndex -> panelPath

  const StoryPanelArtMetadata({
    required this.columns,
    required this.rows,
    required this.panelImagePaths,
    required this.sheetImagePath,
    required this.importedAt,
    this.assignments = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'columns': columns,
      'rows': rows,
      'panel_image_paths': panelImagePaths,
      'sheet_image_path': sheetImagePath,
      'imported_at': importedAt.toIso8601String(),
      'assignments': assignments.map((key, value) => MapEntry(key.toString(), value)),
    };
  }

  factory StoryPanelArtMetadata.fromJson(Map<String, dynamic> json) {
    final rawAssignments = json['assignments'] as Map<String, dynamic>? ?? {};
    return StoryPanelArtMetadata(
      columns: json['columns'] as int? ?? 1,
      rows: json['rows'] as int? ?? 1,
      panelImagePaths: (json['panel_image_paths'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      sheetImagePath: json['sheet_image_path'] as String? ?? '',
      importedAt:
          DateTime.tryParse(json['imported_at'] as String? ?? '') ??
          DateTime.now(),
      assignments: rawAssignments.map(
        (key, value) => MapEntry(int.tryParse(key) ?? -1, value.toString()),
      )..removeWhere((key, value) => key == -1),
    );
  }

  StoryPanelArtMetadata copyWith({
    int? columns,
    int? rows,
    List<String>? panelImagePaths,
    String? sheetImagePath,
    DateTime? importedAt,
    Map<int, String>? assignments,
  }) {
    return StoryPanelArtMetadata(
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      panelImagePaths: panelImagePaths ?? this.panelImagePaths,
      sheetImagePath: sheetImagePath ?? this.sheetImagePath,
      importedAt: importedAt ?? this.importedAt,
      assignments: assignments ?? this.assignments,
    );
  }
}

class StoryRevision {
  final int version;
  final String instructions;
  final String storyText;
  final DateTime createdAt;
  final String modelId;

  StoryRevision({
    required this.version,
    required this.instructions,
    required this.storyText,
    required this.createdAt,
    required this.modelId,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'instructions': instructions,
      'story_text': storyText,
      'created_at': createdAt.toIso8601String(),
      'model_id': modelId,
    };
  }

  factory StoryRevision.fromJson(Map<String, dynamic> json) {
    return StoryRevision(
      version: json['version'] as int? ?? 1,
      instructions: json['instructions'] as String? ?? '',
      storyText: json['story_text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      modelId:
          json['model_id'] as String? ?? StoryGenerationDefaults.defaultModelId,
    );
  }
}

class StoryGenerationDefaults {
  static const String primaryModelId = 'google/gemini-2.5-flash';
  static const String fallbackModelId = 'moonshotai/kimi-k2-thinking'; //'openai/gpt-5.1'; //'qwen/qwen-2.5-72b-instruct';
  static const String defaultModelId = primaryModelId;
  static const int minMinutes = 5;
  static const int maxMinutes = 20;
  static const int defaultMinutes = 8;
  static const int minReadingLevel = 1;
  static const int maxReadingLevel = 5;
  static const int defaultReadingLevel = 2;
}
