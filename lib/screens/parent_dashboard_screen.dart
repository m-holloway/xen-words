import 'package:flutter/material.dart';
import '../models/learning_progress.dart';
import '../models/child_profile.dart';
import '../models/story_models.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../utils/app_logger.dart';
import '../widgets/simple_progress_hero.dart';
import '../widgets/progress_timeline_widget.dart';
import '../widgets/action_words_widget.dart';
import '../widgets/word_detail_dialog.dart';
import 'story_reader_screen.dart';

/// Parent dashboard showing child's learning progress
/// Protected by parental gate in game_screen.dart
class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({Key? key}) : super(key: key);

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  LearningProgress? _progress;
  ChildProfile? _activeProfile;
  bool _isGuest = false;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final profileService = ProfileService();
      final isGuest = await profileService.isGuestMode();
      
      if (isGuest) {
        // Guest mode - show default/empty progress
        final now = DateTime.now();
        setState(() {
          _isGuest = true;
          _activeProfile = null;
          _progress = LearningProgress(
            firstSessionDate: now,
            lastSessionDate: now,
          );
          _isLoading = false;
        });
      } else {
        // Load active profile
        final activeProfileId = await profileService.getActiveProfileId();
        ChildProfile? profile;
        LearningProgress? progress;
        
        if (activeProfileId != null) {
          final profiles = await profileService.loadProfiles();
          profile = profiles.where((p) => p.id == activeProfileId).firstOrNull;
          
          // Load profile-specific progress
          if (profile != null) {
            progress = await profileService.loadProgressForProfile(profile.id);
          }
        }
        
        final now = DateTime.now();
        setState(() {
          _activeProfile = profile;
          _isGuest = false;
          _progress = progress ?? LearningProgress(
            firstSessionDate: now,
            lastSessionDate: now,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.storage.e('Error loading progress', error: e);
      final now = DateTime.now();
      setState(() {
        _progress = LearningProgress(
          firstSessionDate: now,
          lastSessionDate: now,
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Progress Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (_activeProfile != null)
              Text(
                _activeProfile!.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
              )
            else if (_isGuest)
              const Text(
                'Guest Mode',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_progress == null || (_progress?.totalSessions ?? 0) == 0)
              ? _buildNoDataView(context)
              : _buildDashboard(context, _progress!),
    );
  }
  
  Widget _buildNoDataView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'No Learning Data Yet',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Your child hasn\'t started any lessons yet.\nCome back after they complete their first session!',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDashboard(BuildContext context, LearningProgress progress) {
    final childName = _activeProfile?.name ?? 'Your child';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HERO - The big story at a glance
          SimpleProgressHero(
            progress: progress,
            childName: childName,
          ),
          
          const SizedBox(height: 20),
          
          // 2. PRIMARY ACTION - Start Story Time
          _buildStoryTimeButton(context, progress, childName),
          
          const SizedBox(height: 20),
          
          // 3. TIMELINE - Visual progress over time
          ProgressTimelineWidget(
            progress: progress,
          ),
          
          const SizedBox(height: 20),
          
          // 3. ACTION ITEMS - What to do next
          ActionWordsWidget(
            progress: progress,
            onWordTap: (word) => _showWordDetail(context, word, progress),
          ),
          
          const SizedBox(height: 20),
          
          // 4. DETAILS ON DEMAND - View all words (collapsed by default)
          _buildViewAllWordsButton(context, progress),
          
          const SizedBox(height: 20),
          
          // 5. DATA MANAGEMENT - Settings at bottom
          _buildDataManagementSection(context),
        ],
      ),
    );
  }
  
  Widget _buildStoryTimeButton(BuildContext context, LearningProgress progress, String childName) {
    // Calculate milestone progress
    // For now, unlock story every 5 words mastered
    final wordsMastered = progress.wordProgress.values.where((w) => w.isMastered).length;
    final nextMilestone = ((wordsMastered ~/ 5) + 1) * 5;
    final wordsUntilStory = nextMilestone - wordsMastered;
    
    // Check if story is unlocked
    final storyUnlocked = wordsUntilStory <= 0 || progress.totalSessions >= 3;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: storyUnlocked
              ? [Colors.purple.shade400, Colors.deepPurple.shade600]
              : [Colors.grey.shade400, Colors.grey.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: storyUnlocked
                ? Colors.deepPurple.withOpacity(0.3)
                : Colors.grey.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: storyUnlocked ? () => _launchStoryTime(context, progress, childName) : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.auto_stories,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Story Time',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            storyUnlocked
                                ? 'Read together with $childName!'
                                : 'Complete $wordsUntilStory more ${wordsUntilStory == 1 ? "word" : "words"} to unlock',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (storyUnlocked)
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                  ],
                ),
                if (!storyUnlocked) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: wordsMastered / nextMilestone,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$wordsMastered / $nextMilestone words mastered',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _launchStoryTime(BuildContext context, LearningProgress progress, String childName) {
    // TODO: Navigate to story reader screen
    // For now, show a placeholder message
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Colors.deepPurple),
            SizedBox(width: 12),
            Text('Story Time!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get ready for an adventure with $childName!',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'The story will feature:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._selectStoryWords(progress).map((word) => Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Row(
                children: [
                  Icon(
                    word['mastery'] >= 0.8
                        ? Icons.check_circle
                        : word['mastery'] >= 0.5
                            ? Icons.circle
                            : Icons.circle_outlined,
                    size: 16,
                    color: word['mastery'] >= 0.8
                        ? Colors.green
                        : word['mastery'] >= 0.5
                            ? Colors.orange
                            : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${word['word']} (${(word['mastery'] * 100).toStringAsFixed(0)}%)',
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Story reader UI coming next!',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startStoryReader(context, progress, childName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Start Story'),
          ),
        ],
      ),
    );
  }
  
  List<Map<String, dynamic>> _selectStoryWords(LearningProgress progress) {
    final allWords = progress.wordProgress.values.toList();
    
    if (allWords.isEmpty) {
      return [
        {'word': 'you', 'mastery': 0.5},
        {'word': 'see', 'mastery': 0.5},
        {'word': 'go', 'mastery': 0.5},
      ];
    }
    
    // Separate by mastery level
    final easy = allWords.where((w) => w.successRate >= 0.7).toList();
    final challenging = allWords.where((w) => w.successRate < 0.7).toList();
    
    // Select 3 easy, 2 challenging (60/40 split)
    final selectedEasy = (easy..shuffle()).take(3).toList();
    final selectedChallenging = (challenging..shuffle()).take(2).toList();
    
    final selected = [...selectedEasy, ...selectedChallenging];
    
    return selected.map((w) => {
      'word': w.word,
      'mastery': w.successRate,
    }).toList();
  }
  
  void _startStoryReader(BuildContext context, LearningProgress progress, String childName) {
    // For now, create a sample story
    // TODO: Call StoryService to generate via GenAI
    final sampleStory = _createSampleStory(childName);
    
    AppLogger.system.d('Launching story reader for: $childName');
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StoryReaderScreen(
          story: sampleStory,
          profileId: _activeProfile?.id ?? 'guest',
          childName: childName,
        ),
      ),
    );
  }
  
  StoryChapter _createSampleStory(String childName) {
    // Sample story based on our test generation
    return StoryChapter(
      id: 'sample_${DateTime.now().millisecondsSinceEpoch}',
      title: '$childName and the Sparkling Path',
      beats: [
        StoryBeat(
          id: 'beat_1',
          type: BeatType.narration,
          text: 'You are $childName, and today you see a glowing trail outside your window—shimmering like stardust! Your heart jumps with excitement. What could it lead to?',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_2',
          type: BeatType.childTurn,
          text: 'Now $childName, can you say the word "you"?',
          speaker: Speaker.coach,
          targetWords: ['you'],
          coachPhrase: 'That\'s you—awesome!',
        ),
        StoryBeat(
          id: 'beat_3',
          type: BeatType.narration,
          text: 'You put on your rainbow boots, ready to go on an adventure. The sparkles wiggle like they\'re waving at you, saying, "Come on, you can do it!"',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_4',
          type: BeatType.childTurn,
          text: 'Can you say the word "go"?',
          speaker: Speaker.coach,
          targetWords: ['go'],
          coachPhrase: 'You\'ve got the power to go!',
        ),
        StoryBeat(
          id: 'beat_5',
          type: BeatType.narration,
          text: 'The path splits! One side hums like a happy bee, the other whispers like the wind. What should you do? You stop and wonder.',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_6',
          type: BeatType.celebration,
          text: 'Yay! You said "go" when you were ready—just like $childName is ready to go on this big adventure!',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_7',
          type: BeatType.childTurn,
          text: 'Now $childName, say the word "see"!',
          speaker: Speaker.coach,
          targetWords: ['see'],
          coachPhrase: 'Perfect! You can see the adventure ahead!',
        ),
        StoryBeat(
          id: 'beat_8',
          type: BeatType.narration,
          text: 'You choose the humming path. It\'s bumpy and twisty, and you trip once—but you get back up. What matters is you keep trying.',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_9',
          type: BeatType.coachIntervention,
          text: 'This word is a little tricky—"what." Watch my lips: WH-AT. Can you say "what"?',
          speaker: Speaker.coach,
          targetWords: ['what'],
          coachPhrase: 'You\'re doing so well—try it again!',
        ),
        StoryBeat(
          id: 'beat_10',
          type: BeatType.narration,
          text: 'A tiny fox with silver paws appears. "You\'re stuck?" he asks. "I know what helps—teamwork!" Your eyes light up. What a kind friend!',
          speaker: Speaker.parent,
        ),
        StoryBeat(
          id: 'beat_11',
          type: BeatType.celebration,
          text: 'You did it! You said "see," "go," and "what"—just in time! Together, you and the fox see the treasure: a garden glowing with laughter flowers! You all go home heroes!',
          speaker: Speaker.parent,
        ),
      ],
      choicePoints: [
        ChoicePoint(
          id: 'choice_1',
          beatIndex: 5,
          promptText: 'What should $childName do?',
          choices: [
            StoryChoice(
              id: 'choice_1a',
              previewText: 'Follow the humming path',
              choiceText: 'Choose the humming path',
            ),
            StoryChoice(
              id: 'choice_1b',
              previewText: 'Try the whispering wind trail',
              choiceText: 'Choose the wind trail',
            ),
          ],
        ),
      ],
      metadata: {
        'chapter_num': 1,
        'theme': 'adventure',
        'tone': 'encouraging',
      },
    );
  }
  
  Widget _buildViewAllWordsButton(BuildContext context, LearningProgress progress) {
    if (progress.wordProgress.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return OutlinedButton.icon(
      onPressed: () => _showAllWords(context, progress),
      icon: const Icon(Icons.list),
      label: const Text('View All Words'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        foregroundColor: Colors.deepPurple,
        side: BorderSide(color: Colors.deepPurple.shade200, width: 2),
      ),
    );
  }
  
  void _showAllWords(BuildContext context, LearningProgress progress) {
    // Group words by mastery
    final mastered = progress.wordProgress.values
        .where((w) => w.isMastered)
        .toList()
      ..sort((a, b) => b.masteredDate!.compareTo(a.masteredDate!));
    
    final practicing = progress.wordProgress.values
        .where((w) => !w.isMastered)
        .toList()
      ..sort((a, b) => a.successRate.compareTo(b.successRate));
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'All Words',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Word list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (mastered.isNotEmpty) ...[
                    _buildWordListSection(
                      context,
                      'Mastered (${mastered.length})',
                      mastered,
                      Colors.green,
                      progress,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (practicing.isNotEmpty)
                    _buildWordListSection(
                      context,
                      'Practicing (${practicing.length})',
                      practicing,
                      Colors.orange,
                      progress,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWordListSection(
    BuildContext context,
    String title,
    List<WordProgress> words,
    MaterialColor color,
    LearningProgress progress,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color.shade700,
          ),
        ),
        const SizedBox(height: 12),
        ...words.map((word) => _buildSimpleWordTile(context, word, color, progress)),
      ],
    );
  }
  
  Widget _buildSimpleWordTile(
    BuildContext context,
    WordProgress word,
    MaterialColor color,
    LearningProgress progress,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close modal
        _showWordDetail(context, word.word, progress);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                word.isMastered ? Icons.check_circle : Icons.circle_outlined,
                color: color.shade600,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    word.word,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${(word.successRate * 100).toStringAsFixed(0)}% success • ${word.totalAttempts} attempts',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
  
  void _showWordDetail(BuildContext context, String word, LearningProgress progress) {
    final wordKey = word.toLowerCase();
    final wordProgress = progress.wordProgress[wordKey];
    
    showDialog(
      context: context,
      builder: (context) => WordDetailDialog(
        word: word,
        progress: wordProgress,
      ),
    );
  }
  
  Widget _buildDataManagementSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Privacy & Data',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text('Data Storage'),
                subtitle: const Text('All data is stored locally on this device only'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDataInfoDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete All Data'),
                subtitle: const Text('Remove all progress and session history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmDeleteAllData(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  void _showDataInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Your Data'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What data is stored:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Words attempted and mastered'),
              Text('• Session history and dates'),
              Text('• Success rates and progress'),
              Text('• Child\'s name (for personalization)'),
              Text('• Week progression'),
              SizedBox(height: 16),
              Text(
                'Privacy guarantees:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('✓ Stored only on this device'),
              Text('✓ Never transmitted over internet'),
              Text('✓ Not shared with anyone'),
              Text('✓ Deleted when app is uninstalled'),
              SizedBox(height: 16),
              Text(
                'No audio recordings are ever saved.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
  
  void _confirmDeleteAllData(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Data?'),
        content: const Text(
          'This will permanently delete all progress, session history, and settings. This cannot be undone.\n\nAre you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await PreferencesService().clearAllData();
                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close dashboard
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All data deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                AppLogger.storage.e('Failed to delete data', error: e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting data: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}

