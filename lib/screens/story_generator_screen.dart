import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/child_profile.dart';
import '../models/story_generation_models.dart';
import '../models/story_models.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../services/story_cover_service.dart';
import '../services/story_generator_service.dart';
import '../services/story_panel_art_service.dart';
import '../utils/reading_level_helper.dart';
import '../utils/story_text_utils.dart';
import '../widgets/star_rating.dart';
import 'story_playback_screen.dart';
import 'story_reader_screen_enhanced.dart';
import 'story_revision_screen.dart';

enum StoryLabView { library, generator }

enum StoryLibraryFilter { all, favorites, mostRead, recent }

class StoryGeneratorScreen extends StatefulWidget {
  const StoryGeneratorScreen({
    super.key,
    this.initialView = StoryLabView.library,
  });

  final StoryLabView initialView;

  @override
  State<StoryGeneratorScreen> createState() => _StoryGeneratorScreenState();
}

class _StoryGeneratorScreenState extends State<StoryGeneratorScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _parentPromptController = TextEditingController();
  final _childContextController = TextEditingController();
  final _storyConceptController = TextEditingController();

  final StoryGeneratorService _storyService = StoryGeneratorService();
  final PreferencesService _preferencesService = PreferencesService();
  final ProfileService _profileService = ProfileService();
  final StoryCoverService _coverService = StoryCoverService();
  final StoryPanelArtService _panelArtService = StoryPanelArtService();
  late final AnimationController _loadingController;
  late StoryLabView _activeView;

  bool _isGenerating = false;
  int _durationMinutes = StoryGenerationDefaults.defaultMinutes;
  double _readingLevel = StoryGenerationDefaults.defaultReadingLevel.toDouble();
  ReadingBand _currentBand = ReadingLevelHelper.bandForLevel(
    StoryGenerationDefaults.defaultReadingLevel,
  );
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

  List<GeneratedStoryRecord> get _favoriteStories => _savedStories
      .where((story) => !story.isBuiltIn && (story.childRating ?? 0) >= 3)
      .toList();

  int get _personalStoryCount =>
      _savedStories.where((story) => !story.isBuiltIn).length;

  int get _builtInStoryCount =>
      _savedStories.where((story) => story.isBuiltIn).length;

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
    if (now.year == last.year &&
        now.month == last.month &&
        now.day == last.day) {
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
    final fallbackUseChildName = await _preferencesService
        .getStoryUseChildName();
    final useChildNamePref = _coerceBool(
      draft?['include_child_name'],
      fallbackUseChildName,
    );
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

    final readingLevel = _coerceInt(
      draft?['reading_level'],
      StoryGenerationDefaults.defaultReadingLevel,
    );
    final duration = _coerceInt(
      draft?['duration_minutes'],
      StoryGenerationDefaults.defaultMinutes,
    );

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
    final picks =
        _savedStories
            .where(
              (story) =>
                  !story.isBuiltIn && (story.readCount > 0 || story.isFavorite),
            )
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
    if (story.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in stories cannot be removed.')),
      );
      return;
    }
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
    final GeneratedStoryRecord handleStory;
    if (story.isBuiltIn) {
      handleStory = story;
    } else {
      final updated = await _storyService.recordStoryOpened(story.id);
      handleStory = updated ?? story;
    }
    final metadataName =
        (handleStory.chapter.metadata?['child_name'] as String?)?.trim();
    final resolvedChildName = metadataName != null && metadataName.isNotEmpty
        ? metadataName
        : (_profileChildName ?? 'Reader');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryReaderScreenEnhanced(
          story: handleStory.chapter,
          profileId: _activeProfileIdOrDefault(),
          childName: resolvedChildName,
          generatedStory: handleStory,
        ),
      ),
    );
    if (story.isBuiltIn) {
      return;
    }
    await _loadStories();
    if (!mounted) return;
    final refreshed = _savedStories.firstWhere(
      (s) => s.id == handleStory.id,
      orElse: () => handleStory,
    );
    if ((refreshed.childRating ?? 0) == 0) {
      await _promptChildRating(refreshed);
    }
  }

  void _handleInlineRating(GeneratedStoryRecord story, int rating) {
    _updateStoryRating(story, rating);
  }

  Future<void> _updateStoryRating(
    GeneratedStoryRecord story,
    int rating,
  ) async {
    if (story.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in stories can\'t be rated.')),
      );
      return;
    }
    final next = rating.clamp(0, 5);
    await _storyService.setChildRating(story.id, next == 0 ? null : next);
    await _loadStories();
    if (!mounted) return;
    final message = next == 0
        ? 'Rating cleared'
        : 'Saved ${next.toString()}-star rating';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openStoryDetails(GeneratedStoryRecord story) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryDetailScreen(
          story: story,
          storyService: _storyService,
          coverService: _coverService,
          panelArtService: _panelArtService,
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
      await _preferencesService.setStoryPersonalizationNotes(
        _childContextController.text.trim(),
      );
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
        storyConcept: _storyConceptController.text.trim().isEmpty
            ? null
            : _storyConceptController.text.trim(),
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
          const SnackBar(
            content: Text('Story generated and saved to your library!'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Story generation failed: $e')));
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
    if (story.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in stories are read only.')),
      );
      return;
    }
    final requestInputs = story.requestInputs;
    final readingLevel = _coerceInt(
      requestInputs?['reading_level'],
      story.readingLevel,
    );
    final duration = _coerceInt(
      requestInputs?['duration_minutes'],
      story.durationMinutes,
    );
    final parentPrompt =
        requestInputs?['parent_prompt']?.toString() ?? story.parentPrompt;
    final childContext =
        requestInputs?['child_context']?.toString() ?? story.childContext;
    final storyConcept =
        requestInputs?['story_concept']?.toString() ??
        (story.storyConcept ?? '');
    final includeChildRequest = _coerceBool(
      requestInputs?['include_child_name'],
      story.includeChildName,
    );
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
        content: Text(
          'Story inputs copied from "${story.chapter.title}".$childNameNotice',
        ),
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
        title: const Text('Story Time'),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.35),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isLibraryView
            ? KeyedSubtree(
                key: const ValueKey('story_lab_library'),
                child: _buildLibraryPane(),
              )
            : KeyedSubtree(
                key: const ValueKey('story_lab_generator'),
                child: _buildGeneratorPane(),
              ),
      ),
    );
  }

  Widget _buildGeneratorPane() {
    final vocabPreview = ReadingLevelHelper.vocabularyForBand(
      _currentBand,
      wordsPerBand: 12,
    );
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
                  subtitle:
                      'Adjust reading level and pacing for tonight’s session.',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentBand.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
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
                                min: StoryGenerationDefaults.minReadingLevel
                                    .toDouble(),
                                max: StoryGenerationDefaults.maxReadingLevel
                                    .toDouble(),
                                divisions:
                                    StoryGenerationDefaults.maxReadingLevel -
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
                              .map((note) => Chip(label: Text(note)))
                              .toList(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Library reference: ${_currentBand.libraryReference}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: vocabPreview
                              .map((word) => Chip(label: Text(word)))
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
                                min: StoryGenerationDefaults.minMinutes
                                    .toDouble(),
                                max: StoryGenerationDefaults.maxMinutes
                                    .toDouble(),
                                divisions:
                                    StoryGenerationDefaults.maxMinutes -
                                    StoryGenerationDefaults.minMinutes,
                                label: '$_durationMinutes min',
                                onChanged: (value) {
                                  setState(
                                    () => _durationMinutes = value.round(),
                                  );
                                  _scheduleDraftSave();
                                },
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '$_durationMinutes min',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
                  subtitle:
                      'Capture parent notes and child context (auto-saved).',
                ),
                _buildTextFieldCard(
                  label: 'Parent Notes / Prompt',
                  controller: _parentPromptController,
                  hint: 'What adventure do you want to tell tonight?',
                  minLines: 3,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please describe your story idea'
                      : null,
                ),
                const SizedBox(height: 12),
                _buildTextFieldCard(
                  label: 'Child Personalization',
                  controller: _childContextController,
                  hint:
                      'Interests, colors, animals, routines, calming phrases… (auto-saved)',
                  minLines: 3,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please add child context'
                      : null,
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
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
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
                  style: const TextStyle(color: Colors.white70),
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
                    color: Colors.amber.shade400.withOpacity(
                      0.9 - (index * 0.2),
                    ),
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
                  label: Text(
                    '${(story.familiarWordRatio * 100).toStringAsFixed(0)}% familiar',
                  ),
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
    final personalMinutes = _savedStories
        .where((story) => !story.isBuiltIn)
        .fold<int>(0, (sum, story) => sum + story.durationMinutes);
    final filteredStories = _filteredStories;
    final libraryStats = _personalStoryCount > 0
        ? '${_personalStoryCount} personal • $_builtInStoryCount built-in • $personalMinutes personal mins'
        : '$_builtInStoryCount built-in stories ready to read';

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
                child: Icon(
                  Icons.auto_stories,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Library ($totalStories)',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    libraryStats,
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 340, // Tall enough for the hero card content
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.88),
              padEnds:
                  false, // Start aligned to left (with padding handled by builder)
              itemCount: featuredStories.length,
              itemBuilder: (context, index) {
                // Add padding to separate cards
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 16 : 8,
                    right: index == featuredStories.length - 1 ? 16 : 8,
                  ),
                  child: _FeaturedStoryCard(
                    story: featuredStories[index],
                    isNewest:
                        index == 0 &&
                        _savedStories.first.id == featuredStories[index].id,
                    lastReadLabel: _lastReadLabel(
                      context,
                      featuredStories[index],
                    ),
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
                : filteredStories
                      .map(
                        (story) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildLibraryItem(story),
                        ),
                      )
                      .toList(),
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
              'Start your Story Time library',
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
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
    final radius = BorderRadius.circular(14);
    final outline = theme.colorScheme.outlineVariant.withOpacity(0.45);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: outline, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.surfaceVariant.withOpacity(0.4),
                      theme.colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
              ),
            ),
            _StoryListTile(
              story: story,
              onOpen: () => _handleReadStory(story),
              onReuse: () => _reuseStoryInputs(story),
              onDelete: () => _deleteStory(story),
              onPreview: () => _openStoryDetails(story),
              onRate: (value) => _handleInlineRating(story, value),
              lastReadLabel: _lastReadLabel(context, story),
            ),
          ],
        ),
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
        .where(
          (date) =>
              date.isAfter(DateTime.now().subtract(const Duration(days: 30))),
        )
        .length;
    final gradientColors = isDark
        ? [const Color(0xFF1E1B4B), const Color(0xFF4C1D95)]
        : [const Color(0xFF3730A3), const Color(0xFF7C3AED)];
    final onGradient = Colors.white;
    final radius = BorderRadius.circular(28);

    final coverDecoration = BoxDecoration(
      gradient: story.coverImagePath == null
          ? LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      image: story.coverImagePath != null
          ? DecorationImage(
              image: FileImage(File(story.coverImagePath!)),
              fit: BoxFit.cover,
            )
          : null,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 22,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(child: DecoratedBox(decoration: coverDecoration)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.black.withOpacity(0.18),
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1.1,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isNewest
                                    ? Icons.auto_awesome
                                    : Icons.local_fire_department,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isNewest
                                    ? 'Newest'
                                    : readsMonth > 0
                                    ? 'Trending'
                                    : 'Featured',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StarRating(
                          rating: story.childRating ?? 0,
                          size: 18,
                          activeColor: Colors.amber,
                          inactiveColor: Colors.white.withOpacity(0.3),
                          allowClear: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          Text(
                            story.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onGradient.withOpacity(0.82),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 16,
                                color: onGradient.withOpacity(0.9),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                lastReadLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onGradient.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroChip(
                                icon: Icons.schedule,
                                label: '${story.durationMinutes}m',
                              ),
                              _HeroChip(
                                icon: Icons.school,
                                label: 'Lvl ${story.readingLevel}',
                              ),
                              _HeroChip(
                                icon: Icons.percent,
                                label: '$familiarPercent%',
                              ),
                            ],
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: onGradient,
                                foregroundColor: gradientColors.first,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
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
                  ],
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

class _BookCoverPreview extends StatelessWidget {
  const _BookCoverPreview({
    required this.imagePath,
    this.width = 82,
    this.borderRadius = 16,
    this.showShadow = false,
  });

  final String? imagePath;
  final double width;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final height = width / 3 * 4;
    final scheme = Theme.of(context).colorScheme;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final borderColor = scheme.outlineVariant.withOpacity(0.45);
    final borderRadiusValue = BorderRadius.circular(borderRadius);
    final pageEdgeWidth = width * 0.12;

    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withOpacity(0.25),
            scheme.secondary.withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadiusValue,
      ),
      child: Icon(
        Icons.menu_book_outlined,
        size: width * 0.4,
        color: scheme.onSurfaceVariant.withOpacity(0.75),
      ),
    );

    Widget imageLayer;
    if (hasImage) {
      imageLayer = Image.file(
        File(imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else {
      imageLayer = placeholder;
    }

    final cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadiusValue,
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadiusValue,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageLayer,
            Container(
              decoration: BoxDecoration(
                gradient: hasImage
                    ? LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.08),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      )
                    : null,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 26,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.08),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return SizedBox(
      width: width + pageEdgeWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            top: 6,
            bottom: 6,
            width: pageEdgeWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(borderRadius * 0.8),
                  bottomRight: Radius.circular(borderRadius * 0.8),
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.9),
                    Colors.grey.shade200,
                    Colors.white.withOpacity(0.75),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: pageEdgeWidth - 4,
            top: 0,
            bottom: 0,
            child: cover,
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
    final isBuiltIn = story.isBuiltIn;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPreview,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCoverPreview(imagePath: story.coverImagePath),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.chapter.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    story.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (isBuiltIn) ...[
                    const SizedBox(height: 6),
                    Chip(
                      label: const Text('Built-in'),
                      avatar: const Icon(Icons.lock, size: 16),
                      side: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.4),
                      ),
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.1,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _tonalMetricChip(
                        context,
                        Icons.schedule,
                        '${story.durationMinutes} min',
                      ),
                      _tonalMetricChip(
                        context,
                        Icons.school,
                        'Level ${story.readingLevel}',
                      ),
                      _tonalMetricChip(
                        context,
                        Icons.history,
                        _readsThisMonthText(story),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.timelapse,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                  _buildRatingRow(context, isBuiltIn),
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
                      if (!isBuiltIn)
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

  Widget _buildRatingRow(BuildContext context, bool isBuiltIn) {
    if (isBuiltIn) {
      return Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          const Text('Built-in story (read only)'),
        ],
      );
    }
    return StarRating(
      rating: story.childRating ?? 0,
      size: 24,
      allowClear: true,
      onRatingChanged: onRate,
    );
  }

  String _readsThisMonthText(GeneratedStoryRecord story) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final count = story.readMoments
        .where((moment) => moment.isAfter(cutoff))
        .length;
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

class _EditStoryTitleDialog extends StatefulWidget {
  const _EditStoryTitleDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_EditStoryTitleDialog> createState() => _EditStoryTitleDialogState();
}

class _EditStoryTitleDialogState extends State<_EditStoryTitleDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit story title'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
          hintText: 'Enter a new title',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StoryDetailScreen extends StatefulWidget {
  const _StoryDetailScreen({
    required this.story,
    required this.storyService,
    required this.coverService,
    required this.panelArtService,
    required this.onRead,
    required this.onCopyInputs,
    required this.deleteStory,
    required this.onViewSummary,
    required this.onRate,
    required this.lastReadLabel,
  });

  final GeneratedStoryRecord story;
  final StoryGeneratorService storyService;
  final StoryCoverService coverService;
  final StoryPanelArtService panelArtService;
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
  late GeneratedStoryRecord _story;
  late int _currentRating;
  bool _isUpdatingCover = false;
  bool _isUpdatingPanelArt = false;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _currentRating = _story.childRating ?? 0;
  }

  int get _expectedPanelCount =>
      _countNarrationParagraphs(_story.chapter);

  Future<void> _handleRatingTap(int value) async {
    setState(() {
      _currentRating = value;
    });
    widget.onRate(value);
  }

  Future<void> _changeCover() async {
    if (_story.isBuiltIn || _isUpdatingCover) return;
    setState(() {
      _isUpdatingCover = true;
    });
    try {
      final coverPath = await widget.coverService.pickAndStoreCover(
        context: context,
        storyId: _story.id,
        existingCoverPath: _story.coverImagePath,
      );
      if (coverPath == null) {
        return;
      }
      final updated = await widget.storyService.updateStoryCover(
        _story.id,
        coverPath,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update cover: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingCover = false;
        });
      } else {
        _isUpdatingCover = false;
      }
    }
  }

  Future<void> _removeCover() async {
    if (_story.coverImagePath == null || _isUpdatingCover) return;
    setState(() {
      _isUpdatingCover = true;
    });
    try {
      await widget.coverService.deleteCover(_story.coverImagePath);
      final updated = await widget.storyService.updateStoryCover(
        _story.id,
        null,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to remove cover: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingCover = false;
        });
      } else {
        _isUpdatingCover = false;
      }
    }
  }

  Future<void> _importPanelArt() async {
    if (_story.isBuiltIn || _isUpdatingPanelArt) return;
    if (_expectedPanelCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Update the story text first so we know how many passages need art.',
          ),
        ),
      );
      return;
    }
    setState(() => _isUpdatingPanelArt = true);
    try {
      final art = await widget.panelArtService.pickAndStorePanelArt(
        context: context,
        storyId: _story.id,
        panelCount: _expectedPanelCount,
        existingArt: _story.panelArt,
      );
      if (art == null) {
        return;
      }
      final updated = await widget.storyService.updateStoryPanelArt(
        _story.id,
        art,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scene artwork imported!')),
        );
      }
    } on StoryPanelArtException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to import panels: $e')),
      );
    } finally {
      if (!mounted) {
        _isUpdatingPanelArt = false;
        return;
      }
      setState(() => _isUpdatingPanelArt = false);
    }
  }

  Future<void> _removePanelArt() async {
    if (_story.panelArt == null || _isUpdatingPanelArt) return;
    setState(() => _isUpdatingPanelArt = true);
    final existing = _story.panelArt;
    try {
      await widget.panelArtService.deletePanelArt(existing);
      final updated = await widget.storyService.updateStoryPanelArt(
        _story.id,
        null,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scene artwork removed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove artwork: $e')),
      );
    } finally {
      if (!mounted) {
        _isUpdatingPanelArt = false;
        return;
      }
      setState(() => _isUpdatingPanelArt = false);
    }
  }

  Future<void> _openCoverLightbox() async {
    final path = _story.coverImagePath;
    if (path == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withOpacity(0.9),
            child: Center(
              child: Hero(
                tag: 'story_cover_${_story.id}',
                child: InteractiveViewer(
                  maxScale: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.file(File(path), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openStoryEditor() async {
    if (_story.isBuiltIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in stories cannot be edited.')),
      );
      return;
    }

    final updated = await Navigator.of(context).push<GeneratedStoryRecord>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StoryEditorScreen(
          story: _story,
          storyService: widget.storyService,
          coverService: widget.coverService,
          panelArtService: widget.panelArtService,
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _story = updated;
        _currentRating = updated.childRating ?? _currentRating;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = _story;
    final isDark = theme.brightness == Brightness.dark;
    final isBuiltIn = story.isBuiltIn;
    final gradientColors = isDark
        ? [const Color(0xFF1E1B4B), const Color(0xFF4C1D95)]
        : [const Color(0xFF3730A3), const Color(0xFF7C3AED)];
    final familiarPercent = (story.familiarWordRatio * 100).toStringAsFixed(0);
    final readsMonth = story.readMoments
        .where(
          (moment) =>
              moment.isAfter(DateTime.now().subtract(const Duration(days: 30))),
        )
        .length;

    final coverShowcaseWidth = (MediaQuery.of(context).size.width * 0.55)
        .clamp(160.0, 280.0)
        .toDouble();

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
                icon: const Icon(Icons.ios_share, color: Colors.white),
                tooltip: 'Share story',
                onPressed: _shareStory,
              ),
              if (!isBuiltIn)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  tooltip: 'Rename story',
                  onPressed: _promptEditTitle,
                ),
              if (!isBuiltIn)
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (story.coverImagePath != null)
                      Image.file(
                        File(story.coverImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: gradientColors.first),
                      ),
                    if (story.coverImagePath != null)
                      BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(color: Colors.black.withOpacity(0)),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            gradientColors.first.withOpacity(0.7),
                            gradientColors.last.withOpacity(0.4),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 60,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.school,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Level ${story.readingLevel}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isBuiltIn) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StarRating(
                                    rating: _currentRating,
                                    size: 18,
                                    allowClear: true,
                                    activeColor: Colors.amberAccent,
                                    inactiveColor: Colors.white.withOpacity(
                                      0.35,
                                    ),
                                    onRatingChanged: _handleRatingTap,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _currentRating > 0
                                        ? '${_currentRating}/5'
                                        : 'Tap to rate',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isBuiltIn) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Built-in story',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Hero(
                            tag: 'story_title_${story.id}',
                            child: Material(
                              color: Colors.transparent,
                              child: Text(
                                story.chapter.title,
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
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Version v${story.version}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
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
                      _buildDetailStat(
                        context,
                        Icons.schedule,
                        '${story.durationMinutes}m',
                        'Duration',
                      ),
                      _buildDetailStat(
                        context,
                        Icons.percent,
                        '$familiarPercent%',
                        'Familiar',
                      ),
                      _buildDetailStat(
                        context,
                        Icons.history,
                        readsMonth.toString(),
                        'Reads (30d)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isBuiltIn) ...[
                    Text(
                      'Your rating',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StarRating(
                      rating: _currentRating,
                      size: 42,
                      allowClear: true,
                      onRatingChanged: _handleRatingTap,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Icon(
                        Icons.timelapse,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.lastReadLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onRead,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Read Now'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Story Summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    story.summary,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Book cover',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: story.coverImagePath != null
                              ? _openCoverLightbox
                              : null,
                          child: Hero(
                            tag: 'story_cover_${story.id}',
                            child: _BookCoverPreview(
                              imagePath: story.coverImagePath,
                              width: coverShowcaseWidth,
                              borderRadius: 28,
                              showShadow: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!isBuiltIn)
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _isUpdatingCover
                                    ? null
                                    : _changeCover,
                                icon: _isUpdatingCover
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.brush_outlined),
                                label: Text(
                                  story.coverImagePath == null
                                      ? 'Add cover art'
                                      : 'Update cover art',
                                ),
                              ),
                              if (story.coverImagePath != null)
                                TextButton.icon(
                                  onPressed: _isUpdatingCover
                                      ? null
                                      : _removeCover,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remove cover'),
                                ),
                              FilledButton.tonalIcon(
                                onPressed: _openStoryEditor,
                                icon: const Icon(Icons.edit_note_outlined),
                                label: const Text('Edit story text'),
                              ),
                            ],
                          ),
                        if (isBuiltIn)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Built-in stories use default artwork.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Scene artwork',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPanelArtSection(context, theme, isBuiltIn),
                  const SizedBox(height: 24),
                  if (!isBuiltIn) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onCopyInputs,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Create Similar Story'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openRevisionFlow,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Revise Story'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPanelArtSection(
    BuildContext context,
    ThemeData theme,
    bool isBuiltIn,
  ) {
    final art = _story.panelArt;
    final panelPaths = art?.panelImagePaths ?? const <String>[];
    final hasArt = panelPaths.isNotEmpty;
    final expected = _expectedPanelCount;
    final readyCount = hasArt ? panelPaths.length : 0;
    final targetCount = expected == 0 ? readyCount : expected;
    final statusText = hasArt
        ? 'Ready for $readyCount${targetCount > 0 ? '/$targetCount' : ''} passages.'
        : expected == 0
            ? 'Add story paragraphs so we know how many panels to expect.'
            : 'Expecting $expected square panels. Import your AI collage to unlock reveals.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasArt && art != null)
                      Text(
                        'Imported ${panelPaths.length} panels on '
                        '${MaterialLocalizations.of(context).formatShortDate(art.importedAt)}.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          hasArt
              ? _buildPanelArtPreviewGrid(panelPaths)
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.3),
                    ),
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.photo_size_select_large_outlined,
                        size: 38,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Import a perfectly square grid (left-to-right, top-to-bottom) to match each paragraph.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 12),
          Text(
            expected == 0
                ? 'Paragraph count unavailable—edit the story text to unlock scene art.'
                : 'Paragraphs in this story: $expected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (!isBuiltIn)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isUpdatingPanelArt ? null : _importPanelArt,
                  icon: _isUpdatingPanelArt
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.grid_on),
                  label: Text(hasArt ? 'Update scene art' : 'Import scene art'),
                ),
                if (hasArt)
                  OutlinedButton.icon(
                    onPressed: _isUpdatingPanelArt ? null : _removePanelArt,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove art'),
                  ),
              ],
            )
          else
            Text(
              'Scene artwork can be customized on your own generated stories.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelArtPreviewGrid(List<String> paths) {
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }
    return _PanelThumbnailGrid(paths: paths);
  }

  Future<void> _shareStory() async {
    final shareText = StoryTextUtils.shareableStoryText(_story);
    if (shareText.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story text is unavailable to share right now.'),
        ),
      );
      return;
    }
    await Share.share(shareText, subject: _story.chapter.title);
  }

  Future<void> _promptEditTitle() async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) =>
          _EditStoryTitleDialog(initialTitle: _story.chapter.title),
    );
    if (newTitle == null ||
        newTitle.isEmpty ||
        newTitle == _story.chapter.title) {
      return;
    }
    try {
      final updated = await widget.storyService.updateStoryTitle(
        _story.id,
        newTitle,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update title: $e')));
    }
  }

  Future<void> _openRevisionFlow() async {
    final updated = await Navigator.of(context).push<GeneratedStoryRecord>(
      MaterialPageRoute(
        builder: (_) => StoryRevisionScreen(
          story: _story,
          storyService: widget.storyService,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _story = updated;
        _currentRating = updated.childRating ?? _currentRating;
      });
    }
  }
}

