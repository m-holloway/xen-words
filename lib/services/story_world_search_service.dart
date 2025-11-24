import '../models/story_world_models.dart';
import 'story_world_service.dart';

/// Lightweight, local-first semantic-ish search over the Story World graph.
///
/// This is intentionally simple for now (string-based scoring) but is
/// structured so that an embedding model can be dropped in later.
class StoryWorldSearchService {
  StoryWorldSearchService({StoryWorldService? worldService})
      : _worldService = worldService ?? StoryWorldService.instance;

  final StoryWorldService _worldService;

  Future<List<StoryCharacterEntity>> searchCharacters({
    required String profileId,
    required String query,
    int maxResults = 5,
  }) async {
    final world = await _worldService.loadWorld(profileId);
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return const [];

    final scored = <StoryCharacterEntity, double>{};
    for (final character in world.characters.values) {
      final score = _score(
        normalizedQuery,
        [
          character.displayName,
          character.summary,
          character.fullDescription,
          ...character.traits,
          ...character.powers,
          ...character.favorites,
        ],
      );
      if (score > 0) {
        scored[character] = score;
      }
    }

    final results = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return results.take(maxResults).map((e) => e.key).toList();
  }

  double _score(String query, List<String?> fields) {
    final tokens = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    double best = 0;
    for (final rawField in fields) {
      final field = rawField?.toLowerCase().trim();
      if (field == null || field.isEmpty) continue;
      double fieldScore = 0;
      for (final token in tokens) {
        if (field.contains(token)) {
          fieldScore += 1;
        }
      }
      if (field.contains(query)) {
        fieldScore += 1.5; // exact phrase bonus
      }
      if (fieldScore > best) best = fieldScore;
    }
    return best;
  }
}


