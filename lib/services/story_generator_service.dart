import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/built_in_stories.dart';
import '../models/story_generation_models.dart';
import '../models/story_models.dart';
import '../prompts/character_extraction_prompt.dart';
import '../prompts/cover_art_prompt.dart';
import '../prompts/panel_art_prompt.dart';
import '../prompts/panel_description_prompt.dart';
import '../secrets/openrouter_secret.dart' as local_secret;
import '../utils/app_logger.dart';
import '../utils/reading_level_helper.dart';
import '../utils/story_text_utils.dart';
import 'openrouter_image_client.dart';
import 'openrouter_story_client.dart';
import 'story_panel_art_service.dart';
import 'story_storage_service.dart';

class StoryGeneratorService {
  StoryGeneratorService({
    OpenRouterStoryClient? client,
    StoryStorageService? storage,
    OpenRouterImageClient? imageClient,
  }) : _client = client ?? OpenRouterStoryClient(),
       _storage = storage ?? StoryStorageService.instance,
       _imageClient = imageClient ?? OpenRouterImageClient();

  final OpenRouterStoryClient _client;
  final StoryStorageService _storage;
  final OpenRouterImageClient _imageClient;

  Future<GeneratedStoryRecord> generateStory(
    StoryGenerationRequest request,
  ) async {
    AppLogger.system.d(
      'StoryGeneratorService: request(level=${request.readingLevel}, minutes=${request.durationMinutes})',
    );
    final result = await _client.generateStoryPayload(request);
    final record = _recordFromPayload(result.payload, request, result.modelId);
    await _storage.saveStory(record);
    AppLogger.system.emoji(
      '📖',
      'Stored story "${record.chapter.title}" (${record.id})',
    );
    return record;
  }

  Future<List<GeneratedStoryRecord>> loadStories() async {
    final stored = await _storage.loadStories();
    final builtIns = BuiltInStoryLibrary.loadStories();
    return [...stored, ...builtIns];
  }

  Future<void> deleteStory(String storyId) => _storage.deleteStory(storyId);

  Future<GeneratedStoryRecord?> recordStoryOpened(String storyId) async {
    return _storage.updateStory(storyId, (current) {
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
    });
  }

  Future<GeneratedStoryRecord?> toggleFavorite(
    String storyId, {
    bool? value,
  }) async {
    return _storage.updateStory(storyId, (current) {
      final desired = value ?? !current.isFavorite;
      return current.copyWith(isFavorite: desired);
    });
  }

  Future<GeneratedStoryRecord?> setChildRating(
    String storyId,
    int? rating,
  ) async {
    return _storage.updateStory(
      storyId,
      (current) => current.copyWith(
        childRating: rating,
        isFavorite: rating != null && rating >= 4,
      ),
    );
  }

