import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/story_generation_models.dart';
import '../services/story_generator_service.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../utils/reading_level_helper.dart';
import '../widgets/star_rating.dart';
import 'story_playback_screen.dart';
import 'story_reader_screen_enhanced.dart';

enum StoryLabView {
  library,
  generator,
}

enum StoryLibraryFilter {
  all,
  favorites,
  mostRead,
  recent,
}

class StoryGeneratorScreen extends StatefulWidget {
  const StoryGeneratorScreen({
    super.key,
    this.initialView = StoryLabView.library,
  });

  final StoryLabView initialView;

  @override
  State<StoryGeneratorScreen> createState() => _StoryGeneratorScreenState();
}

class _StoryGeneratorScreenState extends State<StoryGeneratorScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _parentPromptController = TextEditingController();
  final _childContextController = TextEditingController();
  final _storyConceptController = TextEditingController();

  final StoryGeneratorService _storyService = StoryGeneratorService();
  final PreferencesService _preferencesService = PreferencesService();
  final ProfileService _profileService = ProfileService();
  late final AnimationController _loadingController;
  late StoryLabView _activeView;

  bool _isGenerating = false;
  int _durationMinutes = StoryGenerationDefaults.defaultMinutes;
  double _readingLevel = StoryGenerationDefaults.defaultReadingLevel.toDouble();
  ReadingBand _currentBand = ReadingLevelHelper.bandForLevel(StoryGenerationDefaults.defaultReadingLevel);
  List<GeneratedStoryRecord> _savedStories = [];
  GeneratedStoryRecord? _latestStory;
  bool _useChildName = false;
  String? _profileChildName;
  Timer? _draftSaveDebounce;
  Timer? _generationTicker;
  DateTime? _generationStartTime;
  Duration _generationElapsed = Duration.zero;
  StoryLibraryFilter _libraryFilter = StoryLibraryFilter.all;

  @override
  void initState() {
    super.initState();
    _activeView = widget.initialView;
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _parentPromptController.addListener(_onDraftFieldChanged);
    _childContextController.addListener(_onDraftFieldChanged);
    _storyConceptController.addListener(_onDraftFieldChanged);
    _currentBand = ReadingLevelHelper.bandForLevel(_readingLevel.round());
    _loadInitialState();
    _loadStories();
  }

  @override
  void dispose() {
    _parentPromptController.removeListener(_onDraftFieldChanged);
    _childContextController.removeListener(_onDraftFieldChanged);
    _storyConceptController.removeListener(_onDraftFieldChanged);
    _draftSaveDebounce?.cancel();
    _generationTicker?.cancel();
    _loadingController.dispose();
    _parentPromptController.dispose();
    _storyConceptController.dispose();
    _childContextController.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    final stories = await _storyService.loadStories();
    setState(() {
      _savedStories = stories;
      _latestStory = stories.isNotEmpty ? stories.first : null;
    });
  }

  List<GeneratedStoryRecord> get _favoriteStories =>
      _savedStories.where((story) => (story.childRating ?? 0) >= 3).toList();

  List<GeneratedStoryRecord> get _topFavoriteStories {
    final favs = _favoriteStories;
    favs.sort((a, b) {
      final ratingCompare = (b.childRating ?? 0).compareTo(a.childRating ?? 0);
      if (ratingCompare != 0) return ratingCompare;
      final recencyCompare = _readsLast30Days(b).compareTo(_readsLast30Days(a));
      if (recencyCompare != 0) return recencyCompare;
      final readCompare = b.readCount.compareTo(a.readCount);
      if (readCompare != 0) return readCompare;
      final lastA = a.lastReadAt ?? a.createdAt;
      final lastB = b.lastReadAt ?? b.createdAt;
      return lastB.compareTo(lastA);
    });
    return favs.take(6).toList();
  }

  List<GeneratedStoryRecord> get _filteredStories {
    switch (_libraryFilter) {
      case StoryLibraryFilter.favorites:
        return List<GeneratedStoryRecord>.from(_topFavoriteStories);
      case StoryLibraryFilter.mostRead:
        final sorted = List<GeneratedStoryRecord>.from(_savedStories)
          ..sort((a, b) {
            final countCompare = b.readCount.compareTo(a.readCount);
            if (countCompare != 0) return countCompare;
            final lastA = a.lastReadAt ?? a.createdAt;
            final lastB = b.lastReadAt ?? b.createdAt;
            return lastB.compareTo(lastA);
          });
        return sorted;
      case StoryLibraryFilter.recent:
        final recents = List<GeneratedStoryRecord>.from(_savedStories);
        recents.sort((a, b) {
          final lastA = a.lastReadAt ?? a.createdAt;
          final lastB = b.lastReadAt ?? b.createdAt;
          return lastB.compareTo(lastA);
        });
        return recents;
      case StoryLibraryFilter.all:
        return List<GeneratedStoryRecord>.from(_savedStories);
    }
  }

  int _readsLast30Days(GeneratedStoryRecord story) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return story.readMoments.where((date) => date.isAfter(cutoff)).length;
  }

  String _lastReadLabel(BuildContext context, GeneratedStoryRecord story) {
    final localizations = MaterialLocalizations.of(context);
    final last = story.lastReadAt;
    if (last == null) {
      return 'Not read yet';
    }
    final now = DateTime.now();
    if (now.year == last.year && now.month == last.month && now.day == last.day) {
      return 'Last read today';
    }
    final difference = now.difference(last);
    final days = difference.inDays;
    if (days == 1) {
      return 'Last read yesterday';
    }
    if (days < 7) {
      return 'Last read ${days}d ago';
    }
    if (days < 30) {
      final weeks = (days / 7).floor();
      return weeks == 1 ? 'Last read 1w ago' : 'Last read ${weeks}w ago';
    }
    return 'Last read ${localizations.formatShortDate(last)}';
  }

  Future<void> _loadInitialState() async {
    final draft = await _preferencesService.loadStoryGeneratorDraft();
    final fallbackUseChildName = await _preferencesService.getStoryUseChildName();
    final useChildNamePref = _coerceBool(draft?['include_child_name'], fallbackUseChildName);
    final profileName = await _loadActiveProfileName();
    final parentPrompt = draft?['parent_prompt']?.toString() ?? '';
    var childContext = draft?['child_context']?.toString() ?? '';
    if (childContext.isEmpty) {
      childContext = await _preferencesService.getStoryPersonalizationNotes();
    }
    final storyConcept = draft?['story_concept']?.toString() ?? '';
    _parentPromptController.text = parentPrompt;
    _childContextController.text = childContext;
    _storyConceptController.text = storyConcept;

    final readingLevel =
        _coerceInt(draft?['reading_level'], StoryGenerationDefaults.defaultReadingLevel);
    final duration =
        _coerceInt(draft?['duration_minutes'], StoryGenerationDefaults.defaultMinutes);

    if (!mounted) return;
    setState(() {
      _readingLevel = readingLevel.toDouble();
      _currentBand = ReadingLevelHelper.bandForLevel(readingLevel);
      _durationMinutes = duration;
      _profileChildName = profileName;
      _useChildName = useChildNamePref && (profileName?.isNotEmpty ?? false);
    });
  }

  Future<String?> _loadActiveProfileName() async {
    final activeId = await _profileService.getActiveProfileId();
    if (activeId == null) {
      return null;
    }
    final List<ChildProfile> profiles = await _profileService.loadProfiles();
    try {
      return profiles.firstWhere((p) => p.id == activeId).name;
    } catch (_) {
      return null;
    }
  }

  int _coerceInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  bool _coerceBool(dynamic value, bool fallback) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return fallback;
  }

  void _showLibrary() {
    if (!mounted) return;
    setState(() => _activeView = StoryLabView.library);
  }

  void _showGenerator() {
    if (!mounted) return;
    setState(() => _activeView = StoryLabView.generator);
  }

  List<GeneratedStoryRecord> _topPicks() {
    final picks = _savedStories
        .where((story) => story.readCount > 0 || story.isFavorite)
        .toList()
      ..sort((a, b) {
        final scoreA = (a.isFavorite ? 2 : 0) + a.readCount;
        final scoreB = (b.isFavorite ? 2 : 0) + b.readCount;
        if (scoreA == scoreB) {
          final aDate = a.lastReadAt ?? a.createdAt;
          final bDate = b.lastReadAt ?? b.createdAt;
          return bDate.compareTo(aDate);
        }
        return scoreB.compareTo(scoreA);
      });
    return picks.take(5).toList();
  }

  Future<void> _deleteStory(GeneratedStoryRecord story) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete story?'),
        content: Text('Remove "${story.chapter.title}" from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _storyService.deleteStory(story.id);
      await _loadStories();
    }
  }

  Future<void> _handleReadStory(GeneratedStoryRecord story) async {
    final updated = await _storyService.recordStoryOpened(story.id) ?? story;
    final metadataName = (updated.chapter.metadata?['child_name'] as String?)?.trim();
    final resolvedChildName =
        metadataName != null && metadataName.isNotEmpty ? metadataName : (_profileChildName ?? 'Reader');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryReaderScreenEnhanced(
          story: updated.chapter,
          profileId: _activeProfileIdOrDefault(),
          childName: resolvedChildName,
          generatedStory: updated,
        ),
      ),
    );
    await _loadStories();
    if (!mounted) return;
    final refreshed = _savedStories.firstWhere(
      (s) => s.id == updated.id,
      orElse: () => updated,
    );
    if ((refreshed.childRating ?? 0) == 0) {
      await _promptChildRating(refreshed);
    }
  }

  void _handleInlineRating(GeneratedStoryRecord story, int rating) {
    _updateStoryRating(story, rating);
  }

  Future<void> _updateStoryRating(GeneratedStoryRecord story, int rating) async {
    final next = rating.clamp(0, 5);
    await _storyService.setChildRating(story.id, next == 0 ? null : next);
    await _loadStories();
    if (!mounted) return;
    final message = next == 0
        ? 'Rating cleared'
        : 'Saved ${next.toString()}-star rating';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openStoryDetails(GeneratedStoryRecord story) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryDetailScreen(
          story: story,
          onRead: () {
            Navigator.of(context).pop();
            _handleReadStory(story);
          },
          onCopyInputs: () {
            Navigator.of(context).pop();
            _reuseStoryInputs(story);
          },
          onViewSummary: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StoryPlaybackScreen(story: story),
              ),
            );
          },
          onRate: (value) => _handleInlineRating(story, value),
          lastReadLabel: _lastReadLabel(context, story),
          deleteStory: () async {
            await _deleteStory(story);
          },
        ),
      ),
    );
    // Always reload when coming back, in case of rating changes or deletion
    await _loadStories();
  }

  String _activeProfileIdOrDefault() => 'generated_profile';


  void _onDraftFieldChanged() {
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 400), () {
      _persistDraft();
    });
  }

  Future<void> _persistDraft() async {
    final draft = {
      'reading_level': _readingLevel.round(),
      'duration_minutes': _durationMinutes,
      'parent_prompt': _parentPromptController.text.trim(),
      'child_context': _childContextController.text.trim(),
      'story_concept': _storyConceptController.text.trim(),
      'include_child_name': _useChildName,
    };
    try {
      await _preferencesService.saveStoryGeneratorDraft(draft);
      await _preferencesService.setStoryPersonalizationNotes(_childContextController.text.trim());
      await _preferencesService.setStoryUseChildName(_useChildName);
    } catch (error) {
      debugPrint('Failed to persist Story Lab draft: $error');
    }
  }

  Future<void> _toggleUseChildName(bool? value) async {
    final desired = value ?? false;
    final allowed = desired && (_profileChildName?.isNotEmpty ?? false);
    setState(() => _useChildName = allowed);
    await _preferencesService.setStoryUseChildName(allowed);
    _scheduleDraftSave();
  }

  void _updateReadingLevel(double value) {
    setState(() {
      _readingLevel = value;
      _currentBand = ReadingLevelHelper.bandForLevel(value.round());
    });
    _scheduleDraftSave();
  }

  Future<void> _generateStory() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isGenerating = true;
    });
    await _persistDraft();

    try {
      _generationStartTime = DateTime.now();
      _generationElapsed = Duration.zero;
      _generationTicker?.cancel();
      _generationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _generationStartTime == null) return;
        setState(() {
          _generationElapsed = DateTime.now().difference(_generationStartTime!);
        });
      });
      final band = ReadingLevelHelper.bandForLevel(_readingLevel.round());
      final childName = _useChildName ? _profileChildName : null;
      final request = StoryGenerationRequest(
        readingLevel: band.level,
        readingBand: band,
        durationMinutes: _durationMinutes,
        parentPrompt: _parentPromptController.text.trim(),
        childContext: _childContextController.text.trim(),
        storyConcept: _storyConceptController.text.trim().isEmpty ? null : _storyConceptController.text.trim(),
        childName: childName,
        includeChildName: childName != null,
      );

      final story = await _storyService.generateStory(request);
      setState(() {
        _latestStory = story;
      });
      await _loadStories();
      if (mounted) {
        _showLibrary();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story generated and saved to your library!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Story generation failed: $e')),
      );
    } finally {
      _generationTicker?.cancel();
      _generationTicker = null;
      _generationStartTime = null;
      _generationElapsed = Duration.zero;
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _reuseStoryInputs(GeneratedStoryRecord story) {
    final requestInputs = story.requestInputs;
    final readingLevel = _coerceInt(requestInputs?['reading_level'], story.readingLevel);
    final duration = _coerceInt(requestInputs?['duration_minutes'], story.durationMinutes);
    final parentPrompt = requestInputs?['parent_prompt']?.toString() ?? story.parentPrompt;
    final childContext = requestInputs?['child_context']?.toString() ?? story.childContext;
    final storyConcept = requestInputs?['story_concept']?.toString() ?? (story.storyConcept ?? '');
    final includeChildRequest =
        _coerceBool(requestInputs?['include_child_name'], story.includeChildName);
    final hasProfileName = _profileChildName?.isNotEmpty ?? false;
    final allowChildName = includeChildRequest && hasProfileName;

    setState(() {
      _readingLevel = readingLevel.toDouble();
      _currentBand = ReadingLevelHelper.bandForLevel(readingLevel);
      _durationMinutes = duration;
      _useChildName = allowChildName;
    });

    _parentPromptController.text = parentPrompt;
    _childContextController.text = childContext;
    _storyConceptController.text = storyConcept;

    _showGenerator();
    _scheduleDraftSave();

    final childNameNotice = includeChildRequest && !hasProfileName
        ? '\nAdd a profile name to include the child name.'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Story inputs copied from "${story.chapter.title}".$childNameNotice'),
      ),
    );
  }

  Future<void> _promptChildRating(GeneratedStoryRecord story) async {
    final rating = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _StoryRatingSheet(
        currentRating: story.childRating,
        storyTitle: story.chapter.title,
      ),
    );
    if (rating == null) {
      return;
    }
    await _updateStoryRating(story, rating);
  }

  @override
  Widget build(BuildContext context) {
    final isLibraryView = _activeView == StoryLabView.library;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Lab'),
        actions: [
          if (!isLibraryView)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: TextButton.icon(
                onPressed: _showLibrary,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Back to library'),
              ),
            ),
        ],
      ),
      floatingActionButton: isLibraryView
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: _showGenerator,
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    icon: const Icon(Icons.auto_fix_high, size: 26),
                    label: const Text(
                      'Create Adventure',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isLibraryView
            ? KeyedSubtree(key: const ValueKey('story_lab_library'), child: _buildLibraryPane())
            : KeyedSubtree(key: const ValueKey('story_lab_generator'), child: _buildGeneratorPane()),
      ),
    );
  }

  Widget _buildGeneratorPane() {
    final vocabPreview = ReadingLevelHelper.vocabularyForBand(_currentBand, wordsPerBand: 12);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepHeader(
                  step: 1,
                  title: 'Set the difficulty',
                  subtitle: 'Adjust reading level and pacing for tonight’s session.',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentBand.label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentBand.gradeBand} • ${_currentBand.lexileBand}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentBand.description,
                          style: const TextStyle(height: 1.3),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _readingLevel,
                                min: StoryGenerationDefaults.minReadingLevel.toDouble(),
                                max: StoryGenerationDefaults.maxReadingLevel.toDouble(),
                                divisions: StoryGenerationDefaults.maxReadingLevel -
                                    StoryGenerationDefaults.minReadingLevel,
                                label: 'Level ${_readingLevel.round()}',
                                onChanged: _updateReadingLevel,
                              ),
                            ),
                            Text('Level ${_readingLevel.round()}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _currentBand.hallmarks
                              .map(
                                (note) => Chip(
                                  label: Text(note),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Library reference: ${_currentBand.libraryReference}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: vocabPreview
                              .map(
                                (word) => Chip(
                                  label: Text(word),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Desired Length (minutes)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _durationMinutes.toDouble(),
                                min: StoryGenerationDefaults.minMinutes.toDouble(),
                                max: StoryGenerationDefaults.maxMinutes.toDouble(),
                                divisions:
                                    StoryGenerationDefaults.maxMinutes - StoryGenerationDefaults.minMinutes,
                                label: '$_durationMinutes min',
                            onChanged: (value) {
                              setState(() => _durationMinutes = value.round());
                              _scheduleDraftSave();
                            },
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '$_durationMinutes min',
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Stories are paced for read-aloud; choose between 5 and 20 minutes.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildStepHeader(
                  step: 2,
                  title: 'Story ingredients',
                  subtitle: 'Capture parent notes and child context (auto-saved).',
                ),
                _buildTextFieldCard(
                  label: 'Parent Notes / Prompt',
                  controller: _parentPromptController,
                  hint: 'What adventure do you want to tell tonight?',
                  minLines: 3,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Please describe your story idea' : null,
                ),
                const SizedBox(height: 12),
                _buildTextFieldCard(
                  label: 'Child Personalization',
                  controller: _childContextController,
                  hint: 'Interests, colors, animals, routines, calming phrases… (auto-saved)',
                  minLines: 3,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Please add child context' : null,
                ),
                const SizedBox(height: 12),
                _buildStepHeader(
                  step: 3,
                  title: 'Personal touches',
                  subtitle: 'Optional twists that make the story feel bespoke.',
                ),
                _buildTextFieldCard(
                  label: 'Story Idea / Scenario (optional)',
                  controller: _storyConceptController,
                  hint: 'e.g., “A river clean-up mission after school”',
                ),
                const SizedBox(height: 12),
                _buildChildNameToggle(),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateStory,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_stories),
                  label: Text(_isGenerating ? 'Generating…' : 'Generate Story'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_latestStory != null) ...[
                  const SizedBox(height: 24),
                  _buildStoryPreview(_latestStory!),
                ],
              ],
            ),
          ),
        ),
        Positioned.fill(child: _buildGeneratingOverlay()),
      ],
    );
  }

  Widget _buildTextFieldCard({
    required String label,
    required TextEditingController controller,
    String? hint,
    int minLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    String? Function(String?)? validator,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              minLines: minLines,
              maxLines: minLines + 4,
              textCapitalization: textCapitalization,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              validator: validator,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader({
    required int step,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $step',
            style: TextStyle(
              fontSize: 12,
              color: Colors.deepPurple.shade300,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildChildNameToggle() {
    final hasProfileName = _profileChildName?.isNotEmpty ?? false;
    return Card(
      child: CheckboxListTile(
        value: _useChildName && hasProfileName,
        onChanged: hasProfileName ? _toggleUseChildName : null,
        title: Text(
          hasProfileName
              ? 'Use child name from profile (${_profileChildName!})'
              : 'Use child name from profile',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          hasProfileName
              ? 'Checked: the story will refer to your child by name.'
              : 'No active profile name found. Select a profile to enable this option.',
        ),
      ),
    );
  }

  Widget _buildGeneratingOverlay() {
    return IgnorePointer(
      ignoring: !_isGenerating,
      child: AnimatedOpacity(
        opacity: _isGenerating ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBookLoadingAnimation(),
                const SizedBox(height: 16),
                const Text(
                  'Crafting your story…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gemini Flash is generating the next chapter',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Elapsed: ${_generationElapsed.inSeconds}s',
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookLoadingAnimation() {
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: _loadingController,
        builder: (context, child) {
          final angle = _loadingController.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: angle,
                child: Icon(
                  Icons.auto_stories,
                  size: 72,
                  color: Colors.amber.shade200,
                ),
              ),
              ...List.generate(3, (index) {
                final offsetAngle = angle + (index * 2 * math.pi / 3);
                final dx = 50 * math.cos(offsetAngle);
                final dy = 50 * math.sin(offsetAngle);
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Icon(
                    Icons.star,
                    size: 18 + index * 3,
                    color: Colors.amber.shade400.withOpacity(0.9 - (index * 0.2)),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStoryPreview(GeneratedStoryRecord story) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              story.chapter.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(story.summary),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text('${story.durationMinutes} min'),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.school, size: 16),
                  label: Text('Level ${story.readingLevel}'),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.percent, size: 16),
                  label: Text('${(story.familiarWordRatio * 100).toStringAsFixed(0)}% familiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoryPlaybackScreen(story: story),
                  ),
                );
              },
              child: const Text('Open Story'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryPane() {
    if (_savedStories.isEmpty) {
      return _buildEmptyLibraryState();
    }

    final totalStories = _savedStories.length;
    final totalMinutes = _savedStories.fold<int>(0, (sum, story) => sum + story.durationMinutes);
    final filteredStories = _filteredStories;
    
    // Create "Featured" list: Newest + Top Picks (deduplicated, ordered)
    final featuredStories = <GeneratedStoryRecord>[];
    if (_savedStories.isNotEmpty) {
      featuredStories.add(_savedStories.first);
    }
    for (final pick in _topPicks()) {
      final exists = featuredStories.any((story) => story.id == pick.id);
      if (!exists) {
        featuredStories.add(pick);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Header Info
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_stories, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Library',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$totalStories stories • $totalMinutes mins saved',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Unified Featured Carousel
        if (featuredStories.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Highlights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 340, // Tall enough for the hero card content
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.88),
              padEnds: false, // Start aligned to left (with padding handled by builder)
              itemCount: featuredStories.length,
              itemBuilder: (context, index) {
                // Add padding to separate cards
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 16 : 8, 
                    right: index == featuredStories.length - 1 ? 16 : 8
                  ),
                  child: _FeaturedStoryCard(
                    story: featuredStories[index],
                    isNewest: index == 0 && _savedStories.first.id == featuredStories[index].id,
                    lastReadLabel: _lastReadLabel(context, featuredStories[index]),
                    onTap: () => _openStoryDetails(featuredStories[index]),
                    onRead: () => _handleReadStory(featuredStories[index]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Filter Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildLibraryFilterControls(),
        ),
        const SizedBox(height: 12),

        // List Items
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: filteredStories.isEmpty
              ? [_buildEmptyFilterState()]
              : filteredStories.map(
                  (story) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLibraryItem(story),
                  ),
                ).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyLibraryState() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.menu_book, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
            Text(
              'Start your Story Lab library',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
              'Capture your child’s interests, then let Story Lab craft bedtime-ready adventures.',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showGenerator,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Create your first story'),
              ),
            ],
          ),
        ),
      );
    }


  Widget _buildLibraryFilterControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: StoryLibraryFilter.values.map((filter) {
            final selected = _libraryFilter == filter;
            return ChoiceChip(
              label: Text(_labelForFilter(filter)),
              selected: selected,
              onSelected: (_) {
                setState(() => _libraryFilter = filter);
              },
            );
          }).toList(),
        ),
      ],
    );
  }


  Widget _buildLibraryItem(GeneratedStoryRecord story) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow, // Flatter, modern background
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
        child: _StoryListTile(
          story: story,
          onOpen: () => _handleReadStory(story),
          onReuse: () => _reuseStoryInputs(story),
          onDelete: () => _deleteStory(story),
          onPreview: () => _openStoryDetails(story),
          onRate: (value) => _handleInlineRating(story, value),
          lastReadLabel: _lastReadLabel(context, story),
        ),
    );
  }

  Widget _buildEmptyFilterState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.auto_fix_high, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text(
            'No stories match this filter',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Try another filter or create a new story.'),
                ],
              ),
            );
  }

  String _labelForFilter(StoryLibraryFilter filter) {
    switch (filter) {
      case StoryLibraryFilter.all:
        return 'All';
      case StoryLibraryFilter.favorites:
        return 'Favorites';
      case StoryLibraryFilter.mostRead:
        return 'Most read';
      case StoryLibraryFilter.recent:
        return 'Recently read';
    }
  }

}

