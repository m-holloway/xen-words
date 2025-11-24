library;

import 'package:flutter/foundation.dart';

/// Types of entities that can live in the Story World graph.
enum StoryWorldEntityType {
  character,
  thing,
  place,
  drawing,
}

/// Types of relationships between Story World entities and stories/scenes.
enum StoryWorldEdgeType {
  appearsIn, // character/thing/place -> storyId or sceneId
  uses, // character -> thing
  has, // storyId -> thing
  locatedAt, // sceneId or storyId -> place
  inspiredBy, // character/thing/place -> drawing or real-person-id (string)
  friendsWith, // character <-> character
  visitedBy, // place -> character
  contains, // place -> thing
  depicts, // drawing -> character/thing/place
  seedFor, // drawing -> storyId or sceneId
}

String storyWorldEdgeTypeToString(StoryWorldEdgeType type) {
  switch (type) {
    case StoryWorldEdgeType.appearsIn:
      return 'appears_in';
    case StoryWorldEdgeType.uses:
      return 'uses';
    case StoryWorldEdgeType.has:
      return 'has';
    case StoryWorldEdgeType.locatedAt:
      return 'located_at';
    case StoryWorldEdgeType.inspiredBy:
      return 'inspired_by';
    case StoryWorldEdgeType.friendsWith:
      return 'friends_with';
    case StoryWorldEdgeType.visitedBy:
      return 'visited_by';
    case StoryWorldEdgeType.contains:
      return 'contains';
    case StoryWorldEdgeType.depicts:
      return 'depicts';
    case StoryWorldEdgeType.seedFor:
      return 'seed_for';
  }
}

StoryWorldEdgeType storyWorldEdgeTypeFromString(String value) {
  switch (value.toLowerCase()) {
    case 'appears_in':
      return StoryWorldEdgeType.appearsIn;
    case 'uses':
      return StoryWorldEdgeType.uses;
    case 'has':
      return StoryWorldEdgeType.has;
    case 'located_at':
      return StoryWorldEdgeType.locatedAt;
    case 'inspired_by':
      return StoryWorldEdgeType.inspiredBy;
    case 'friends_with':
      return StoryWorldEdgeType.friendsWith;
    case 'visited_by':
      return StoryWorldEdgeType.visitedBy;
    case 'contains':
      return StoryWorldEdgeType.contains;
    case 'depicts':
      return StoryWorldEdgeType.depicts;
    case 'seed_for':
      return StoryWorldEdgeType.seedFor;
    default:
      return StoryWorldEdgeType.appearsIn;
  }
}

String storyWorldEntityTypeToString(StoryWorldEntityType type) {
  switch (type) {
    case StoryWorldEntityType.character:
      return 'character';
    case StoryWorldEntityType.thing:
      return 'thing';
    case StoryWorldEntityType.place:
      return 'place';
    case StoryWorldEntityType.drawing:
      return 'drawing';
  }
}

StoryWorldEntityType storyWorldEntityTypeFromString(String value) {
  switch (value.toLowerCase()) {
    case 'thing':
      return StoryWorldEntityType.thing;
    case 'place':
      return StoryWorldEntityType.place;
    case 'drawing':
      return StoryWorldEntityType.drawing;
    case 'character':
    default:
      return StoryWorldEntityType.character;
  }
}

/// Base class for any Story World entity.
///
/// Concrete entities add their own fields but share identity and tagging.
@immutable
abstract class StoryWorldEntity {
  const StoryWorldEntity({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.summary,
    this.tags = const [],
  });

  /// Global, unique identifier (e.g., "char_...", "thing_...", etc.).
  final String id;

  /// Entity type used for graph queries and persistence.
  final StoryWorldEntityType type;

  /// Optional short display name for UI (e.g., "The Amazing AZ").
  final String? displayName;

  /// Optional short, kid-friendly summary/tagline.
  final String? summary;

