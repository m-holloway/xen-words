import 'package:flutter/material.dart';

import '../models/story_world_models.dart';
import '../services/profile_service.dart';
import '../services/story_world_search_service.dart';
import '../services/story_world_service.dart';
import '../utils/app_logger.dart';

enum StoryCoachMode {
  characterBuilder,
  storySeed,
}

/// A lightweight conversational-style Story Coach that helps parents
/// and kids shape Story Friends and story ideas using local Story World
/// knowledge. Voice input can be layered on later; for now this is
/// touch + text driven.
class StoryCoachScreen extends StatefulWidget {
  const StoryCoachScreen({
    super.key,
    this.mode = StoryCoachMode.characterBuilder,
  });

  final StoryCoachMode mode;

  @override
  State<StoryCoachScreen> createState() => _StoryCoachScreenState();
}

class _StoryCoachScreenState extends State<StoryCoachScreen> {
  final ProfileService _profileService = ProfileService();
  final StoryWorldService _worldService = StoryWorldService.instance;
  final StoryWorldSearchService _searchService =
      StoryWorldSearchService();

  final TextEditingController _inputController = TextEditingController();

  String? _profileId;
  String? _profileName;
  bool _loadingProfile = true;

  StoryCharacterEntity? _workingCharacter;
  int _stepIndex = 0;
  bool _saving = false;
  List<StoryCharacterEntity> _searchMatches = const [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
    });
    try {
      final activeId = await _profileService.getActiveProfileId();
      final profiles = await _profileService.loadProfiles();
      final profile = activeId == null
          ? null
          : profiles.where((p) => p.id == activeId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _profileId = profile?.id ?? 'guest';
        _profileName = profile?.name;
        _loadingProfile = false;
      });
    } catch (e) {
      AppLogger.system.e('Failed to load profile for Story Coach', error: e);
      if (!mounted) return;
      setState(() {
        _profileId = 'guest';
        _loadingProfile = false;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _onNextPressed() async {
    final profileId = _profileId;
    if (profileId == null) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    if (_stepIndex == 0) {
      // Step 0: name or pick a Story Friend.
      final matches = await _searchService.searchCharacters(
        profileId: profileId,
        query: text,
      );
      if (matches.isNotEmpty) {
        setState(() {
          _searchMatches = matches;
        });
      } else {
        final now = DateTime.now();
        final character = StoryCharacterEntity(
          id: 'temp_${now.millisecondsSinceEpoch}',
          displayName: text,
          summary: null,
          tags: const [],
          inspiredByProfileId: profileId == 'guest' ? null : profileId,
          fullDescription: null,
          traits: const [],
          powers: const [],
          favorites: const [],
          heroPortraitPath: null,
          drawingIds: const [],
          createdAt: now,
          updatedAt: now,
        );
        setState(() {
          _workingCharacter = character;
          _stepIndex = 1;
          _searchMatches = const [];
          _inputController.clear();
        });
      }
    } else if (_stepIndex == 1) {
      // Appearance / costume.
      final current = _workingCharacter;
      if (current == null) return;
      final updated = current.copyWith(
        fullDescription: text,
        updatedAt: DateTime.now(),
      );
      setState(() {
        _workingCharacter = updated;
        _stepIndex = 2;
        _inputController.clear();
      });
    } else if (_stepIndex == 2) {
      // Powers or special skills.
      final current = _workingCharacter;
      if (current == null) return;
      final powers = text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where(
            (e) => e.isNotEmpty,
          );
      final updated = current.copyWith(
        powers: powers.toList(),
        updatedAt: DateTime.now(),
      );
      setState(() {
        _workingCharacter = updated;
        _stepIndex = 3;
        _inputController.clear();
      });
    } else if (_stepIndex == 3) {
      // Favorites / heart.
      final current = _workingCharacter;
      if (current == null) return;
      final favorites =
          text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where(
                (e) => e.isNotEmpty,
              );
      final updated = current.copyWith(
        favorites: favorites.toList(),
        updatedAt: DateTime.now(),
      );
      setState(() {
        _workingCharacter = updated;
      });
      await _saveCharacter();
    }
  }

  Future<void> _saveCharacter() async {
    final profileId = _profileId;
    final working = _workingCharacter;
    if (profileId == null || working == null || _saving) return;
    setState(() {
      _saving = true;
    });
    try {
      final now = DateTime.now();
      final character = StoryCharacterEntity(
        id: '', // ID will be assigned by service.
        displayName: working.displayName,
        summary: working.summary ??
            'A Story Friend imagined with the Story Coach.',
        tags: working.tags,
        inspiredByProfileId: working.inspiredByProfileId,
        fullDescription: working.fullDescription,
        traits: working.traits,
        powers: working.powers,
        favorites: working.favorites,
        heroPortraitPath: working.heroPortraitPath,
        drawingIds: working.drawingIds,
        createdAt: now,
        updatedAt: now,
      );
      // Use createCharacter so that IDs and persistence are handled uniformly.
      await _worldService.createCharacter(
        profileId: profileId,
        displayName: character.displayName ?? 'Story Friend',
        summary: character.summary,
        inspiredByProfileId: character.inspiredByProfileId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story Friend saved to My Story World!'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save Story Friend: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _selectMatch(StoryCharacterEntity match) {
    setState(() {
      _workingCharacter = match;
      _stepIndex = 1;
      _searchMatches = const [];
      _inputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName ?? 'your child';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.mode == StoryCoachMode.characterBuilder
                  ? 'Story Friend Coach'
                  : 'Story Idea Coach',
            ),
            Text(
              'Guided imagination time for $name',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildConversation(theme),
                  ),
                  const SizedBox(height: 12),
                  _buildInputBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildConversation(ThemeData theme) {
    final characterName =
        _workingCharacter?.displayName ?? 'your Story Friend';

    final questions = [
      'Let’s dream up a Story Friend. What should we call them?',
      'What does $characterName look like? You can mention clothes, colors, or anything special.',
      'Does $characterName have any powers or special skills?',
      'What are some things $characterName loves? Foods, places, friends, or hobbies?',
    ];

    final question = questions[_stepIndex.clamp(0, questions.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology_alt_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_searchMatches.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchMatches.map((c) {
              return ActionChip(
                label: Text(c.displayName ?? 'Story Friend'),
                onPressed: () => _selectMatch(c),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onNextPressed(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Answer here…',
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _onNextPressed,
          child: const Text('Next'),
        ),
      ],
    );
  }
}


