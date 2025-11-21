import 'dart:math';

import '../data/built_in_stories.dart';
import '../models/story_generation_models.dart';
import '../models/story_models.dart';
import '../utils/app_logger.dart';
import '../utils/reading_level_helper.dart';
import 'openrouter_story_client.dart';
import 'story_storage_service.dart';

class StoryGeneratorService {
  StoryGeneratorService({
    OpenRouterStoryClient? client,
    StoryStorageService? storage,
  })  : _client = client ?? OpenRouterStoryClient(),
        _storage = storage ?? StoryStorageService.instance;

  final OpenRouterStoryClient _client;
  final StoryStorageService _storage;

  Future<GeneratedStoryRecord> generateStory(StoryGenerationRequest request) async {
    AppLogger.system.d(
      'StoryGeneratorService: request(level=${request.readingLevel}, minutes=${request.durationMinutes})',
    );
    final result = await _client.generateStoryPayload(request);
    final record = _recordFromPayload(result.payload, request, result.modelId);
    await _storage.saveStory(record);
    AppLogger.system.emoji('📖', 'Stored story "${record.chapter.title}" (${record.id})');
    return record;
  }

  Future<List<GeneratedStoryRecord>> loadStories() async {
    final stored = await _storage.loadStories();
    final builtIns = BuiltInStoryLibrary.loadStories();
    return [...stored, ...builtIns];
  }

  Future<void> deleteStory(String storyId) => _storage.deleteStory(storyId);

  Future<GeneratedStoryRecord?> recordStoryOpened(String storyId) async {
    return _storage.updateStory(
      storyId,
      (current) {
        final now = DateTime.now();
        final updatedMoments = List<DateTime>.from(current.readMoments)..add(now);
        if (updatedMoments.length > 30) {
          updatedMoments.removeRange(0, updatedMoments.length - 30);
        }
        return current.copyWith(
          readCount: current.readCount + 1,
          lastReadAt: now,
          readMoments: updatedMoments,
        );
      },
    );
  }

  Future<GeneratedStoryRecord?> toggleFavorite(String storyId, {bool? value}) async {
    return _storage.updateStory(
      storyId,
      (current) {
        final desired = value ?? !current.isFavorite;
        return current.copyWith(isFavorite: desired);
      },
    );
  }

  Future<GeneratedStoryRecord?> setChildRating(String storyId, int? rating) async {
    return _storage.updateStory(
      storyId,
      (current) => current.copyWith(
        childRating: rating,
        isFavorite: rating != null && rating >= 4,
      ),
    );
  }