  Future<GeneratedStoryRecord?> updateStoryTitle(
    String storyId,
    String newTitle,
  ) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Title cannot be empty.');
    }
    return _storage.updateStory(storyId, (current) {
      final updatedChapter = StoryChapter(
        id: current.chapter.id,
        title: trimmed,
        beats: current.chapter.beats,
        choicePoints: current.chapter.choicePoints,
        metadata: current.chapter.metadata,
      );
      return current.copyWith(chapter: updatedChapter);
    });
  }

  Future<GeneratedStoryRecord?> updateStoryCover(
    String storyId,
    String? coverPath,
  ) {
    return _storage.updateStory(storyId, (current) {
      return current.copyWith(coverImagePath: coverPath);
    });
  }

  Future<GeneratedStoryRecord?> updateStoryPanelArt(
    String storyId,
    StoryPanelArtMetadata? art,
  ) {
    return _storage.updateStory(storyId, (current) {
      return current.copyWith(panelArt: art);
    });
  }

  Future<GeneratedStoryRecord?> updateStoryText(
    String storyId,
    String rawText,
  ) {
    final sanitized = rawText.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('Story text cannot be empty.');
    }
    return _storage.updateStory(storyId, (current) {
      final updatedBeats = _beatsFromRawText(sanitized);
      final updatedChapter = StoryChapter(
        id: current.chapter.id,
        title: current.chapter.title,
        beats: updatedBeats,
        choicePoints: current.chapter.choicePoints,
        metadata: current.chapter.metadata,
      );
      final band = ReadingLevelHelper.bandForLevel(current.readingLevel);
      final familiarity = _computeFamiliarity(updatedChapter, band);
      return current.copyWith(
        chapter: updatedChapter,
        totalWordCount: familiarity.totalWords,
        familiarWordCount: familiarity.familiarCount,
        familiarWordRatio: familiarity.ratio,
      );
    });
  }

  Future<StoryRevisionDraft> draftRevision(
    GeneratedStoryRecord story,
    String instructions,
  ) async {
    final trimmed = instructions.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Please describe what you want to revise.');
    }
    final result = await _client.reviseStoryPayload(
      story: story,
      instructions: trimmed,
    );
    final draft = _recordFromRevisionPayload(
      base: story,
      payload: result.payload,
      modelUsed: result.modelId,
    );
    return StoryRevisionDraft(
      record: draft,
      modelId: result.modelId,
      instructions: trimmed,
    );
  }

  Future<GeneratedStoryRecord?> applyRevision({
    required String storyId,
    required StoryRevisionDraft draft,
  }) {
    return _storage.updateStory(storyId, (current) {
      final nextVersion = current.version + 1;
      final revisionEntry = StoryRevision(
        version: nextVersion,
        instructions: draft.instructions,
        storyText: StoryTextUtils.narrationOnly(draft.record.chapter),
        createdAt: DateTime.now(),
        modelId: draft.modelId,
      );
      final history = List<StoryRevision>.from(current.revisions)
        ..add(revisionEntry);
      final updatedChapter = StoryChapter(
        id: current.chapter.id,
        title: draft.record.chapter.title,
        beats: draft.record.chapter.beats,
        choicePoints: draft.record.chapter.choicePoints,
        metadata: draft.record.chapter.metadata,
      );
      return current.copyWith(
        chapter: updatedChapter,
        summary: draft.record.summary,
        readingLevel: draft.record.readingLevel,
        durationMinutes: draft.record.durationMinutes,
        focusWords: draft.record.focusWords,
        familiarWordRatio: draft.record.familiarWordRatio,
        familiarWordCount: draft.record.familiarWordCount,
        totalWordCount: draft.record.totalWordCount,
        model: draft.modelId,
        version: nextVersion,
        revisions: history,
      );
    });
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
    final metadata = Map<String, dynamic>.from(
      payload['metadata'] as Map<String, dynamic>? ?? {},
    );
    metadata['generated_via'] = 'openrouter';
    metadata['requested_at'] = request.requestedAt.toIso8601String();
    metadata['parent_prompt'] = request.parentPrompt;
    metadata['child_context'] = request.childContext;
    metadata['model_used'] = modelUsed;
    metadata['reading_band'] = request.readingBand.toJson();
    metadata['include_child_name'] = request.includeChildName;
    metadata['child_name'] = request.includeChildName
        ? request.childName
        : null;

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
    final estimatedMinutes =
        (payload['estimated_minutes'] as num?)?.toInt() ??
        request.durationMinutes;
    final readingLevel =
        payload['reading_level'] as int? ?? request.readingLevel;
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

  GeneratedStoryRecord _recordFromRevisionPayload({
    required GeneratedStoryRecord base,
    required Map<String, dynamic> payload,
    required String modelUsed,
  }) {
    final beats = _parseBeats(payload['beats']);
    final choicePoints = _parseChoicePoints(payload['choice_points']);
    final title = payload['title'] as String? ?? base.chapter.title;
    final summary = payload['summary'] as String? ?? base.summary;
    final focusWords =
        (payload['focus_words'] as List<dynamic>? ?? base.focusWords)
            .map((e) => e.toString())
            .toList();
    final estimatedMinutes =
        (payload['estimated_minutes'] as num?)?.toInt() ?? base.durationMinutes;
    final readingLevel = payload['reading_level'] as int? ?? base.readingLevel;

    final metadata = Map<String, dynamic>.from(base.chapter.metadata ?? {});
    metadata['last_revision_model'] = modelUsed;
    metadata['last_revision_at'] = DateTime.now().toIso8601String();

    final chapter = StoryChapter(
      id: base.chapter.id,
      title: title,
      beats: beats,
      choicePoints: choicePoints,
      metadata: metadata,
    );

    final band = ReadingLevelHelper.bandForLevel(readingLevel);
    final familiarityStats = _computeFamiliarity(chapter, band);

    return base.copyWith(
      chapter: chapter,
      summary: summary,
      readingLevel: readingLevel,
      durationMinutes: estimatedMinutes,
      focusWords: focusWords,
      familiarWordRatio: familiarityStats.ratio,
      familiarWordCount: familiarityStats.familiarCount,
      totalWordCount: familiarityStats.totalWords,
      model: modelUsed,
    );
  }

  List<StoryBeat> _parseBeats(dynamic beatsJson) {
    final beatsList = (beatsJson as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>?>();
    return beatsList.asMap().entries.map((entry) {
      final beat = entry.value ?? {};
      return StoryBeat(
        id: beat['id']?.toString().isNotEmpty == true
            ? beat['id'].toString()
            : 'beat_${entry.key + 1}',
        type: _parseBeatType(beat['type']),
        text: beat['text']?.toString() ?? '',
        speaker: _parseSpeaker(beat['speaker']),
        targetWords: (beat['target_words'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        coachPhrase: beat['coach_phrase']?.toString(),
      );
    }).toList();
  }

  List<ChoicePoint> _parseChoicePoints(dynamic choiceJson) {
    final list = (choiceJson as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>?>();
    return list.map((choice) {
      final choices = (choice?['choices'] as List<dynamic>? ?? [])
          .map((c) => c as Map<String, dynamic>? ?? {})
          .toList();
      return ChoicePoint(
        id:
            choice?['id']?.toString() ??
            'choice_${DateTime.now().millisecondsSinceEpoch}',
        beatIndex: (choice?['beat_index'] as num?)?.toInt() ?? 0,
        promptText: choice?['prompt_text']?.toString() ?? '',
        choices: choices
            .map(
              (c) => StoryChoice(
                id:
                    c['id']?.toString() ??
                    'choice_option_${Random().nextInt(9999)}',
                previewText: c['preview_text']?.toString() ?? '',
                choiceText: c['choice_text']?.toString() ?? '',
              ),
            )
            .toList(),
      );
    }).toList();
  }

  List<StoryBeat> _beatsFromRawText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final segments = normalized
        .split(RegExp(r'\n{2,}'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      segments.add(normalized);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return segments.asMap().entries.map((entry) {
      return StoryBeat(
        id: 'edited_${timestamp}_${entry.key + 1}',
        type: BeatType.narration,
        text: entry.value,
        speaker: Speaker.parent,
      );
    }).toList();
  }

  _FamiliarityStats _computeFamiliarity(
    StoryChapter chapter,
    ReadingBand readingBand,
  ) {
    final vocab = ReadingLevelHelper.vocabularyForBand(
      readingBand,
    ).map((w) => w.toLowerCase()).toSet();
    final words = chapter.beats
        .expand(
          (beat) => beat.text
              .replaceAll(RegExp(r"[^\w\s']"), '')
              .toLowerCase()
              .split(RegExp(r'\s+')),
        )
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

  /// Generate panel art for a story.
  /// 
  /// This method performs the full panel art generation flow:
  /// 1. Extract character descriptions
  /// 2. Generate panel descriptions
  /// 3. Generate panel art grid
  /// 4. Slice and save panels
  /// 
  /// [story] - The story record to generate art for
  /// [childAge] - Optional child age for style description
  /// [onProgress] - Optional callback for progress updates
  Future<StoryPanelArtMetadata> generatePanelArt(
    GeneratedStoryRecord story, {
    int? childAge,
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('Extracting characters...');
    
    // Step 1: Extract character descriptions
    final storyText = StoryTextUtils.narrationOnly(story.chapter);
    final characterDescriptions = await _extractCharacters(storyText);
    
    onProgress?.call('Writing panel descriptions...');
    
    // Step 2: Generate panel descriptions
    final panelDescriptions = await _generatePanelDescriptions(
      storyText,
      characterDescriptions,
    );
    
    onProgress?.call('Painting panels...');
    
    // Step 3: Generate panel art grid
    final panelCount = panelDescriptions.length;
    final styleDescription = _buildStyleDescription(childAge);
    final panelArtPrompt = _buildPanelArtPrompt(
      panelCount: panelCount,
      panelDescriptions: panelDescriptions,
      styleDescription: styleDescription,
    );
    
    final imageResult = await _imageClient.generateImage(
      prompt: panelArtPrompt,
      modelId: OpenRouterImageClient.panelModel,
      aspectRatio: '1:1',
      systemPrompt: panelArtPrompt,
    );
    
    onProgress?.call('Slicing artwork...');
    
    // Step 4: Save and slice the grid
    final tempDir = await _getTempDirectory();
    final gridPath = await _imageClient.saveImageFromDataUrl(
      dataUrl: imageResult.imageDataUrl,
      fileName: 'panel_grid_${story.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      directory: tempDir.path,
    );
    
    // Slice the grid into individual panels using existing processing logic
    final batchDir = await _createBatchDirectory(story.id);
    final panelArtService = StoryPanelArtService();
    
    final panelPaths = await panelArtService.processPanelGrid(
      gridImagePath: gridPath,
      outputDir: batchDir.path,
      panelCount: panelCount,
    );
    
    // Create metadata
    final estimatedCols = sqrt(panelCount).ceil();
    final estimatedRows = (panelCount / estimatedCols).ceil();
    
    final metadata = StoryPanelArtMetadata(
      columns: estimatedCols,
      rows: estimatedRows,
      panelImagePaths: panelPaths,
      sheetImagePath: gridPath,
      importedAt: DateTime.now(),
      assignments: _createDefaultAssignments(panelCount, panelPaths),
    );
    
    // Save to story
    await updateStoryPanelArt(story.id, metadata);
    
    onProgress?.call('Done!');
    
    return metadata;
  }

  /// Generate cover art for a story.
  /// 
  /// [story] - The story record to generate cover for
  /// [panelArtImagePath] - Optional path to panel art grid (for visual reference)
  /// [childAge] - Optional child age for style description
  /// [onProgress] - Optional callback for progress updates
  Future<String> generateCoverArt(
    GeneratedStoryRecord story, {
    String? panelArtImagePath,
    int? childAge,
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('Creating cover art...');
    
    final storyText = StoryTextUtils.narrationOnly(story.chapter);
    final coverPrompt = _buildCoverArtPrompt(
      story: story,
      storyText: storyText,
      childAge: childAge,
      hasPanelArt: panelArtImagePath != null,
    );
    
    final String coverPath;
    
    if (panelArtImagePath != null) {
      // Generate with panel art as reference
      final imageResult = await _imageClient.generateImageWithInput(
        prompt: coverPrompt,
        imagePath: panelArtImagePath,
        modelId: OpenRouterImageClient.coverModel,
        aspectRatio: '3:4',
        systemPrompt: coverArtPromptWithPanelArt,
      );
      
      final coversDir = await _getCoversDirectory();
      coverPath = await _imageClient.saveImageFromDataUrl(
        dataUrl: imageResult.imageDataUrl,
        fileName: 'cover_${story.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        directory: coversDir.path,
      );
    } else {
      // Generate without panel art
      final imageResult = await _imageClient.generateImage(
        prompt: coverPrompt,
        modelId: OpenRouterImageClient.coverModel,
        aspectRatio: '3:4',
        systemPrompt: coverArtPromptWithoutPanelArt,
      );
      
      final coversDir = await _getCoversDirectory();
      coverPath = await _imageClient.saveImageFromDataUrl(
        dataUrl: imageResult.imageDataUrl,
        fileName: 'cover_${story.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        directory: coversDir.path,
      );
    }
    
    // Save to story
    await updateStoryCover(story.id, coverPath);
    
    onProgress?.call('Done!');
    
    return coverPath;
  }

  Future<String> _extractCharacters(String storyText) async {
    final result = await _callTextModel(
      systemPrompt: characterExtractionPrompt,
      userPrompt: storyText,
      temperature: 0.3,
      maxOutputTokens: 1024,
    );
    
    return result;
  }

  Future<List<String>> _generatePanelDescriptions(
    String storyText,
    String characterDescriptions,
  ) async {
    final userPrompt = 'CHARACTER DESCRIPTIONS:\n$characterDescriptions\n\nSTORY TEXT:\n$storyText';
    
    final result = await _callTextModel(
      systemPrompt: panelDescriptionPrompt,
      userPrompt: userPrompt,
      temperature: 0.7,
      maxOutputTokens: 4096,
    );
    
    // Parse panel descriptions (assume they're numbered: Panel 1, Panel 2, etc.)
    final panels = <String>[];
    final lines = result.split('\n');
    String? currentPanel;
    
    for (final line in lines) {
      if (line.trim().toLowerCase().startsWith(RegExp(r'panel \d+'))) {
        if (currentPanel != null && currentPanel.trim().isNotEmpty) {
          panels.add(currentPanel.trim());
        }
        currentPanel = line.trim();
      } else if (currentPanel != null) {
        currentPanel += '\n$line';
      }
    }
    
    if (currentPanel != null && currentPanel.trim().isNotEmpty) {
      panels.add(currentPanel.trim());
    }
    
    // Fallback: if no panels found, split by double newlines
    if (panels.isEmpty) {
      final paragraphs = result.split(RegExp(r'\n{2,}'));
      panels.addAll(paragraphs.where((p) => p.trim().isNotEmpty));
    }
    
    // Ensure we have at least one panel
    if (panels.isEmpty) {
      panels.add(result.trim());
    }
    
    return panels;
  }

  /// Call OpenRouter for text generation (not JSON).
  Future<String> _callTextModel({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
    int maxOutputTokens = 2048,
  }) async {
    final apiKey = _getApiKey();
    if (apiKey.isEmpty) {
      throw StateError('OPENROUTER_API_KEY missing');
    }

    final body = {
      'model': StoryGenerationDefaults.primaryModelId,
      'temperature': temperature,
      'top_p': 0.9,
      'max_output_tokens': maxOutputTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };

    AppLogger.system.d('Calling OpenRouter for text generation');

    final httpClient = http.Client();
    final response = await httpClient.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://xen.words.app/dev',
        'X-Title': 'Xen Words',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      AppLogger.system.e('OpenRouter error: ${response.statusCode} ${response.body}');
      throw Exception('OpenRouter API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw StateError('OpenRouter returned no choices');
    }

    final content = choices.first['message']['content'];
    final contentString = content is List
        ? content.map((e) => e['text'] ?? '').join('\n')
        : content?.toString() ?? '';

    httpClient.close();
    return contentString;
  }

  String _getApiKey() {
    final localKey = local_secret.openRouterApiKey.trim();
    if (localKey.isNotEmpty) {
      return localKey;
    }
    return const String.fromEnvironment('OPENROUTER_API_KEY');
  }

  String _buildStyleDescription(int? childAge) {
    final ageText = childAge != null ? 'age-appropriate for $childAge years old' : 'age-appropriate';
    return 'Whimsical children\'s book illustration style, vibrant colors, soft lighting, $ageText, warm and engaging';
  }

  String _buildPanelArtPrompt({
    required int panelCount,
    required List<String> panelDescriptions,
    required String styleDescription,
  }) {
    final panelList = panelDescriptions
        .asMap()
        .entries
        .map((e) => 'Panel ${e.key + 1}:\n${e.value}')
        .join('\n\n');
    
    return panelArtPrompt
        .replaceAll('[N]', panelCount.toString())
        .replaceAll('[ART_STYLE_DESCRIPTION]', styleDescription)
        .replaceAll('[PANEL_LIST]', panelList);
  }

  String _buildCoverArtPrompt({
    required GeneratedStoryRecord story,
    required String storyText,
    int? childAge,
    required bool hasPanelArt,
  }) {
    final ageText = childAge != null ? childAge.toString() : '5-8';
    
    if (hasPanelArt) {
      return coverArtPromptWithPanelArt
          .replaceAll('[STORY_TITLE]', story.chapter.title)
          .replaceAll('[STORY_SUMMARY]', story.summary)
          .replaceAll('[CHILD_AGE]', ageText);
    } else {
      return coverArtPromptWithoutPanelArt
          .replaceAll('[STORY_TITLE]', story.chapter.title)
          .replaceAll('[STORY_SUMMARY]', story.summary)
          .replaceAll('[FULL_STORY_TEXT]', storyText)
          .replaceAll('[CHILD_AGE]', ageText)
          .replaceAll('[CHARACTER_DESCRIPTIONS]', '');
    }
  }


  Map<int, String> _createDefaultAssignments(int panelCount, List<String> panelPaths) {
    final assignments = <int, String>{};
    for (int i = 0; i < panelCount && i < panelPaths.length; i++) {
      assignments[i] = panelPaths[i];
    }
    return assignments;
  }

  Future<Directory> _getTempDirectory() async {
    final dir = Directory.systemTemp;
    final tempDir = Directory('${dir.path}/xen_words_art');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  Future<Directory> _getCoversDirectory() async {
    final docs = await _getApplicationDocumentsDirectory();
    final coversDir = Directory('${docs.path}/story_covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir;
  }

  Future<Directory> _createBatchDirectory(String storyId) async {
    final docs = await _getApplicationDocumentsDirectory();
    final base = Directory('${docs.path}/story_panels/$storyId');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    final batchDir = Directory(
      '${base.path}/${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!await batchDir.exists()) {
      await batchDir.create(recursive: true);
    }
    return batchDir;
  }

  Future<Directory> _getApplicationDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
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

  factory _FamiliarityStats.zero() =>
      const _FamiliarityStats(familiarCount: 0, totalWords: 0, ratio: 0);
}

class StoryRevisionDraft {
  final GeneratedStoryRecord record;
  final String modelId;
  final String instructions;

  StoryRevisionDraft({
    required this.record,
    required this.modelId,
    required this.instructions,
  });
}
