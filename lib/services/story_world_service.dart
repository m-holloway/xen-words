import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/story_world_models.dart';
import '../utils/app_logger.dart';

/// Local-first persistence and graph helper for Story World entities.
///
/// This service stores a per-profile Story World graph as a JSON file
/// alongside existing story data. It is intentionally lightweight and
/// optimized for on-device use.
class StoryWorldService {
  StoryWorldService._();

  static final StoryWorldService instance = StoryWorldService._();

  /// Derive a stable storage file name for a given profile.
  ///
  /// Guest mode can pass a synthetic ID such as "guest".
  String _fileNameForProfile(String profileId) {
    final sanitized = profileId.isEmpty ? 'guest' : profileId;
    return 'story_world_$sanitized.json';
  }

  Future<File> _ensureFile(String profileId) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_fileNameForProfile(profileId)}');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(const StoryWorldSnapshot().toJson()));
    }
    return file;
  }

  /// Load the Story World graph for the given profile, creating an empty
  /// graph if needed.
  Future<StoryWorldSnapshot> loadWorld(String profileId) async {
    try {
      final file = await _ensureFile(profileId);
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        return const StoryWorldSnapshot();
      }
      final data = jsonDecode(contents) as Map<String, dynamic>;
      return StoryWorldSnapshot.fromJson(data);
    } catch (e) {
      AppLogger.storage.e(
        'Failed to load Story World for profile=$profileId',
        error: e,
      );
      return const StoryWorldSnapshot();
    }
  }

  Future<void> _saveWorld(String profileId, StoryWorldSnapshot world) async {
    try {
      final file = await _ensureFile(profileId);
      await file.writeAsString(jsonEncode(world.toJson()));
      AppLogger.storage.d('Story World saved for profile=$profileId');
    } catch (e) {
      AppLogger.storage.e(
        'Failed to save Story World for profile=$profileId',
        error: e,
      );
      rethrow;
    }
  }

  /// Generate a new, prefixed ID for an entity type.
  String _newEntityId(StoryWorldEntityType type) {
    final prefix = storyWorldEntityTypeToString(type);
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
  }

  String _newEdgeId() {
    return 'edge_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
  }

  String _randomSuffix() {
    // Very small, local-only random suffix to avoid collisions.
    return (DateTime.now().microsecondsSinceEpoch % 100000).toRadixString(36);
  }

  /// Create a new character with a generated ID and persist it.
  Future<StoryCharacterEntity> createCharacter({
    required String profileId,
    required String displayName,
    String? summary,
    String? inspiredByProfileId,
  }) async {
    final now = DateTime.now();
    final id = _newEntityId(StoryWorldEntityType.character);
    final character = StoryCharacterEntity(
      id: id,
      displayName: displayName,
      summary: summary,
      inspiredByProfileId: inspiredByProfileId,
      createdAt: now,
      updatedAt: now,
    );
    await upsertCharacter(profileId: profileId, character: character);
    return character;
  }

  /// Delete a character and remove any graph edges that reference it.
  Future<void> deleteCharacter({
    required String profileId,
    required String characterId,
  }) async {
    final world = await loadWorld(profileId);
    if (!world.characters.containsKey(characterId)) {
      return;
    }

    final updatedCharacters =
        Map<String, StoryCharacterEntity>.from(world.characters)
          ..remove(characterId);
    final updatedEdges = world.edges
        .where(
          (edge) =>
              edge.fromId != characterId && edge.toId != characterId,
        )
        .toList();

    final updatedWorld = world.copyWith(
      characters: updatedCharacters,
      edges: updatedEdges,
    );
    await _saveWorld(profileId, updatedWorld);
  }

  /// Insert or update a character for the profile.
  Future<void> upsertCharacter({
    required String profileId,
    required StoryCharacterEntity character,
  }) async {
    final world = await loadWorld(profileId);
    final updatedCharacters = Map<String, StoryCharacterEntity>.from(
      world.characters,
    );
    updatedCharacters[character.id] = character;
    final updatedWorld = world.copyWith(characters: updatedCharacters);
    await _saveWorld(profileId, updatedWorld);
  }

  Future<List<StoryCharacterEntity>> getCharacters(String profileId) async {
    final world = await loadWorld(profileId);
    return world.characters.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<StoryCharacterEntity?> getCharacterById(
    String profileId,
    String characterId,
  ) async {
    final world = await loadWorld(profileId);
    return world.characters[characterId];
  }

  /// Create or update a Thing (prop).
  Future<void> upsertThing({
    required String profileId,
    required StoryThingEntity thing,
  }) async {
    final world = await loadWorld(profileId);
    final updatedThings = Map<String, StoryThingEntity>.from(world.things);
    updatedThings[thing.id] = thing;
    final updatedWorld = world.copyWith(things: updatedThings);
    await _saveWorld(profileId, updatedWorld);
  }

  /// Delete a thing and remove any graph edges that reference it.
  Future<void> deleteThing({
    required String profileId,
    required String thingId,
  }) async {
    final world = await loadWorld(profileId);
    if (!world.things.containsKey(thingId)) {
      return;
    }

    final updatedThings =
        Map<String, StoryThingEntity>.from(world.things)..remove(thingId);
    final updatedEdges = world.edges
        .where((edge) => edge.fromId != thingId && edge.toId != thingId)
        .toList();

    final updatedWorld = world.copyWith(
      things: updatedThings,
      edges: updatedEdges,
    );
    await _saveWorld(profileId, updatedWorld);
  }

  /// Create or update a Place.
  Future<void> upsertPlace({
    required String profileId,
    required StoryPlaceEntity place,
  }) async {
    final world = await loadWorld(profileId);
    final updatedPlaces = Map<String, StoryPlaceEntity>.from(world.places);
    updatedPlaces[place.id] = place;
    final updatedWorld = world.copyWith(places: updatedPlaces);
    await _saveWorld(profileId, updatedWorld);
  }

  /// Delete a place and remove any graph edges that reference it.
  Future<void> deletePlace({
    required String profileId,
    required String placeId,
  }) async {
    final world = await loadWorld(profileId);
    if (!world.places.containsKey(placeId)) {
      return;
    }

    final updatedPlaces =
        Map<String, StoryPlaceEntity>.from(world.places)..remove(placeId);
    final updatedEdges = world.edges
        .where((edge) => edge.fromId != placeId && edge.toId != placeId)
        .toList();

    final updatedWorld = world.copyWith(
      places: updatedPlaces,
      edges: updatedEdges,
    );
    await _saveWorld(profileId, updatedWorld);
  }

  /// Create a drawing entity record for an imported or captured image.
  Future<StoryDrawingEntity> createDrawing({
    required String profileId,
    required String imagePath,
    String? title,
    String? summary,
    String? captureSource,
    String? createdByProfileId,
  }) async {
    final now = DateTime.now();
    final id = _newEntityId(StoryWorldEntityType.drawing);
    final drawing = StoryDrawingEntity(
      id: id,
      imagePath: imagePath,
      displayName: title,
      summary: summary,
      captureSource: captureSource,
      createdByProfileId: createdByProfileId,
      createdAt: now,
      updatedAt: now,
    );
    final world = await loadWorld(profileId);
    final updatedDrawings = Map<String, StoryDrawingEntity>.from(
      world.drawings,
    );
    updatedDrawings[drawing.id] = drawing;
    final updatedWorld = world.copyWith(drawings: updatedDrawings);
    await _saveWorld(profileId, updatedWorld);
    return drawing;
  }

  /// Insert or update a drawing record.
  Future<void> upsertDrawing({
    required String profileId,
    required StoryDrawingEntity drawing,
  }) async {
    final world = await loadWorld(profileId);
    final updatedDrawings =
        Map<String, StoryDrawingEntity>.from(world.drawings);
    updatedDrawings[drawing.id] = drawing;
    final updatedWorld = world.copyWith(drawings: updatedDrawings);
    await _saveWorld(profileId, updatedWorld);
  }

  /// Delete a drawing, remove references from entities, and clean up edges.
  Future<void> deleteDrawing({
    required String profileId,
    required String drawingId,
  }) async {
    final world = await loadWorld(profileId);
    final existing = world.drawings[drawingId];
    if (existing == null) {
      return;
    }

    // Attempt to delete the underlying image file.
    try {
      final file = File(existing.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      AppLogger.storage.w(
        'Failed to delete drawing file for $drawingId',
        error: e,
      );
    }

    // Remove drawing from map.
    final updatedDrawings =
        Map<String, StoryDrawingEntity>.from(world.drawings)
          ..remove(drawingId);

    // Remove drawing references from characters, things, and places.
    final cleanedCharacters = world.characters.map((id, character) {
      final filteredIds =
          character.drawingIds.where((dId) => dId != drawingId).toList();
      if (filteredIds.length == character.drawingIds.length) {
        return MapEntry(id, character);
      }
      return MapEntry(
        id,
        character.copyWith(
          drawingIds: filteredIds,
          updatedAt: DateTime.now(),
        ),
      );
    });

    final cleanedThings = world.things.map((id, thing) {
      final filteredIds =
          thing.drawingIds.where((dId) => dId != drawingId).toList();
      if (filteredIds.length == thing.drawingIds.length) {
        return MapEntry(id, thing);
      }
      return MapEntry(
        id,
        thing.copyWith(
          drawingIds: filteredIds,
          updatedAt: DateTime.now(),
        ),
      );
    });

    final cleanedPlaces = world.places.map((id, place) {
      final filteredIds =
          place.drawingIds.where((dId) => dId != drawingId).toList();
      if (filteredIds.length == place.drawingIds.length) {
        return MapEntry(id, place);
      }
      return MapEntry(
        id,
        place.copyWith(
          drawingIds: filteredIds,
          updatedAt: DateTime.now(),
        ),
      );
    });

    // Remove edges that reference the drawing.
    final updatedEdges = world.edges
        .where(
          (edge) =>
              edge.fromId != drawingId && edge.toId != drawingId,
        )
        .toList();

    final updatedWorld = world.copyWith(
      drawings: updatedDrawings,
      characters: cleanedCharacters,
      things: cleanedThings,
      places: cleanedPlaces,
      edges: updatedEdges,
    );
    await _saveWorld(profileId, updatedWorld);
  }

  /// Add or update a graph edge between two IDs.
  ///
  /// The IDs may refer to Story World entities or to external story/scene IDs.
  Future<void> link({
    required String profileId,
    required StoryWorldEdgeType type,
    required String fromId,
    required String toId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final world = await loadWorld(profileId);
    final existing = world.edges.where((edge) {
      return edge.type == type &&
          edge.fromId == fromId &&
          edge.toId == toId;
    }).toList();

    final now = DateTime.now();
    final List<StoryWorldEdge> updatedEdges;
    if (existing.isEmpty) {
      final newEdge = StoryWorldEdge(
        id: _newEdgeId(),
        type: type,
        fromId: fromId,
        toId: toId,
        createdAt: now,
        updatedAt: now,
        metadata: metadata,
      );
      updatedEdges = [...world.edges, newEdge];
    } else {
      final updated = existing.first.copyWith(
        metadata: {
          ...existing.first.metadata,
          ...metadata,
        },
        updatedAt: now,
      );
      updatedEdges = world.edges
          .map((edge) => edge.id == updated.id ? updated : edge)
          .toList();
    }

    final updatedWorld = world.copyWith(edges: updatedEdges);
    await _saveWorld(profileId, updatedWorld);
  }

  /// Remove a graph edge between two IDs if it exists.
  Future<void> unlink({
    required String profileId,
    required StoryWorldEdgeType type,
    required String fromId,
    required String toId,
  }) async {
    final world = await loadWorld(profileId);
    final filtered = world.edges.where((edge) {
      return !(edge.type == type &&
          edge.fromId == fromId &&
          edge.toId == toId);
    }).toList();
    if (filtered.length == world.edges.length) {
      return;
    }
    final updatedWorld = world.copyWith(edges: filtered);
    await _saveWorld(profileId, updatedWorld);
  }

  /// Convenience helper: find all characters that appear in a story.
  Future<List<StoryCharacterEntity>> charactersForStory({
    required String profileId,
    required String storyId,
  }) async {
    final world = await loadWorld(profileId);
    final characterIds = world.edges
        .where(
          (edge) =>
              edge.type == StoryWorldEdgeType.appearsIn &&
              edge.toId == storyId,
        )
        .map((e) => e.fromId)
        .toSet();
    return characterIds
        .map((id) => world.characters[id])
        .whereType<StoryCharacterEntity>()
        .toList();
  }

  /// Convenience helper: find all stories that a character appears in.
  ///
  /// Returns raw story IDs so that higher-level services can fetch full
  /// [GeneratedStoryRecord] instances as needed.
  Future<List<String>> storyIdsForCharacter({
    required String profileId,
    required String characterId,
  }) async {
    final world = await loadWorld(profileId);
    return world.edges
        .where(
          (edge) =>
              edge.type == StoryWorldEdgeType.appearsIn &&
              edge.fromId == characterId,
        )
        .map((e) => e.toId)
        .toSet()
        .toList();
  }

  /// Clear all Story World data for a given profile.
  Future<void> clearWorld(String profileId) async {
    final file = await _ensureFile(profileId);
    await file.writeAsString(
      jsonEncode(const StoryWorldSnapshot().toJson()),
    );
  }
}


