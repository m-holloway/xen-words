import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/story_generation_models.dart';
import '../secrets/openrouter_secret.dart' as local_secret;
import '../utils/app_logger.dart';
import '../utils/reading_level_helper.dart';

class OpenRouterStoryResult {
  final Map<String, dynamic> payload;
  final String modelId;

  OpenRouterStoryResult({
    required this.payload,
    required this.modelId,
  });
}

class OpenRouterStoryClient {
  OpenRouterStoryClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _referer = 'https://xen.words.app/dev';
  static const _title = 'Xen Words';

  String get _apiKey {
    final localKey = local_secret.openRouterApiKey.trim();
    if (localKey.isNotEmpty) {
      return localKey;
    }
    return const String.fromEnvironment('OPENROUTER_API_KEY');
  }

  String get _primaryModelOverride {
    final localModel = local_secret.openRouterPrimaryModelOverride?.trim() ?? '';
    return localModel.isNotEmpty ? localModel : StoryGenerationDefaults.primaryModelId;
  }

  String get _fallbackModelOverride {
    final localFallback = local_secret.openRouterFallbackModelOverride?.trim() ?? '';
    return localFallback.isNotEmpty ? localFallback : StoryGenerationDefaults.fallbackModelId;
  }

  Future<OpenRouterStoryResult> generateStoryPayload(StoryGenerationRequest request) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'OPENROUTER_API_KEY missing. Either set --dart-define=OPENROUTER_API_KEY or edit lib/secrets/openrouter_secret.dart.',
      );
    }

    final vocabulary = ReadingLevelHelper.vocabularyForBand(request.readingBand);

    final systemPrompt = '''
You are a master storyteller in the tradition of Arnold Lobel, Beatrix Potter, and Maurice Sendak—a weaver of bedtime tales that children beg to hear again and again.

Your gift is transforming even the simplest seed of an idea into a captivating journey. When a parent says "a story about a turtle," you don't just write about a turtle—you craft a world where that turtle has personality, quirks, and a problem that matters. You make children FEEL the cool mud between the turtle's toes, HEAR the plop of water, WONDER what's around the next bend.

Core Craft Principles:
• CHARACTER OVER CONCEPT: Even simple creatures have personality. Give them voice, motivation, distinct traits. A grumpy hedgehog, a curious beetle, a brave but clumsy rabbit. Make us CARE in the first paragraph.

• SENSORY IMMERSION: Children live through their senses. Paint with specific details—not "the forest" but "moss soft as kitten fur," not "it was dark" but "shadows stretched like reaching fingers." Make it VIVID.

• EMOTIONAL ARC: Every great story is a journey from one feeling to another. Start with a relatable emotion (worry, curiosity, loneliness, excitement), build gentle tension, resolve with warmth. The child should feel satisfied, not just informed.

• SHOW, DON'T TELL: Never say "she was brave." Show her hands trembling as she takes the first step into the dark cave. Trust your young reader to understand.

• PACING & RHYTHM: Read-aloud magic lives in the cadence. Vary sentence length. Use repetition for comfort ("One step. Two steps. Three careful steps."). Build to moments of "what happens next?" then release to "ahhhh."

• STAKES THAT MATTER: The problem doesn't need to be big—lost mittens, a stuck acorn, finding the courage to try. But it must matter to THIS character. Make us root for them.

• DELIGHT IN LANGUAGE: You're writing for Reading Level ${request.readingLevel}, but that doesn't mean flat prose. Use the vocabulary available to you with JOY. Embrace repetition, alliteration, playful rhythms. Make words dance while staying accessible.

• SATISFYING ENDINGS: Children crave resolution. Don't end abruptly. Give us a moment to breathe, a sense of completion, a echo of warmth. Let us close the book feeling cozy.

Vocabulary Guidance:
You're writing for children at Level ${request.readingLevel} (${request.readingBand.gradeBand}). The available vocabulary includes familiar words they know plus a few "stretch words" to grow on. Use this vocabulary as your PALETTE, not your PRISON. The best children's writers work within constraints to create art.

Include 85-90% familiar words so children can flow through the story with confidence. Sprinkle in 4-6 new or challenging words that context makes clear—these are gifts of language, chances to grow.

Technical Notes:
• Target ${request.durationMinutes} minutes of read-aloud time (roughly ${(request.durationMinutes * 150 * 0.9).round()}-${(request.durationMinutes * 150 * 1.1).round()} words)
• Break the narrative into natural story "beats"—scenes or moments where something shifts
• Output JSON only, no markdown fences or commentary

Your mission: Transform their simple prompt into a story that makes bedtime magical. Expand, enhance, and ENCHANT.
    '''
        .trim();

    final userPrompt = jsonEncode({
      'reading_level': request.readingLevel,
      'child_name': request.childName,
      'target_minutes': request.durationMinutes,
      'parent_prompt': request.parentPrompt,
      'child_context': request.childContext,
      'story_concept': request.storyConcept,
      'profile_id': request.profileId,
      'cast_context': request.castContext,
      'cast_character_ids': request.castCharacterIds,
      'familiar_words': vocabulary,
      'instructions': 'Return JSON with title, summary, focus_words, beats, and optional choice_points.',
    });

    final bandMap = request.readingBand.toJson();

    final modelsToTry = <String>{
      if (request.model.trim().isNotEmpty) request.model.trim(),
      _primaryModelOverride,
      _fallbackModelOverride,
    }.where((m) => m.isNotEmpty).toList();

    Exception? lastError;
    for (final modelId in modelsToTry) {
      try {
        final payload = await _callModel(
          apiKey: apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          vocabulary: vocabulary,
          request: request,
          userPrompt: userPrompt,
          bandMap: bandMap,
        );
        return OpenRouterStoryResult(payload: payload, modelId: modelId);
      } catch (e, stack) {
        lastError = e is Exception ? e : Exception(e.toString());
        AppLogger.system
            .w('OpenRouter model $modelId failed, trying fallback...', error: e, stackTrace: stack);
      }
    }

    throw lastError ??
        Exception('All OpenRouter models failed (${modelsToTry.join(', ')}). Please try again.');
  }

  Future<OpenRouterStoryResult> reviseStoryPayload({
    required GeneratedStoryRecord story,
    required String instructions,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'OPENROUTER_API_KEY missing. Either set --dart-define=OPENROUTER_API_KEY or edit lib/secrets/openrouter_secret.dart.',
      );
    }

    final sanitizedInstructions = instructions.trim();
    if (sanitizedInstructions.isEmpty) {
      throw ArgumentError('Revision instructions cannot be empty.');
    }

    final systemPrompt = '''
You are a meticulous story editor working alongside a parent to refine their child's bedtime story.

Your role is surgical and respectful:
• Make ONLY the changes the parent requests—no more, no less
• Preserve the heart of the story: its characters, voice, tone, emotional arc
• Maintain the reading level and vocabulary constraints of the original
• Keep the same story structure (number of beats, overall flow) unless specifically asked to change it
• If asked to "make it funnier" or "add more description," enhance what's there—don't rewrite from scratch

Think of yourself as a gentle editor with a red pen, not a co-author rewriting the tale. The original storyteller did good work; you're polishing specific facets they've identified.

Output: Return the full revised story in the same JSON schema as the original. Respond with JSON only—no commentary or markdown fences.
    '''
        .trim();

    final originalPayload = _storyPayloadForRevision(story);
    final userPrompt = '''
Original story (JSON):
${jsonEncode(originalPayload)}

Revision request:
"$sanitizedInstructions"

Return the revised story JSON. Retain fields that are untouched by the revision.
    '''
        .trim();

    final modelsToTry = <String>{
      story.model.trim(),
      _primaryModelOverride,
      _fallbackModelOverride,
    }.where((m) => m.isNotEmpty).toList();

    Exception? lastError;
    for (final modelId in modelsToTry) {
      try {
        final payload = await _callModelWithMessages(
          apiKey: apiKey,
          modelId: modelId,
          messages: [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          temperature: 0.4,
          maxOutputTokens: 2048,
        );
        return OpenRouterStoryResult(payload: payload, modelId: modelId);
      } catch (e, stack) {
        lastError = e is Exception ? e : Exception(e.toString());
        AppLogger.system
            .w('OpenRouter revision model $modelId failed, trying fallback...', error: e, stackTrace: stack);
      }
    }

    throw lastError ??
        Exception('All OpenRouter revision models failed (${modelsToTry.join(', ')}). Please try again.');
  }

  Future<Map<String, dynamic>> _callModel({
    required String apiKey,
    required String modelId,
    required String systemPrompt,
    required List<String> vocabulary,
    required StoryGenerationRequest request,
    required String userPrompt,
    required Map<String, dynamic> bandMap,
  }) async {
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': '''
THE STORY REQUEST:
Parent's idea: "${request.parentPrompt}"
${request.storyConcept != null ? 'Story scenario: "${request.storyConcept}"\n' : ''}
Child personalization notes: "${request.childContext}"
${request.includeChildName && request.childName != null ? 'Child\'s name: ${request.childName} (weave naturally into the story)\n' : ''}
${request.castContext != null && request.castContext!.trim().isNotEmpty ? 'Story Friends to include (from the child\'s Story World):\n${request.castContext!.trim()}\n\n' : ''}

VOCABULARY PALETTE:
Familiar words for this level: ${vocabulary.take(40).join(', ')}
(Use these as your primary vocabulary—they should make up 85-90% of your words)

OUTPUT FORMAT (JSON, no markdown):
{
  "title": "An evocative, child-friendly title that sparks curiosity",
  "summary": "2-3 sentences capturing the heart of the story—what it's ABOUT emotionally, not just plot",
  "estimated_minutes": ${request.durationMinutes},
  "reading_level": ${request.readingLevel},
  "focus_words": ["4-6 new/stretch words that appear in the story—words that context makes learnable"],
  "beats": [
    {
      "id": "beat_1",
      "type": "narration",
      "text": "A paragraph or two of story narrative. Each beat is a natural story moment—a scene, a shift, a development. Break the story into 8-15 beats for pacing and read-aloud flow."
    }
  ],
  "metadata": {
    "tone": "warm, adventurous, gentle, mysterious, playful—whatever fits YOUR story",
    "themes": ["friendship", "courage", "curiosity", "kindness"—the emotional themes],
    "child_name": ${request.includeChildName && request.childName != null ? '"${request.childName}"' : 'null'},
    "official_reading_band": ${jsonEncode(bandMap)}
  }
}

Remember: The parent's prompt is a SEED. Your job is to grow it into something magical. If they say "a turtle," give us a turtle with personality, a problem, a journey, and a satisfying resolution. Make it SING.
''',
      },
    ];

    return _callModelWithMessages(
      apiKey: apiKey,
      modelId: modelId,
      messages: messages,
      temperature: 0.85,
      maxOutputTokens: 2048,
    );
  }

  void dispose() {
    _client.close();
  }

  String _extractFirstJsonObject(String text) {
    final sanitized = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    final start = sanitized.indexOf('{');
    final end = sanitized.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw FormatException('No JSON object found in response.');
    }
    return sanitized.substring(start, end + 1);
  }

  Future<Map<String, dynamic>> _callModelWithMessages({
    required String apiKey,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    double topP = 0.9,
    int maxOutputTokens = 2048,
  }) async {
    final body = {
      'model': modelId,
      'temperature': temperature,
      'top_p': topP,
      'max_output_tokens': maxOutputTokens,
      'messages': messages,
    };

    AppLogger.system.d('Calling OpenRouter with model $modelId');

    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': _referer,
        'X-Title': _title,
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

    final extracted = _extractFirstJsonObject(contentString);
    return jsonDecode(extracted) as Map<String, dynamic>;
  }

  Map<String, dynamic> _storyPayloadForRevision(GeneratedStoryRecord story) {
    final chapterJson = story.chapter.toJson();
    return {
      'title': chapterJson['title'],
      'summary': story.summary,
      'estimated_minutes': story.durationMinutes,
      'reading_level': story.readingLevel,
      'focus_words': story.focusWords,
      'beats': chapterJson['beats'],
      'choice_points': chapterJson['choice_points'],
      'metadata': chapterJson['metadata'],
    };
  }
}

