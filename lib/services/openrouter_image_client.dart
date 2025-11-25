import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../secrets/openrouter_secret.dart' as local_secret;
import '../utils/app_logger.dart';

/// Result of an image generation request.
class OpenRouterImageResult {
  final String imageDataUrl; // Base64 data URL
  final String modelId;

  OpenRouterImageResult({
    required this.imageDataUrl,
    required this.modelId,
  });
}

/// Client for generating images via OpenRouter API.
class OpenRouterImageClient {
  OpenRouterImageClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _referer = 'https://xen.words.app/dev';
  static const _title = 'Xen Words';

  // Model constants (defaults; user-selectable in Story Time settings)
  static const String coverModel = 'google/gemini-2.5-flash-image';
  static const String panelModel = 'qwen/qwen3-vl-30b-a3b-instruct';

  String get _apiKey {
    final localKey = local_secret.openRouterApiKey.trim();
    if (localKey.isNotEmpty) {
      return localKey;
    }
    return const String.fromEnvironment('OPENROUTER_API_KEY');
  }

  /// Generate an image from a text prompt.
  /// 
  /// [prompt] - The text prompt describing the image to generate
  /// [modelId] - The model to use (defaults to coverModel)
  /// [aspectRatio] - Aspect ratio for the image (e.g., "1:1", "3:4")
  /// [systemPrompt] - Optional system prompt to guide the model
  Future<OpenRouterImageResult> generateImage({
    required String prompt,
    String? modelId,
    String? aspectRatio,
    String? systemPrompt,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'OPENROUTER_API_KEY missing. Either set --dart-define=OPENROUTER_API_KEY or edit lib/secrets/openrouter_secret.dart.',
      );
    }

    final model = modelId ?? coverModel;
    final messages = <Map<String, dynamic>>[];

