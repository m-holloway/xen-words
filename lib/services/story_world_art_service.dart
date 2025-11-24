import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/story_world_models.dart';
import '../utils/app_logger.dart';
import 'openrouter_image_client.dart';
import 'story_world_service.dart';

/// Helper for generating Story World artwork (e.g., character portraits)
/// using the existing OpenRouter image client.
class StoryWorldArtService {
  StoryWorldArtService({
    OpenRouterImageClient? imageClient,
    StoryWorldService? worldService,
  })  : _imageClient = imageClient ?? OpenRouterImageClient(),
        _worldService = worldService ?? StoryWorldService.instance;

  final OpenRouterImageClient _imageClient;
  final StoryWorldService _worldService;

  /// Generate or refresh a hero portrait for a Story Friend (character).
  ///
  /// [profileId] is used to locate the correct Story World graph.
  /// [referenceDrawing] can optionally provide a child-drawn image as
  /// inspiration for the AI model.
  Future<StoryCharacterEntity> generateCharacterPortrait({
    required String profileId,
    required StoryCharacterEntity character,
    StoryDrawingEntity? referenceDrawing,
    int? childAge,
  }) async {
    final prompt = _buildCharacterArtPrompt(
      character: character,
      childAge: childAge,
    );

    final directory = await _getCharactersDirectory();
    final fileName =
        'character_${character.id}_${DateTime.now().millisecondsSinceEpoch}.png';

    try {
      AppLogger.system.d(
        'Generating portrait for Story Friend ${character.id} (${character.displayName})',
      );

      final hasRealPhoto = character.realPhotoPath != null &&
          character.realPhotoPath!.trim().isNotEmpty;

      final imageResult = hasRealPhoto
          ? await _imageClient.generateImageWithInput(
              prompt: prompt,
              imagePath: character.realPhotoPath!,
              modelId: OpenRouterImageClient.coverModel,
              aspectRatio: '3:4',
              systemPrompt:
                  'You are illustrating a childrens book character using the provided real-life photo as reference. Preserve key identity features while rendering in a child-friendly illustration style.',
            )
          : referenceDrawing != null
              ? await _imageClient.generateImageWithInput(
                  prompt: prompt,
                  imagePath: referenceDrawing.imagePath,
                  modelId: OpenRouterImageClient.coverModel,
                  aspectRatio: '3:4',
                  systemPrompt:
                      'You are illustrating a childrens book character based on a child\'s drawing.',
                )
              : await _imageClient.generateImage(
                  prompt: prompt,
                  modelId: OpenRouterImageClient.coverModel,
                  aspectRatio: '3:4',
                  systemPrompt:
                      'You are illustrating a friendly childrens book character for ages 4-8.',
                );

      final savedPath = await _imageClient.saveImageFromDataUrl(
        dataUrl: imageResult.imageDataUrl,
        fileName: fileName,
        directory: directory.path,
      );

      final updated = character.copyWith(
        heroPortraitPath: savedPath,
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertCharacter(
        profileId: profileId,
        character: updated,
      );
      return updated;
    } catch (e) {
      AppLogger.system.e(
        'Failed to generate portrait for Story Friend ${character.id}',
        error: e,
      );
      rethrow;
    }
  }

  String _buildCharacterArtPrompt({
    required StoryCharacterEntity character,
    int? childAge,
  }) {
    final buffer = StringBuffer();
    final name = character.displayName ?? 'the character';
    final ageText =
        childAge != null ? 'for a child around age $childAge' : 'for a child';

    buffer.writeln(
      'Create a whimsical, age-appropriate children\'s book illustration of $name.',
    );
    if (character.summary != null && character.summary!.isNotEmpty) {
      buffer.writeln('Short description: ${character.summary}.');
    }
    if (character.fullDescription != null &&
        character.fullDescription!.isNotEmpty) {
      buffer.writeln('Backstory and appearance details:');
      buffer.writeln(character.fullDescription);
    }
    if (character.traits.isNotEmpty) {
      buffer.writeln('Traits: ${character.traits.join(', ')}.');
    }
    if (character.powers.isNotEmpty) {
      buffer.writeln('Powers or special abilities: ${character.powers.join(', ')}.');
    }
    if (character.favorites.isNotEmpty) {
      buffer.writeln('Favorites (foods, places, friends, etc.): '
          '${character.favorites.join(', ')}.');
    }
    buffer.writeln(
      'The style should feel like a warm children\'s picture book illustration '
      '$ageText, with soft lighting and vibrant but gentle colors.',
    );

    return buffer.toString();
  }

  Future<Directory> _getCharactersDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/story_characters');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}