  /// Free-form tags to support lightweight filtering and search.
  final List<String> tags;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last updated timestamp.
  final DateTime updatedAt;

  Map<String, dynamic> toJson();
}

@immutable
class StoryCharacterEntity extends StoryWorldEntity {
  const StoryCharacterEntity({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    super.displayName,
    super.summary,
    super.tags = const [],
    this.inspiredByProfileId,
    this.fullDescription,
    this.traits = const [],
    this.powers = const [],
    this.favorites = const [],
    this.heroPortraitPath,
    this.realPhotoPath,
    this.drawingIds = const [],
  }) : super(type: StoryWorldEntityType.character);

  /// Optional ID of the child profile or real person who inspired this character.
  final String? inspiredByProfileId;

  /// Rich, free-form description/backstory.
  final String? fullDescription;

  /// Short trait labels like "brave", "silly", etc.
  final List<String> traits;

  /// Superpowers or special skills.
  final List<String> powers;

  /// Favorites (foods, places, friends, etc.).
  final List<String> favorites;

  /// Path to the main hero portrait (AI or kid-drawn scan).
  final String? heroPortraitPath;

  /// Optional real-life photo reference (e.g., of the child/person
  /// the character is based on).
  final String? realPhotoPath;

  /// IDs of drawing entities attached to this character.
  final List<String> drawingIds;

  StoryCharacterEntity copyWith({
    String? displayName,
    String? summary,
    List<String>? tags,
    String? inspiredByProfileId,
    String? fullDescription,
    List<String>? traits,
    List<String>? powers,
    List<String>? favorites,
    String? heroPortraitPath,
    String? realPhotoPath,
    List<String>? drawingIds,
    DateTime? updatedAt,
  }) {
    return StoryCharacterEntity(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      inspiredByProfileId: inspiredByProfileId ?? this.inspiredByProfileId,
      fullDescription: fullDescription ?? this.fullDescription,
      traits: traits ?? this.traits,
      powers: powers ?? this.powers,
      favorites: favorites ?? this.favorites,
      heroPortraitPath: heroPortraitPath ?? this.heroPortraitPath,
      realPhotoPath: realPhotoPath ?? this.realPhotoPath,
      drawingIds: drawingIds ?? this.drawingIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': storyWorldEntityTypeToString(type),
      'display_name': displayName,
      'summary': summary,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'inspired_by_profile_id': inspiredByProfileId,
      'full_description': fullDescription,
      'traits': traits,
      'powers': powers,
      'favorites': favorites,
      'hero_portrait_path': heroPortraitPath,
      'real_photo_path': realPhotoPath,
      'drawing_ids': drawingIds,
    };
  }