class _StoryEditorScreen extends StatefulWidget {
  const _StoryEditorScreen({
    required this.story,
    required this.storyService,
    required this.coverService,
    required this.panelArtService,
  });

  final GeneratedStoryRecord story;
  final StoryGeneratorService storyService;
  final StoryCoverService coverService;
  final StoryPanelArtService panelArtService;

  @override
  State<_StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _BeatEditorState {
  final StoryBeat beat;
  final TextEditingController controller;
  _BeatEditorState({required this.beat, required this.controller});
}

class _StoryEditorScreenState extends State<_StoryEditorScreen> {
  late GeneratedStoryRecord _story;
  late List<_BeatEditorState> _beatEditors;
  bool _isDirty = false;
  bool _isSavingText = false;
  bool _isUpdatingCover = false;
  bool _isUpdatingPanelArt = false;
  
  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _initBeatEditors();
  }

  void _initBeatEditors() {
    _beatEditors = _story.chapter.beats.map((beat) {
      return _BeatEditorState(
        beat: beat,
        controller: TextEditingController(text: beat.text)
          ..addListener(_onTextChanged),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final editor in _beatEditors) {
      editor.controller.removeListener(_onTextChanged);
      editor.controller.dispose();
    }
    super.dispose();
  }

  int get _expectedPanelCount =>
      _countNarrationParagraphs(_story.chapter);

  Future<bool> _handleWillPop() async {
    Navigator.of(context).pop(_story);
    return false;
  }

  void _onTextChanged() {
    // Check if any controller is dirty compared to its beat
    bool anyDirty = false;
    for (final editor in _beatEditors) {
      if (editor.controller.text.trimRight() != editor.beat.text.trimRight()) {
        anyDirty = true;
        break;
      }
    }
    // Also check assignments? Assignments are saved immediately via updateStoryPanelArt
    // So _isDirty tracks text changes primarily.
    
    if (anyDirty == _isDirty) return;
    setState(() {
      _isDirty = anyDirty;
    });
  }

  // Reconstruct the full story text from the individual editors
  // This is used if we were saving as a raw string, but we are moving to structured updates.
  // However, existing service expects `updateStoryText` which takes a full string.
  // We might need to update the service or reconstruct the string carefully.
  // The `StoryGeneratorService.updateStoryText` parses the string back into beats.
  // If we want to preserve structure exactly, we should ideally have `updateStoryBeats`.
  // For now, we'll reconstruct the string.
  String _reconstructFullStoryText() {
    final buffer = StringBuffer();
    for (final editor in _beatEditors) {
      final text = editor.controller.text.trimRight();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln(text);
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  void _resetDraft() {
    setState(() {
      _initBeatEditors(); // Re-init from _story
      _isDirty = false;
    });
  }

  Future<void> _saveStoryText() async {
    if (_isSavingText) return;
    
    // Validate
    bool hasContent = false;
    for (final editor in _beatEditors) {
      if (editor.controller.text.trim().isNotEmpty) {
        hasContent = true;
        break;
      }
    }
    
    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Story text cannot be empty.')),
      );
      return;
    }

    setState(() {
      _isSavingText = true;
    });
    
    try {
      final fullText = _reconstructFullStoryText();
      final updated = await widget.storyService.updateStoryText(
        _story.id,
        fullText,
      );
      if (updated != null && mounted) {
        setState(() {
          _story = updated;
          _isDirty = false;
          _initBeatEditors(); // Re-sync editors with new parsed structure
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Story text saved.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save story text: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isSavingText = false);
    }
  }

  Future<void> _changeCover() async {
    if (_isUpdatingCover) return;
    setState(() => _isUpdatingCover = true);
    try {
      final coverPath = await widget.coverService.pickAndStoreCover(
        context: context,
        storyId: _story.id,
        existingCoverPath: _story.coverImagePath,
      );
      if (coverPath == null) return;
      final updated = await widget.storyService.updateStoryCover(
        _story.id,
        coverPath,
      );
      if (updated != null && mounted) {
        setState(() => _story = updated);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cover updated.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update cover: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isUpdatingCover = false);
    }
  }

  Future<void> _removeCover() async {
    if (_story.coverImagePath == null || _isUpdatingCover) return;
    setState(() => _isUpdatingCover = true);
    try {
      await widget.coverService.deleteCover(_story.coverImagePath);
      final updated = await widget.storyService.updateStoryCover(
        _story.id,
        null,
      );
      if (updated != null && mounted) {
        setState(() => _story = updated);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cover removed.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to remove cover: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isUpdatingCover = false);
    }
  }

  Future<void> _importPanelArt() async {
    if (_isUpdatingPanelArt) return;
    if (_expectedPanelCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add or edit the story text so we can count the passages before importing art.',
          ),
        ),
      );
      return;
    }
    setState(() => _isUpdatingPanelArt = true);
    try {
      final art = await widget.panelArtService.pickAndStorePanelArt(
        context: context,
        storyId: _story.id,
        panelCount: _expectedPanelCount,
        existingArt: _story.panelArt,
      );
      if (art == null) {
        return;
      }
      final updated = await widget.storyService.updateStoryPanelArt(
        _story.id,
        art,
      );
      if (updated != null && mounted) {
        setState(() => _story = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scene artwork imported.')),
        );
      }
    } on StoryPanelArtException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to import panels: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isUpdatingPanelArt = false);
    }
  }

  Future<void> _removePanelArt() async {
    if (_story.panelArt == null || _isUpdatingPanelArt) return;
    final existing = _story.panelArt;
    setState(() => _isUpdatingPanelArt = true);
    try {
      await widget.panelArtService.deletePanelArt(existing);
      final updated = await widget.storyService.updateStoryPanelArt(
        _story.id,
        null,
      );
      if (updated != null && mounted) {
        setState(() => _story = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scene artwork removed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove artwork: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isUpdatingPanelArt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _isDirty && !_isSavingText;
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit story'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(_story),
          ),
          actions: [
            TextButton.icon(
              onPressed: canSave ? _saveStoryText : null,
              icon: _isSavingText
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorSectionHeader(
                  icon: Icons.menu_book_outlined,
                  title: 'Cover & presentation',
                  subtitle: 'Refresh the artwork to match your custom story.',
                ),
                const SizedBox(height: 12),
                _buildCoverCard(theme),
                const SizedBox(height: 32),
                _EditorSectionHeader(
                  icon: Icons.auto_awesome_motion,
                  title: 'Scene-by-scene art',
                  subtitle:
                      'Import the comic grid so each passage reveals its own panel.',
                ),
                const SizedBox(height: 12),
                _buildPanelArtCard(theme),
                const SizedBox(height: 32),
                _EditorSectionHeader(
                  icon: Icons.edit_note_outlined,
                  title: 'Story text',
                  subtitle:
                      'Rewrite lines, fix typos, or personalize the tale.',
                ),
                const SizedBox(height: 12),
                _buildTextCard(theme),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: FilledButton.icon(
              onPressed: canSave ? _saveStoryText : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(canSave ? 'Save story text' : 'All changes saved'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'story_cover_${_story.id}',
                child: _BookCoverPreview(
                  imagePath: _story.coverImagePath,
                  width: 140,
                  borderRadius: 28,
                  showShadow: true,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _story.chapter.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _story.coverImagePath == null
                          ? 'Add a portrait image to dress up this story on the shelf.'
                          : 'Swap the artwork anytime for a fresh look.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _isUpdatingCover ? null : _changeCover,
                          icon: _isUpdatingCover
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _story.coverImagePath == null
                                ? 'Add cover art'
                                : 'Change cover art',
                          ),
                        ),
                        if (_story.coverImagePath != null)
                          OutlinedButton.icon(
                            onPressed: _isUpdatingCover ? null : _removeCover,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanelArtCard(ThemeData theme) {
    final art = _story.panelArt;
    final panelPaths = art?.panelImagePaths ?? const <String>[];
    final hasArt = panelPaths.isNotEmpty;
    final expected = _expectedPanelCount;
    final readyCount = hasArt ? panelPaths.length : 0;
    final targetCount = expected == 0 ? readyCount : expected;
    final statusText = hasArt
        ? 'Panels ready for $readyCount${targetCount > 0 ? '/$targetCount' : ''} passages.'
        : expected == 0
            ? 'Add paragraphs above so we can count how many panels you need.'
            : 'Expecting $expected square panels. Arrange them left-to-right, top-to-bottom.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Tip: export a single square collage at the exact order of your paragraphs.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasArt)
            _PanelThumbnailGrid(paths: panelPaths)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.3),
                ),
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_size_select_large_outlined,
                    size: 38,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We’ll slice the collage into perfectly square panels and align them to each narration paragraph.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            expected == 0
                ? 'Paragraph count unavailable. Save your story text to generate beats.'
                : 'Paragraphs detected: $expected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _isUpdatingPanelArt ? null : _importPanelArt,
                icon: _isUpdatingPanelArt
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.grid_on),
                label: Text(hasArt ? 'Update scene art' : 'Import scene art'),
              ),
              if (hasArt)
                OutlinedButton.icon(
                  onPressed: _isUpdatingPanelArt ? null : _removePanelArt,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard(ThemeData theme) {
    final helperColor = theme.colorScheme.primary.withOpacity(0.15);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
        color: theme.colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: helperColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Tap a paragraph to edit text or artwork',
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: _isDirty ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Chip(
                    label: const Text('Unsaved changes'),
                    backgroundColor: theme.colorScheme.errorContainer
                        .withOpacity(0.4),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Render editor list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _beatEditors.length,
            separatorBuilder: (context, index) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final editor = _beatEditors[index];
              final isNarration = editor.beat.type == BeatType.narration;
              
              // Determine current panel for this beat (if narration)
              String? currentPanelPath;
              if (isNarration) {
                // Calculate narration index (0-based among narration beats only)
                int narrationIndex = 0;
                for (int i = 0; i < index; i++) {
                  if (_beatEditors[i].beat.type == BeatType.narration) {
                    narrationIndex++;
                  }
                }
                
                // Look up assignment or default
                final manualAssignment = _story.panelArt?.assignments[narrationIndex];
                if (manualAssignment != null) {
                  currentPanelPath = manualAssignment;
                } else {
                  // Default: use Nth panel from pool if available
                  final pool = _story.panelArt?.panelImagePaths ?? [];
                  if (narrationIndex < pool.length) {
                    currentPanelPath = pool[narrationIndex];
                  }
                }
              }

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => _BeatDetailScreen(
                        initialIndex: index,
                        beatEditors: _beatEditors,
                        story: _story,
                        onPanelSelected: _selectPanelForBeat,
                        onTextUpdated: () {
                          // Trigger rebuild to show updated text
                          _onTextChanged();
                          setState(() {});
                        },
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isNarration && currentPanelPath != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.file(
                                File(currentPanelPath),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              ),
                            ),
                          ),
                        ),
                      if (isNarration && currentPanelPath == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            height: 80,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                      Text(
                        editor.controller.text.trim().isEmpty 
                            ? '(Empty paragraph)' 
                            : editor.controller.text.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            isNarration ? Icons.article_outlined : Icons.bolt,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isNarration ? 'Paragraph ${index + 1}' : 'Beat ${index + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _isDirty && !_isSavingText ? _saveStoryText : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save text changes'),
              ),
              OutlinedButton.icon(
                onPressed: _isDirty && !_isSavingText ? _resetDraft : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectPanelForBeat(int beatIndex) async {
    final pool = _story.panelArt?.panelImagePaths;
    if (pool == null || pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No panel artwork available. Import some first!')),
      );
      return;
    }

    // Calculate narration index
    int narrationIndex = 0;
    for (int i = 0; i < beatIndex; i++) {
      if (_beatEditors[i].beat.type == BeatType.narration) {
        narrationIndex++;
      }
    }

    final selectedPath = await showDialog<String>(
      context: context,
      builder: (context) => _PanelPickerDialog(
        pool: pool,
        currentPath: _story.panelArt?.assignments[narrationIndex],
      ),
    );

    if (selectedPath != null) {
      // Update assignment in metadata
      final currentMetadata = _story.panelArt!;
      final newAssignments = Map<int, String>.from(currentMetadata.assignments);
      newAssignments[narrationIndex] = selectedPath;
      
      final updatedMetadata = currentMetadata.copyWith(assignments: newAssignments);
      
      // Persist immediately
      try {
        final updatedStory = await widget.storyService.updateStoryPanelArt(
          _story.id,
          updatedMetadata,
        );
        if (updatedStory != null && mounted) {
          setState(() {
            _story = updatedStory;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update assignment: $e')),
          );
        }
      }
    }
  }
}

// _BeatDetailScreen class definition
class _BeatDetailScreen extends StatefulWidget {
  const _BeatDetailScreen({
    required this.initialIndex,
    required this.beatEditors,
    required this.story,
    required this.onPanelSelected,
    required this.onTextUpdated,
  });

  final int initialIndex;
  final List<_BeatEditorState> beatEditors;
  final GeneratedStoryRecord story;
  final Future<void> Function(int) onPanelSelected;
  final VoidCallback onTextUpdated;

  @override
  State<_BeatDetailScreen> createState() => _BeatDetailScreenState();
}

class _BeatDetailScreenState extends State<_BeatDetailScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isEditingText = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Beat ${_currentIndex + 1}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            onPressed: _currentIndex > 0
                ? () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    )
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: _currentIndex < widget.beatEditors.length - 1
                ? () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    )
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.beatEditors.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _isEditingText = false; // Reset edit mode on swipe
          });
        },
        itemBuilder: (context, index) {
          final editor = widget.beatEditors[index];
          final isNarration = editor.beat.type == BeatType.narration;
          
          String? currentPanelPath;
          if (isNarration) {
            int narrationIndex = 0;
            for (int i = 0; i < index; i++) {
              if (widget.beatEditors[i].beat.type == BeatType.narration) {
                narrationIndex++;
              }
            }
            final manualAssignment = widget.story.panelArt?.assignments[narrationIndex];
            if (manualAssignment != null) {
              currentPanelPath = manualAssignment;
            } else {
              final pool = widget.story.panelArt?.panelImagePaths ?? [];
              if (narrationIndex < pool.length) {
                currentPanelPath = pool[narrationIndex];
              }
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isNarration) ...[
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: currentPanelPath != null
                            ? Image.file(
                                File(currentPanelPath),
                                fit: BoxFit.cover,
                              )
                            : const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text('No artwork assigned'),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await widget.onPanelSelected(index);
                        // Force rebuild to show new assignment
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Change Artwork'),
                    ),
                  ),
                ] else ...[
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 48, color: Colors.orange.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'Beat Type: ${editor.beat.type.toString().split('.').last}',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: [
                    Text(
                      'Narration Text',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isEditingText = !_isEditingText;
                        });
                      },
                      icon: Icon(_isEditingText ? Icons.check : Icons.edit),
                      style: IconButton.styleFrom(
                        backgroundColor: _isEditingText 
                            ? theme.colorScheme.primaryContainer 
                            : theme.colorScheme.surfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isEditingText)
                  TextField(
                    controller: editor.controller,
                    maxLines: null,
                    autofocus: true,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onChanged: (_) => widget.onTextUpdated(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      editor.controller.text.isEmpty 
                          ? '(No text)' 
                          : editor.controller.text,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PanelThumbnailGrid extends StatelessWidget {
  const _PanelThumbnailGrid({
    required this.paths,
  });

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final theme = Theme.of(context);
    // Calculate responsive item width
    // We want roughly 3-4 items per row depending on screen width
    // Assuming standard padding of ~32-48px total
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Target ~150px instead of 100px, max 2 columns if screen allows
        final crossAxisCount = (width / 150).floor().clamp(2, 4);
        final spacing = 12.0;
        final totalSpacing = spacing * (crossAxisCount - 1);
        final itemWidth = (width - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: paths
              .map(
                (path) => GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: EdgeInsets.zero,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              child: Image.file(File(path), fit: BoxFit.contain),
                            ),
                            Positioned(
                              top: 40,
                              right: 20,
                              child: IconButton.filled(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: SizedBox(
                    width: itemWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _PanelPickerDialog extends StatelessWidget {
  const _PanelPickerDialog({
    required this.pool,
    this.currentPath,
  });

  final List<String> pool;
  final String? currentPath;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose artwork'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 100,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: pool.length,
          itemBuilder: (context, index) {
            final path = pool[index];
            final isSelected = path == currentPath;
            return GestureDetector(
              onTap: () => Navigator.of(context).pop(path),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (isSelected)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green, width: 4),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _EditorSectionHeader extends StatelessWidget {
  const _EditorSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

int _countNarrationParagraphs(StoryChapter chapter) {
  return chapter.beats
      .where((beat) => beat.type == BeatType.narration)
      .length;
}
