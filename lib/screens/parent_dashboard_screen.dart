import 'package:flutter/material.dart';
import '../models/learning_progress.dart';
import '../models/child_profile.dart';
import '../services/profile_service.dart';
import '../utils/app_logger.dart';
import '../widgets/simple_progress_hero.dart';
import '../widgets/progress_timeline_widget.dart';
import '../widgets/action_words_widget.dart';
import '../widgets/word_detail_dialog.dart';

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
        final now = DateTime.now();
      final isGuestMode = await profileService.isGuestMode();

      ChildProfile? profile;
      LearningProgress progress;
      bool guestFlag = isGuestMode;

      if (isGuestMode) {
        progress = LearningProgress(
            firstSessionDate: now,
            lastSessionDate: now,
          );
      } else {
        final activeProfileId = await profileService.getActiveProfileId();
        if (activeProfileId != null) {
          final profiles = await profileService.loadProfiles();
          profile = profiles.where((p) => p.id == activeProfileId).firstOrNull;
          if (profile != null) {
            final loadedProgress = await profileService.loadProgressForProfile(profile.id);
            progress = loadedProgress ??
                LearningProgress(
                  firstSessionDate: now,
                  lastSessionDate: now,
                );
          } else {
            progress = LearningProgress(
              firstSessionDate: now,
              lastSessionDate: now,
            );
          }
        } else {
          progress = LearningProgress(
            firstSessionDate: now,
            lastSessionDate: now,
          );
        }
        guestFlag = false;
      }

      if (!mounted) return;
        setState(() {
          _activeProfile = profile;
        _isGuest = guestFlag;
        _progress = progress;
      });
    } catch (e) {
      AppLogger.storage.e('Error loading progress', error: e);
      final now = DateTime.now();
      if (mounted) {
      setState(() {
        _progress = LearningProgress(
          firstSessionDate: now,
          lastSessionDate: now,
        );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
    
    return LayoutBuilder(
      builder: (context, constraints) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SimpleProgressHero(
            progress: progress,
            childName: childName,
          ),
          
              const SizedBox(height: 16),
              
              _buildInsightsSection(context, progress),
              
              const SizedBox(height: 24),
        ],
      ),
        );
      },
    );
  }

  Widget _buildInsightsSection(BuildContext context, LearningProgress progress) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          'Insights & next steps',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Timeline, focus words, and the full word list'),
        children: [
          SizedBox(
            width: double.infinity,
            child: ProgressTimelineWidget(
              progress: progress,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                'Focus words',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ActionWordsWidget(
            progress: progress,
            onWordTap: (word) => _showWordDetail(context, word, progress),
          ),
          const SizedBox(height: 16),
          _buildViewAllWordsButton(context, progress),
        ],
      ),
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
}
