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
You are a story generation assistant for an early-literacy reading coach.
- Craft bedtime stories for parents to read aloud.
- Maintain ${request.readingLevel == 2 ? 'Reading Level 2' : 'Reading Level ${request.readingLevel}'} vocabulary coverage with a high percentage of Dolch-style sight words.
- Include occasional challenge words so parents can introduce new vocabulary.
- Identify moments for coach guidance where the child practices a focus word.
- Output JSON only. No markdown fences or commentary.
    '''
        .trim();

    final userPrompt = jsonEncode({
      'reading_level': request.readingLevel,
      'child_name': request.childName,
      'target_minutes': request.durationMinutes,
      'parent_prompt': request.parentPrompt,
      'child_context': request.childContext,
      'story_concept': request.storyConcept,
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

  Future<Map<String, dynamic>> _callModel({
    required String apiKey,
    required String modelId,
    required String systemPrompt,
    required List<String> vocabulary,
    required StoryGenerationRequest request,
    required String userPrompt,
    required Map<String, dynamic> bandMap,
  }) async {
    final body = {
      'model': modelId,
      'temperature': 0.85,
      'top_p': 0.9,
      'max_output_tokens': 2048,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': '''
Fill this schema and respond with JSON (no markdown fences):
{
  "title": "string",
  "summary": "2 sentence summary",
  "estimated_minutes": ${request.durationMinutes},
  "reading_level": ${request.readingLevel},
  "focus_words": ["${vocabulary.take(6).join('","')}"],
  "beats": [
    {
      "id": "beat_1",
      "type": "narration | child_turn | coach_intervention | celebration",
      "speaker": "parent | coach | child",
      "text": "string",
      "target_words": ["optional familiar word"],
      "coach_phrase": "optional coaching language"
    }
  ],
  "choice_points": [
    {
      "id": "choice_1",
      "beat_index": 3,
      "prompt_text": "question for the child",
      "choices": [
        {"id": "choice_1a", "preview_text": "option", "choice_text": "full option"}
      ]
    }
  ],
  "metadata": {
    "tone": "adventurous",
    "themes": ["courage", "friendship"],
    "official_reading_band": ${jsonEncode(bandMap)}
  }
}

Story config: $userPrompt
Reading band guidance: ${jsonEncode(bandMap)}
Familiar words to prioritize: ${jsonEncode(vocabulary)}
Child name included: ${request.includeChildName ? 'yes' : 'no'}
Optional child personalization: ${request.childContext}
${request.storyConcept != null ? 'Parent concept: ${request.storyConcept}' : ''}
''',
        },
      ],
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
}