class _FeaturedStoryCard extends StatelessWidget {
  const _FeaturedStoryCard({
    required this.story,
    required this.isNewest,
    required this.lastReadLabel,
    required this.onTap,
    required this.onRead,
  });

  final GeneratedStoryRecord story;
  final bool isNewest;
  final String lastReadLabel;
  final VoidCallback onTap;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final familiarPercent = (story.familiarWordRatio * 100).toStringAsFixed(0);
    final readsMonth = story.readMoments
        .where((date) => date.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;

    // Gradient Logic: Newest gets the signature Indigo; others get a slightly varied hue
    // or we keep them consistent for a clean look. Let's keep consistent for now.
    final gradientColors = isDark
        ? [const Color(0xFF1E1B4B), const Color(0xFF4C1D95)]
        : [const Color(0xFF3730A3), const Color(0xFF7C3AED)];
    
    final onGradient = Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badge + Rating
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isNewest)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'Newest',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else if (readsMonth > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Trending',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(), // Keeps rating aligned right if no badge
                  
                  // Star Rating (Always Visible on Hero Cards)
                  StarRating(
                    rating: story.childRating ?? 0,
                    size: 18,
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white.withOpacity(0.3),
                    allowClear: false,
                  ),
                ],
              ),
              const Spacer(),
              
              // Title
              Hero(
                tag: 'story_title_${story.id}',
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    story.chapter.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: onGradient,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // Summary
              Text(
                story.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onGradient.withOpacity(0.85),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: onGradient.withOpacity(0.9)),
                  const SizedBox(width: 6),
                  Text(
                    lastReadLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onGradient.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Stats Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroChip(icon: Icons.schedule, label: '${story.durationMinutes}m'),
                  _HeroChip(icon: Icons.school, label: 'Lvl ${story.readingLevel}'),
                  _HeroChip(icon: Icons.percent, label: '$familiarPercent%'),
                ],
              ),
              const SizedBox(height: 20),
              
              // Action Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: onGradient,
                    foregroundColor: gradientColors.first,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: onRead,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded),
                      SizedBox(width: 8),
                      Text('Read Now'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
class _StoryListTile extends StatelessWidget {
  const _StoryListTile({
    required this.story,
    required this.onOpen,
    required this.onReuse,
    required this.onDelete,
    required this.onPreview,
    required this.onRate,
    required this.lastReadLabel,
  });

  final GeneratedStoryRecord story;
  final VoidCallback onOpen;
  final VoidCallback onReuse;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final ValueChanged<int> onRate;
  final String lastReadLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPreview,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              story.chapter.title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              story.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _tonalMetricChip(context, Icons.schedule, '${story.durationMinutes} min'),
                _tonalMetricChip(context, Icons.school, 'Level ${story.readingLevel}'),
                _tonalMetricChip(context, Icons.history, _readsThisMonthText(story)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timelapse, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  lastReadLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildRatingRow(context),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onOpen,
                    child: const Text('Read now'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onPreview,
                  child: const Text('Details'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.error.withOpacity(0.9),
                  tooltip: 'Delete story',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tonalMetricChip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(BuildContext context) {
    return StarRating(
      rating: story.childRating ?? 0,
      size: 24,
      allowClear: true,
      onRatingChanged: onRate,
    );
  }

  String _readsThisMonthText(GeneratedStoryRecord story) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final count = story.readMoments.where((moment) => moment.isAfter(cutoff)).length;
    return count == 0 ? 'New' : '${count}× this month';
  }
}

class _StoryRatingSheet extends StatelessWidget {
  const _StoryRatingSheet({
    required this.currentRating,
    required this.storyTitle,
  });

  final int? currentRating;
  final String storyTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rate "$storyTitle"',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Center(
              child: StarRating(
                rating: currentRating ?? 0,
                size: 40,
                allowClear: true,
                onRatingChanged: (value) => Navigator.of(context).pop(value),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap a star to save. Tap the selected star again to clear.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(0),
                  child: const Text('Clear rating'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryDetailScreen extends StatefulWidget {
  const _StoryDetailScreen({
    required this.story,
    required this.onRead,
    required this.onCopyInputs,
    required this.deleteStory,
    required this.onViewSummary,
    required this.onRate,
    required this.lastReadLabel,
  });

  final GeneratedStoryRecord story;
  final VoidCallback onRead;
  final VoidCallback onCopyInputs;
  final Future<void> Function() deleteStory;
  final VoidCallback onViewSummary;
  final ValueChanged<int> onRate;
  final String lastReadLabel;

  @override
  State<_StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<_StoryDetailScreen> {
  late int _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.story.childRating ?? 0;
  }

  Future<void> _handleRatingTap(int value) async {
    setState(() {
      _currentRating = value;
    });
    widget.onRate(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradientColors = isDark
        ? [const Color(0xFF1E1B4B), const Color(0xFF4C1D95)]
        : [const Color(0xFF3730A3), const Color(0xFF7C3AED)];
    final familiarPercent = (widget.story.familiarWordRatio * 100).toStringAsFixed(0);
    final readsMonth = widget.story.readMoments
        .where((moment) => moment.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: gradientColors.first,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Delete Story',
                onPressed: () async {
                  await widget.deleteStory();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      bottom: 60,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.school, color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Level ${widget.story.readingLevel}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
            ),
          ],
        ),
                          ),
                          const SizedBox(height: 12),
                          Hero(
                            tag: 'story_title_${widget.story.id}',
                            child: Material(
                              color: Colors.transparent,
                              child: Text(
                                widget.story.chapter.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailStat(context, Icons.schedule, '${widget.story.durationMinutes}m', 'Duration'),
                      _buildDetailStat(context, Icons.percent, '$familiarPercent%', 'Familiar'),
                      _buildDetailStat(
                        context,
                        Icons.history,
                        readsMonth.toString(),
                        'Reads (30d)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.timelapse, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        widget.lastReadLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Story Summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.story.summary,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Your Rating',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: StarRating(
                      rating: _currentRating,
                      size: 38,
                      allowClear: true,
                      onRatingChanged: _handleRatingTap,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onRead,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Read Now'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onCopyInputs,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Create Similar Story'),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(BuildContext context, IconData icon, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

}