  GeneratedStoryRecord _recordFromPayload(
    Map<String, dynamic> payload,
    StoryGenerationRequest request,
    String modelUsed,
  ) {
    final beats = _parseBeats(payload['beats']);
    final choicePoints = _parseChoicePoints(payload['choice_points']);
    final storyId = payload['id']?.toString().trim().isNotEmpty == true
        ? payload['id'].toString()
        : 'story_${DateTime.now().millisecondsSinceEpoch}';
    final title = payload['title'] as String? ?? 'Story Time Adventure';
    final summary = payload['summary'] as String? ?? '';
    final metadata = Map<String, dynamic>.from(payload['metadata'] as Map<String, dynamic>? ?? {});
    metadata['generated_via'] = 'openrouter';
    metadata['requested_at'] = request.requestedAt.toIso8601String();
    metadata['parent_prompt'] = request.parentPrompt;
    metadata['child_context'] = request.childContext;
    metadata['model_used'] = modelUsed;
    metadata['reading_band'] = request.readingBand.toJson();
    metadata['include_child_name'] = request.includeChildName;
    metadata['child_name'] = request.includeChildName ? request.childName : null;

    final chapter = StoryChapter(
      id: storyId,
      title: title,
      beats: beats,
      choicePoints: choicePoints,
      metadata: metadata,
    );

    final focusWords = (payload['focus_words'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final estimatedMinutes = (payload['estimated_minutes'] as num?)?.toInt() ?? request.durationMinutes;
    final readingLevel = payload['reading_level'] as int? ?? request.readingLevel;
    final familiarityStats = _computeFamiliarity(chapter, request.readingBand);

    return GeneratedStoryRecord(
      id: storyId,
      chapter: chapter,
      summary: summary,
      readingLevel: readingLevel,
      durationMinutes: estimatedMinutes,
      focusWords: focusWords,
      familiarWordRatio: familiarityStats.ratio,
      familiarWordCount: familiarityStats.familiarCount,
      totalWordCount: familiarityStats.totalWords,
      parentPrompt: request.parentPrompt,
      childContext: request.childContext,
      storyConcept: request.storyConcept,
      model: modelUsed,
      includeChildName: request.includeChildName,
      createdAt: DateTime.now(),
      requestInputs: request.toMap(),
      isFavorite: false,
      readCount: 0,
      lastReadAt: null,
      childRating: null,
      isBuiltIn: false,
    );
  }

  List<StoryBeat> _parseBeats(dynamic beatsJson) {
    final beatsList = (beatsJson as List<dynamic>? ?? []).cast<Map<String, dynamic>?>();
    return beatsList.asMap().entries.map((entry) {
      final beat = entry.value ?? {};
      return StoryBeat(
        id: beat['id']?.toString().isNotEmpty == true ? beat['id'].toString() : 'beat_${entry.key + 1}',
        type: _parseBeatType(beat['type']),
        text: beat['text']?.toString() ?? '',
        speaker: _parseSpeaker(beat['speaker']),
        targetWords: (beat['target_words'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        coachPhrase: beat['coach_phrase']?.toString(),
      );
    }).toList();
  }

  List<ChoicePoint> _parseChoicePoints(dynamic choiceJson) {
    final list = (choiceJson as List<dynamic>? ?? []).cast<Map<String, dynamic>?>();
    return list.map((choice) {
      final choices = (choice?['choices'] as List<dynamic>? ?? [])
          .map((c) => c as Map<String, dynamic>? ?? {})
          .toList();
      return ChoicePoint(
        id: choice?['id']?.toString() ?? 'choice_${DateTime.now().millisecondsSinceEpoch}',
        beatIndex: (choice?['beat_index'] as num?)?.toInt() ?? 0,
        promptText: choice?['prompt_text']?.toString() ?? '',
        choices: choices
            .map(
              (c) => StoryChoice(
                id: c['id']?.toString() ?? 'choice_option_${Random().nextInt(9999)}',
                previewText: c['preview_text']?.toString() ?? '',
                choiceText: c['choice_text']?.toString() ?? '',
              ),
            )
            .toList(),
      );
    }).toList();
  }

  _FamiliarityStats _computeFamiliarity(StoryChapter chapter, ReadingBand readingBand) {
    final vocab = ReadingLevelHelper.vocabularyForBand(readingBand)
        .map((w) => w.toLowerCase())
        .toSet();
    final words = chapter.beats
        .expand((beat) => beat.text
            .replaceAll(RegExp(r"[^\w\s']"), '')
            .toLowerCase()
            .split(RegExp(r'\s+')))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return _FamiliarityStats.zero();
    }
    final familiarCount = words.where(vocab.contains).length;
    final ratio = familiarCount / words.length;
    return _FamiliarityStats(
      familiarCount: familiarCount,
      totalWords: words.length,
      ratio: ratio,
    );
  }

  BeatType _parseBeatType(dynamic type) {
    switch (type?.toString().toLowerCase()) {
      case 'child_turn':
      case 'child':
        return BeatType.childTurn;
      case 'coach':
      case 'coach_intervention':
      case 'coaching':
        return BeatType.coachIntervention;
      case 'celebration':
        return BeatType.celebration;
      case 'narration':
      default:
        return BeatType.narration;
    }
  }

  Speaker? _parseSpeaker(dynamic speaker) {
    switch (speaker?.toString().toLowerCase()) {
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
}

class _FamiliarityStats {
  final int familiarCount;
  final int totalWords;
  final double ratio;

  const _FamiliarityStats({
    required this.familiarCount,
    required this.totalWords,
    required this.ratio,
  });

  factory _FamiliarityStats.zero() => const _FamiliarityStats(
        familiarCount: 0,
        totalWords: 0,
        ratio: 0,
      );
}

