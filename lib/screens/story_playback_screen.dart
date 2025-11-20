import 'package:flutter/material.dart';

import '../models/story_generation_models.dart';
import '../models/story_models.dart';
import 'story_reader_screen_enhanced.dart';

enum WordPracticeStatus { pending, mastered, needsWork }

class StoryPlaybackScreen extends StatefulWidget {
  const StoryPlaybackScreen({required this.story, super.key});

  final GeneratedStoryRecord story;

  @override
  State<StoryPlaybackScreen> createState() => _StoryPlaybackScreenState();
}

class _StoryPlaybackScreenState extends State<StoryPlaybackScreen> {
  StoryReadingMode _mode = StoryReadingMode.parent;
  WordToken? _selectedToken;
  final Map<String, WordPracticeStatus> _statuses = {};

  @override
  Widget build(BuildContext context) {
    final story = widget.story;

    return Scaffold(
      appBar: AppBar(
        title: Text(story.chapter.title),
        actions: [
          IconButton(
            tooltip: 'Open Enhanced Reader',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StoryReaderScreenEnhanced(
                    story: story.chapter,
                    profileId: 'generated',
                    childName: story.chapter.metadata?['child_name'] ?? story.storyConcept ?? 'Reader',
                    generatedStory: story,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.auto_stories),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeSwitch(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMetadataCard(story),
                const SizedBox(height: 12),
                _buildSherpaHint(),
                const SizedBox(height: 12),
                ...story.chapter.beats.asMap().entries.map(
                      (entry) => _BeatCard(
                        beat: entry.value,
                        beatIndex: entry.key,
                        mode: _mode,
                        onWordTap: (token) {
                          setState(() => _selectedToken = token);
                        },
                        selectedToken: _selectedToken,
                        statuses: _statuses,
                      ),
                    ),
                const SizedBox(height: 100),
              ],
            ),
          ),
          _buildChildControls(),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SegmentedButton<StoryReadingMode>(
        segments: StoryReadingMode.values
            .map(
              (mode) => ButtonSegment(
                value: mode,
                icon: Icon(mode == StoryReadingMode.parent ? Icons.family_restroom : Icons.check),
                label: Text(mode.label),
              ),
            )
            .toList(),
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
          });
        },
      ),
    );
  }

  Widget _buildMetadataCard(GeneratedStoryRecord story) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              story.summary,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text('${story.durationMinutes} min'),
                ),
                Chip(
                  avatar: const Icon(Icons.school, size: 16),
                  label: Text('Level ${story.readingLevel}'),
                ),
                Chip(
                  avatar: const Icon(Icons.percent, size: 16),
                  label: Text('${(story.familiarWordRatio * 100).toStringAsFixed(0)}% familiar'),
                ),
                Chip(
                  avatar: const Icon(Icons.today, size: 16),
                  label: Text(
                    MaterialLocalizations.of(context).formatShortDate(story.createdAt),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSherpaHint() {
    return Card(
      color: Colors.blueGrey.shade50,
      child: ListTile(
        leading: const Icon(Icons.hearing, color: Colors.blueGrey),
        title: const Text('Sherpa phonetic checks'),
        subtitle: const Text(
          'Child mode will soon auto-check spoken words using the Sherpa recognizer. '
          'For now, tap a word then use the check/X buttons below.',
        ),
      ),
    );
  }

  Widget _buildChildControls() {
    if (_mode == StoryReadingMode.parent) {
      return const SizedBox.shrink();
    }

    final selected = _selectedToken;
    final status = selected != null ? _statuses[selected.key] : null;

    return Container(
      color: Colors.black.withOpacity(0.04),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selected == null ? 'Tap a word to review' : 'Selected: "${selected.text}"',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton.filledTonal(
            onPressed: selected == null
                ? null
                : () => _updateStatus(selected, WordPracticeStatus.mastered),
            icon: const Icon(Icons.check),
            color: status == WordPracticeStatus.mastered ? Colors.green : null,
            tooltip: 'Mark as nailed it',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: selected == null
                ? null
                : () => _updateStatus(selected, WordPracticeStatus.needsWork),
            icon: const Icon(Icons.close),
            color: status == WordPracticeStatus.needsWork ? Colors.red : null,
            tooltip: 'Mark for more practice',
          ),
        ],
      ),
    );
  }

  void _updateStatus(WordToken token, WordPracticeStatus status) {
    setState(() {
      _statuses[token.key] = status;
    });
  }
}

class _BeatCard extends StatelessWidget {
  const _BeatCard({
    required this.beat,
    required this.beatIndex,
    required this.mode,
    required this.onWordTap,
    required this.selectedToken,
    required this.statuses,
  });