  factory StoryCharacterEntity.fromJson(Map<String, dynamic> json) {
    return StoryCharacterEntity(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      displayName: json['display_name'] as String?,
      summary: json['summary'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      inspiredByProfileId: json['inspired_by_profile_id'] as String?,
      fullDescription: json['full_description'] as String?,
      traits: (json['traits'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      powers: (json['powers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      favorites: (json['favorites'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      heroPortraitPath: json['hero_portrait_path'] as String?,
      realPhotoPath: json['real_photo_path'] as String?,
      drawingIds: (json['drawing_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

@immutable
class StoryThingEntity extends StoryWorldEntity {
  const StoryThingEntity({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    super.displayName,
    super.summary,
    super.tags = const [],
    this.rules,
    this.imagePath,
    this.drawingIds = const [],
  }) : super(type: StoryWorldEntityType.thing);

  /// Description of how the thing works (e.g., wand rules, constraints).
  final String? rules;

  /// Optional main image for this prop.
  final String? imagePath;

  /// IDs of drawing entities attached to this thing.
  final List<String> drawingIds;

  StoryThingEntity copyWith({
    String? displayName,
    String? summary,
    List<String>? tags,
    String? rules,
    String? imagePath,
    List<String>? drawingIds,
    DateTime? updatedAt,
  }) {
    return StoryThingEntity(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      rules: rules ?? this.rules,
      imagePath: imagePath ?? this.imagePath,
      drawingIds: drawingIds ?? this.drawingIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': storyWorldEntityTypeToString(type),
      'display_name': displayName,
      'summary': summary,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'rules': rules,
      'image_path': imagePath,
      'drawing_ids': drawingIds,
    };
  }

  factory StoryThingEntity.fromJson(Map<String, dynamic> json) {
    return StoryThingEntity(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      displayName: json['display_name'] as String?,
      summary: json['summary'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      rules: json['rules'] as String?,
      imagePath: json['image_path'] as String?,
      drawingIds: (json['drawing_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

@immutable
class StoryPlaceEntity extends StoryWorldEntity {
  const StoryPlaceEntity({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    super.displayName,
    super.summary,
    super.tags = const [],
    this.placeType,
    this.imagePath,
    this.drawingIds = const [],
  }) : super(type: StoryWorldEntityType.place);

  /// Simple categorization like "real", "imaginary", "hybrid".
  final String? placeType;

  /// Optional main image for this place.
  final String? imagePath;

  /// IDs of drawing entities attached to this place.
  final List<String> drawingIds;

  StoryPlaceEntity copyWith({
    String? displayName,
    String? summary,
    List<String>? tags,
    String? placeType,
    String? imagePath,
    List<String>? drawingIds,
    DateTime? updatedAt,
  }) {
    return StoryPlaceEntity(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      placeType: placeType ?? this.placeType,
      imagePath: imagePath ?? this.imagePath,
      drawingIds: drawingIds ?? this.drawingIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': storyWorldEntityTypeToString(type),
      'display_name': displayName,
      'summary': summary,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'place_type': placeType,
      'image_path': imagePath,
      'drawing_ids': drawingIds,
    };
  }

  factory StoryPlaceEntity.fromJson(Map<String, dynamic> json) {
    return StoryPlaceEntity(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      displayName: json['display_name'] as String?,
      summary: json['summary'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      placeType: json['place_type'] as String?,
      imagePath: json['image_path'] as String?,
      drawingIds: (json['drawing_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

@immutable
class StoryDrawingEntity extends StoryWorldEntity {
  const StoryDrawingEntity({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required this.imagePath,
    super.displayName,
    super.summary,
    super.tags = const [],
    this.captureSource,
    this.createdByProfileId,
  }) : super(type: StoryWorldEntityType.drawing);

  /// Local file path to the image on device.
  final String imagePath;

  /// Where the image came from ("camera", "gallery", etc.).
  final String? captureSource;

  /// Optional profile ID of the child who created this drawing.
  final String? createdByProfileId;

  StoryDrawingEntity copyWith({
    String? displayName,
    String? summary,
    List<String>? tags,
    String? imagePath,
    String? captureSource,
    String? createdByProfileId,
    DateTime? updatedAt,
  }) {
    return StoryDrawingEntity(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imagePath: imagePath ?? this.imagePath,
      displayName: displayName ?? this.displayName,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      captureSource: captureSource ?? this.captureSource,
      createdByProfileId: createdByProfileId ?? this.createdByProfileId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': storyWorldEntityTypeToString(type),
      'display_name': displayName,
      'summary': summary,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'image_path': imagePath,
      'capture_source': captureSource,
      'created_by_profile_id': createdByProfileId,
    };
  }

  factory StoryDrawingEntity.fromJson(Map<String, dynamic> json) {
    return StoryDrawingEntity(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      imagePath: json['image_path'] as String? ?? '',
      displayName: json['display_name'] as String?,
      summary: json['summary'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      captureSource: json['capture_source'] as String?,
      createdByProfileId: json['created_by_profile_id'] as String?,
    );
  }
}

/// A typed relationship (edge) between two Story World entities or a Story.
///
/// The [fromId] and [toId] refer to entity IDs when pointing at Story World
/// entities, or to external IDs such as story IDs or scene IDs when the
/// node is not persisted in this graph file.
@immutable
class StoryWorldEdge {
  const StoryWorldEdge({
    required this.id,
    required this.type,
    required this.fromId,
    required this.toId,
    required this.createdAt,
    this.updatedAt,
    this.metadata = const {},
  });

  final String id;
  final StoryWorldEdgeType type;
  final String fromId;
  final String toId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;

  StoryWorldEdge copyWith({
    StoryWorldEdgeType? type,
    String? fromId,
    String? toId,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
  }) {
    return StoryWorldEdge(
      id: id,
      type: type ?? this.type,
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': storyWorldEdgeTypeToString(type),
      'from_id': fromId,
      'to_id': toId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory StoryWorldEdge.fromJson(Map<String, dynamic> json) {
    return StoryWorldEdge(
      id: json['id'] as String,
      type: storyWorldEdgeTypeFromString(json['type'] as String? ?? ''),
      fromId: json['from_id'] as String? ?? '',
      toId: json['to_id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
          : const {},
    );
  }
}

/// A snapshot of the Story World graph for a given child profile.
@immutable
class StoryWorldSnapshot {
  const StoryWorldSnapshot({
    this.characters = const {},
    this.things = const {},
    this.places = const {},
    this.drawings = const {},
    this.edges = const [],
  });

  final Map<String, StoryCharacterEntity> characters;
  final Map<String, StoryThingEntity> things;
  final Map<String, StoryPlaceEntity> places;
  final Map<String, StoryDrawingEntity> drawings;
  final List<StoryWorldEdge> edges;

  StoryWorldSnapshot copyWith({
    Map<String, StoryCharacterEntity>? characters,
    Map<String, StoryThingEntity>? things,
    Map<String, StoryPlaceEntity>? places,
    Map<String, StoryDrawingEntity>? drawings,
    List<StoryWorldEdge>? edges,
  }) {
    return StoryWorldSnapshot(
      characters: characters ?? this.characters,
      things: things ?? this.things,
      places: places ?? this.places,
      drawings: drawings ?? this.drawings,
      edges: edges ?? this.edges,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characters': characters.map((key, value) => MapEntry(key, value.toJson())),
      'things': things.map((key, value) => MapEntry(key, value.toJson())),
      'places': places.map((key, value) => MapEntry(key, value.toJson())),
      'drawings': drawings.map((key, value) => MapEntry(key, value.toJson())),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
  }

  factory StoryWorldSnapshot.fromJson(Map<String, dynamic> json) {
    final rawCharacters = json['characters'] as Map<String, dynamic>? ?? {};
    final rawThings = json['things'] as Map<String, dynamic>? ?? {};
    final rawPlaces = json['places'] as Map<String, dynamic>? ?? {};
    final rawDrawings = json['drawings'] as Map<String, dynamic>? ?? {};
    final rawEdges = json['edges'] as List<dynamic>? ?? [];

    return StoryWorldSnapshot(
      characters: rawCharacters.map(
        (key, value) => MapEntry(
          key,
          StoryCharacterEntity.fromJson(
            value as Map<String, dynamic>,
          ),
        ),
      ),
      things: rawThings.map(
        (key, value) => MapEntry(
          key,
          StoryThingEntity.fromJson(
            value as Map<String, dynamic>,
          ),
        ),
      ),
      places: rawPlaces.map(
        (key, value) => MapEntry(
          key,
          StoryPlaceEntity.fromJson(
            value as Map<String, dynamic>,
          ),
        ),
      ),
      drawings: rawDrawings.map(
        (key, value) => MapEntry(
          key,
          StoryDrawingEntity.fromJson(
            value as Map<String, dynamic>,
          ),
        ),
      ),
      edges: rawEdges
          .map((e) => StoryWorldEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}


