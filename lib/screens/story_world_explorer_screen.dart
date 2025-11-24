import 'package:flutter/material.dart';

import '../models/story_generation_models.dart';
import '../models/story_world_models.dart';
import '../services/story_generator_service.dart';
import '../services/story_world_service.dart';

/// Read-only view that connects Story Friends, stories, and other
/// Story World entities in a simple, list-based explorer.
class StoryWorldExplorerScreen extends StatefulWidget {
  const StoryWorldExplorerScreen({
    super.key,
    required this.profileId,
  });

  final String profileId;

  @override
  State<StoryWorldExplorerScreen> createState() =>
      _StoryWorldExplorerScreenState();
}

class _StoryWorldExplorerScreenState extends State<StoryWorldExplorerScreen> {
  final StoryWorldService _worldService = StoryWorldService.instance;
  final StoryGeneratorService _storyService = StoryGeneratorService();

  bool _loading = true;
  StoryWorldSnapshot? _world;
  List<GeneratedStoryRecord> _stories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final world = await _worldService.loadWorld(widget.profileId);
      final stories = await _storyService.loadStories();
      if (!mounted) return;
      setState(() {
        _world = world;
        _stories = stories;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final world = _world;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Story World Explorer'),
      ),
      body: _loading || world == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Story Friends',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (world.characters.isEmpty)
                  const Text('No Story Friends saved yet.')
                else
                  ...world.characters.values.map(
                    (character) => _buildCharacterRow(character, world),
                  ),
              ],
            ),
    );
  }

  Widget _buildCharacterRow(
    StoryCharacterEntity character,
    StoryWorldSnapshot world,
  ) {
    final storyIds = world.edges
        .where(
          (edge) =>
              edge.type == StoryWorldEdgeType.appearsIn &&
              edge.fromId == character.id,
        )
        .map((e) => e.toId)
        .toSet();
    final connectedStories = _stories
        .where((story) => storyIds.contains(story.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ExpansionTile(
      title: Text(character.displayName ?? 'Story Friend'),
      subtitle: Text(
        connectedStories.isEmpty
            ? 'Not linked to any stories yet.'
            : '${connectedStories.length} stor${connectedStories.length == 1 ? 'y' : 'ies'}',
      ),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      children: [
        if (connectedStories.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Once you connect this Story Friend to stories, they will appear here.',
            ),
          )
        else
          ...connectedStories.map(
            (story) => ListTile(
              dense: true,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(story.chapter.title),
              subtitle: Text(
                story.summary.isNotEmpty
                    ? story.summary
                    : 'Created on ${story.createdAt.toLocal()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}


