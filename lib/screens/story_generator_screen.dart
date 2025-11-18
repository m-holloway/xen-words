import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/story_generation_models.dart';
import '../services/story_generator_service.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../utils/reading_level_helper.dart';
import 'story_playback_screen.dart';

class StoryGeneratorScreen extends StatefulWidget {
  const StoryGeneratorScreen({super.key});

  @override
  State<StoryGeneratorScreen> createState() => _StoryGeneratorScreenState();
}

class _StoryGeneratorScreenState extends State<StoryGeneratorScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _parentPromptController = TextEditingController();
  final _childContextController = TextEditingController();
  final _storyConceptController = TextEditingController();

  late final TabController _tabController;
  final StoryGeneratorService _storyService = StoryGeneratorService();
  final PreferencesService _preferencesService = PreferencesService();
  final ProfileService _profileService = ProfileService();
  late final AnimationController _loadingController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
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
    });
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
        _tabController.animateTo(1);
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

    _tabController.animateTo(0);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Lab'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Generator'),
            Tab(text: 'Library'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneratorTab(),
          _buildLibraryTab(),
        ],
      ),
    );
  }

  Widget _buildGeneratorTab() {
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
                const SizedBox(height: 16),
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

  Widget _buildLibraryTab() {
    if (_savedStories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.menu_book, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No saved stories yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Generate a story in the generator tab to add it here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _savedStories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final story = _savedStories[index];
        return _StoryListTile(
          story: story,
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StoryPlaybackScreen(story: story),
              ),
            );
          },
          onReuse: () => _reuseStoryInputs(story),
          onDelete: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete story?'),
                content: const Text('This removes the story from your device.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
          },
        );
      },
    );
  }
}

class _StoryListTile extends StatelessWidget {
  const _StoryListTile({
    required this.story,
    required this.onOpen,
    required this.onReuse,
    required this.onDelete,
  });

  final GeneratedStoryRecord story;
  final VoidCallback onOpen;
  final VoidCallback onReuse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          story.chapter.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(story.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text('${story.durationMinutes} min'),
                  avatar: const Icon(Icons.schedule, size: 16),
                ),
                Chip(
                  label: Text('Level ${story.readingLevel}'),
                  avatar: const Icon(Icons.school, size: 16),
                ),
                Chip(
                  label: Text('${(story.familiarWordRatio * 100).toStringAsFixed(0)}% familiar'),
                  avatar: const Icon(Icons.percent, size: 16),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              onDelete();
            } else if (value == 'reuse') {
              onReuse();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'reuse',
              child: Text('Copy inputs to generator'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