  final StoryBeat beat;
  final int beatIndex;
  final StoryReadingMode mode;
  final ValueChanged<WordToken> onWordTap;
  final WordToken? selectedToken;
  final Map<String, WordPracticeStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokenize(beat.text, beatIndex);
    final celebrationTargets = beat.targetWords
        .map((w) => w.replaceAll(RegExp(r"[^\w']"), '').toLowerCase())
        .toSet();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconForBeat(beat.type),
                  color: _colorForBeat(beat.type),
                ),
                const SizedBox(width: 8),
                Text(
                  _labelForBeat(beat.type),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 8,
              children: tokens.map((token) {
                final status = statuses[token.key] ?? WordPracticeStatus.pending;
                final isSelected = selectedToken?.key == token.key;
                final baseBackground = _backgroundForStatus(status, isSelected, mode);
                final normalizedToken = token.text
                    .replaceAll(RegExp(r"[^\w']"), '')
                    .toLowerCase();
                final isCelebrationWord = beat.type == BeatType.celebration &&
                    celebrationTargets.contains(normalizedToken);

                final decorationColor =
                    isCelebrationWord ? Colors.amber.shade50 : baseBackground;
                final border = isCelebrationWord
                    ? Border.all(color: Colors.amber.shade500, width: 2)
                    : null;
                final boxShadow = isCelebrationWord
                    ? [
                        BoxShadow(
                          color: Colors.amber.shade200,
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null;

                Widget chip = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: decorationColor,
                    borderRadius: BorderRadius.circular(8),
                    border: border,
                    boxShadow: boxShadow,
                  ),
                  child: Text(
                    token.text,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: isCelebrationWord
                          ? FontWeight.w800
                          : (isSelected ? FontWeight.bold : FontWeight.normal),
                      color: isCelebrationWord ? Colors.orange.shade900 : null,
                    ),
                  ),
                );

                if (isCelebrationWord) {
                  chip = Stack(
                    clipBehavior: Clip.none,
                    children: [
                      chip,
                      Positioned(
                        top: -10,
                        left: -6,
                        child: Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber.shade500,
                        ),
                      ),
                      Positioned(
                        bottom: -8,
                        right: -8,
                        child: Icon(
                          Icons.star,
                          size: 20,
                          color: Colors.amber.shade300,
                        ),
                      ),
                    ],
                  );
                }

                return GestureDetector(
                  onTap: () => onWordTap(token),
                  child: chip,
                );
              }).toList(),
            ),
            if (beat.coachPhrase != null && beat.coachPhrase!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Coach tip: ${beat.coachPhrase}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _backgroundForStatus(WordPracticeStatus status, bool isSelected, StoryReadingMode mode) {
    if (isSelected) {
      return Colors.amber.shade100;
    }
    if (mode == StoryReadingMode.parent) {
      return Colors.transparent;
    }
    switch (status) {
      case WordPracticeStatus.mastered:
        return Colors.green.shade100;
      case WordPracticeStatus.needsWork:
        return Colors.red.shade100;
      case WordPracticeStatus.pending:
        return Colors.transparent;
    }
  }

  IconData _iconForBeat(BeatType type) {
    switch (type) {
      case BeatType.childTurn:
        return Icons.campaign;
      case BeatType.coachIntervention:
        return Icons.support_agent;
      case BeatType.celebration:
        return Icons.celebration;
      case BeatType.narration:
        return Icons.menu_book;
    }
  }

  Color _colorForBeat(BeatType type) {
    switch (type) {
      case BeatType.childTurn:
        return Colors.orange;
      case BeatType.coachIntervention:
        return Colors.blue;
      case BeatType.celebration:
        return Colors.purple;
      case BeatType.narration:
        return Colors.teal;
    }
  }

  String _labelForBeat(BeatType type) {
    switch (type) {
      case BeatType.childTurn:
        return 'Child turn';
      case BeatType.coachIntervention:
        return 'Coach moment';
      case BeatType.celebration:
        return 'Celebration';
      case BeatType.narration:
        return 'Narration';
    }
  }

  List<WordToken> _tokenize(String text, int beatIdx) {
    final cleaned = text.split(RegExp(r'(\s+)'));
    int wordIndex = 0;
    return cleaned.where((t) => t.trim().isNotEmpty).map((token) {
      final word = token.trim();
      final tokenObj = WordToken(
        beatIndex: beatIdx,
        wordIndex: wordIndex,
        text: word,
      );
      wordIndex += 1;
      return tokenObj;
    }).toList();
  }
}

class WordToken {
  WordToken({
    required this.beatIndex,
    required this.wordIndex,
    required this.text,
  });

  final int beatIndex;
  final int wordIndex;
  final String text;

  String get key => '$beatIndex-$wordIndex';
}