    if (systemPrompt != null) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    messages.add({'role': 'user', 'content': prompt});

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'modalities': ['image', 'text'],
    };

    if (aspectRatio != null) {
      body['image_config'] = {'aspect_ratio': aspectRatio};
    }
    final promptChars = prompt.length;
    final approxInputTokens = (promptChars / 4).round();
    final start = DateTime.now();
    if (AppLogger.enableGenAiLogging) {
      AppLogger.genai.progress(
        'Image request → model=$model aspect=$aspectRatio '
        'chars=$promptChars approxTokens=$approxInputTokens',
      );
      if (AppLogger.enableGenAiVerbose) {
        AppLogger.genai.i(
          'IMAGE SYSTEM PROMPT (model=$model):\n${systemPrompt ?? '(none)'}',
        );
        AppLogger.genai.i(
          'IMAGE USER PROMPT (model=$model):\n$prompt',
        );
      }
    } else {
      AppLogger.system.d('Generating image with model $model');
    }

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
      AppLogger.system.e('OpenRouter image error: ${response.statusCode} ${response.body}');
      throw Exception('OpenRouter API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw StateError('OpenRouter returned no choices');
    }

    final message = choices.first['message'] as Map<String, dynamic>;
    final images = message['images'] as List<dynamic>? ?? [];
    if (images.isEmpty) {
      throw StateError('OpenRouter returned no images');
    }

    final imageData = images.first as Map<String, dynamic>;
    final imageUrl = imageData['image_url'] as Map<String, dynamic>;
    final dataUrl = imageUrl['url'] as String;
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    if (AppLogger.enableGenAiLogging) {
      AppLogger.genai.success(
        'Image response ← model=$model elapsed=${elapsedMs}ms '
        'dataUrlLen=${dataUrl.length}',
      );
      if (AppLogger.enableGenAiVerbose) {
        AppLogger.genai.i(
          'IMAGE DATA URL (model=$model, length=${dataUrl.length}):\n$dataUrl',
        );
      }
    }

    return OpenRouterImageResult(imageDataUrl: dataUrl, modelId: model);
  }

  /// Generate an image from a text prompt with an image input (multimodal).
  /// 
  /// [prompt] - The text prompt describing the image to generate
  /// [imagePath] - Path to the input image file
  /// [modelId] - The model to use (defaults to coverModel)
  /// [aspectRatio] - Aspect ratio for the image (e.g., "1:1", "3:4")
  /// [systemPrompt] - Optional system prompt to guide the model
  Future<OpenRouterImageResult> generateImageWithInput({
    required String prompt,
    required String imagePath,
    String? modelId,
    String? aspectRatio,
    String? systemPrompt,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'OPENROUTER_API_KEY missing. Either set --dart-define=OPENROUTER_API_KEY or edit lib/secrets/openrouter_secret.dart.',
      );
    }

    // Read and encode the input image as base64
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw FileSystemException('Input image file not found: $imagePath');
    }

    final imageBytes = await imageFile.readAsBytes();
    final imageBase64 = base64Encode(imageBytes);
    
    // Determine MIME type from file extension
    final extension = imagePath.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg', // default
    };
    
    final imageDataUrl = 'data:$mimeType;base64,$imageBase64';

    final model = modelId ?? coverModel;
    final messages = <Map<String, dynamic>>[];

    if (systemPrompt != null) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    // Create multimodal message with image and text
    messages.add({
      'role': 'user',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': imageDataUrl},
        },
        {
          'type': 'text',
          'text': prompt,
        },
      ],
    });

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'modalities': ['image', 'text'],
    };

    if (aspectRatio != null) {
      body['image_config'] = {'aspect_ratio': aspectRatio};
    }
    final promptChars = prompt.length;
    final approxInputTokens = (promptChars / 4).round();
    final start = DateTime.now();
    if (AppLogger.enableGenAiLogging) {
      AppLogger.genai.progress(
        'Image+input request → model=$model aspect=$aspectRatio '
        'chars=$promptChars approxTokens=$approxInputTokens '
        'imageBytes=${imageBytes.length}',
      );
      if (AppLogger.enableGenAiVerbose) {
        AppLogger.genai.i(
          'IMAGE+INPUT SYSTEM PROMPT (model=$model):\n${systemPrompt ?? '(none)'}',
        );
        AppLogger.genai.i(
          'IMAGE+INPUT USER PROMPT (model=$model):\n$prompt',
        );
      }
    } else {
      AppLogger.system.d('Generating image with input using model $model');
    }

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
      AppLogger.system.e('OpenRouter image error: ${response.statusCode} ${response.body}');
      throw Exception('OpenRouter API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw StateError('OpenRouter returned no choices');
    }

    final message = choices.first['message'] as Map<String, dynamic>;
    final images = message['images'] as List<dynamic>? ?? [];
    if (images.isEmpty) {
      throw StateError('OpenRouter returned no images');
    }

    final imageData = images.first as Map<String, dynamic>;
    final imageUrl = imageData['image_url'] as Map<String, dynamic>;
    final dataUrl = imageUrl['url'] as String;
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    if (AppLogger.enableGenAiLogging) {
      AppLogger.genai.success(
        'Image+input response ← model=$model elapsed=${elapsedMs}ms '
        'dataUrlLen=${dataUrl.length}',
      );
      if (AppLogger.enableGenAiVerbose) {
        AppLogger.genai.i(
          'IMAGE+INPUT DATA URL (model=$model, length=${dataUrl.length}):\n$dataUrl',
        );
      }
    }

    return OpenRouterImageResult(imageDataUrl: dataUrl, modelId: model);
  }

  /// Save a base64 data URL image to a local file.
  /// 
  /// Returns the path to the saved file.
  Future<String> saveImageFromDataUrl({
    required String dataUrl,
    required String fileName,
    String? directory,
  }) async {
    // Parse data URL: data:image/png;base64,<base64data>
    if (!dataUrl.startsWith('data:')) {
      throw FormatException('Invalid data URL format');
    }

    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1) {
      throw FormatException('Invalid data URL format: no comma found');
    }

    final base64Data = dataUrl.substring(commaIndex + 1);
    final imageBytes = base64Decode(base64Data);

    Directory targetDir;
    if (directory != null) {
      targetDir = Directory(directory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
    } else {
      targetDir = await getApplicationDocumentsDirectory();
    }

    final file = File('${targetDir.path}/$fileName');
    await file.writeAsBytes(imageBytes);

    AppLogger.system.d('Saved image to ${file.path}');
    return file.path;
  }

  void dispose() {
    _client.close();
  }
}

