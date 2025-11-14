import 'package:flutter/material.dart';
import '../models/story_models.dart';
import '../models/coaching_session.dart';
import '../utils/app_logger.dart';

/// Story reader screen for parent-child coaching sessions
class StoryReaderScreen extends StatefulWidget {
  final StoryChapter story;
  final String profileId;
  final String childName;

  const StoryReaderScreen({
    Key? key,
    required this.story,
    required this.profileId,
    required this.childName,
  }) : super(key: key);

  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen> with SingleTickerProviderStateMixin {
  int _currentBeatIndex = 0;
  late CoachingSession _session;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize session tracking
    _session = CoachingSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      profileId: widget.profileId,
      storyChapterId: widget.story.id,
      startTime: DateTime.now(),
    );
    
    // Setup fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    
    _fadeController.forward();
    
    AppLogger.system.d('Story reader opened: ${widget.story.title}');
  }
  
  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
  
  void _nextBeat() {
    if (_currentBeatIndex < widget.story.beats.length - 1) {
      _fadeController.reset();
      setState(() {
        _currentBeatIndex++;
      });
      _fadeController.forward();
    } else {
      _completeStory();
    }
  }
  
  void _completeStory() {
    // Complete the session
    final completedSession = _session.copyWith(
      endTime: DateTime.now(),
    );
    
    AppLogger.system.emoji('✅', 'Story completed: ${widget.story.title}');
    
    // Show completion dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.amber, size: 32),
            SizedBox(width: 12),
            Text('Story Complete!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 Great job, ${widget.childName}!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'You practiced ${_session.wordAttempts.length} words together!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Story time: ${completedSession.duration.inMinutes} minutes',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to dashboard
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }
  
  void _recordWordAttempt(String word, bool correct) {
    final attempt = WordAttempt(
      word: word,
      correct: correct,
      timestamp: DateTime.now(),
    );
    
    setState(() {
      _session = _session.copyWith(
        wordAttempts: [..._session.wordAttempts, attempt],
      );
    });
    
    AppLogger.system.d('Word attempt: $word - ${correct ? "✓" : "✗"}');
  }
  
  void _makeChoice(String choiceId) {
    final choice = ChoiceMade(
      choicePointId: 'choice_$_currentBeatIndex',
      choiceId: choiceId,
      timestamp: DateTime.now(),
    );
    
    setState(() {
      _session = _session.copyWith(
        choicesMade: [..._session.choicesMade, choice],
      );
    });
    
    AppLogger.system.d('Choice made: $choiceId');
    _nextBeat();
  }
  
  @override
  Widget build(BuildContext context) {
    final currentBeat = widget.story.beats[_currentBeatIndex];
    final isLastBeat = _currentBeatIndex == widget.story.beats.length - 1;
    
    // Check if there's a choice point at this beat
    final choicePoint = widget.story.choicePoints.where(
      (cp) => cp.beatIndex == _currentBeatIndex
    ).firstOrNull;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.story.title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // Progress indicator
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentBeatIndex + 1} / ${widget.story.beats.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: (_currentBeatIndex + 1) / widget.story.beats.length,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
              minHeight: 4,
            ),
            
            // Story content
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Beat content
                      _buildBeatWidget(currentBeat),
                      
                      const SizedBox(height: 24),
                      
                      // Choice point (if applicable)
                      if (choicePoint != null)
                        _buildChoiceWidget(choicePoint),
                      
                      // Continue button (if no choice)
                      if (choicePoint == null)
                        _buildContinueButton(currentBeat, isLastBeat),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBeatWidget(StoryBeat beat) {
    switch (beat.type) {
      case BeatType.narration:
        return _buildNarrationBubble(beat);
      case BeatType.childTurn:
        return _buildChildTurnBubble(beat);
      case BeatType.coachIntervention:
        return _buildCoachBubble(beat);
      case BeatType.celebration:
        return _buildCelebrationBubble(beat);
    }
  }
  
  Widget _buildNarrationBubble(StoryBeat beat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Parent reads:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChildTurnBubble(StoryBeat beat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.orange.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.child_care, color: Colors.orange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${widget.childName}\'s turn:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          if (beat.targetWords.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: beat.targetWords.map((word) => Chip(
                label: Text(
                  word,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.orange.shade400, width: 2),
              )).toList(),
            ),
          ],
          if (beat.coachPhrase != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '💬 ${beat.coachPhrase}',
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildCoachBubble(StoryBeat beat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.support_agent, color: Colors.purple, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Coach helps:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          if (beat.coachPhrase != null) ...[
            const SizedBox(height: 12),
            Text(
              '💪 ${beat.coachPhrase}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.purple,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildCelebrationBubble(StoryBeat beat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade100, Colors.teal.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.celebration, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Celebration!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChoiceWidget(ChoicePoint choicePoint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.shade200),
          ),
          child: Column(
            children: [
              const Icon(Icons.fork_right, color: Colors.indigo, size: 32),
              const SizedBox(height: 8),
              Text(
                choicePoint.promptText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...choicePoint.choices.map((choice) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ElevatedButton(
            onPressed: () => _makeChoice(choice.id),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.indigo,
              padding: const EdgeInsets.all(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.indigo.shade300, width: 2),
              ),
              elevation: 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  choice.choiceText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  choice.previewText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }
  
  Widget _buildContinueButton(StoryBeat beat, bool isLastBeat) {
    // For child turns, show practice buttons
    if (beat.type == BeatType.childTurn && beat.targetWords.isNotEmpty) {
      return Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Did ${widget.childName} say the word correctly?',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    for (final word in beat.targetWords) {
                      _recordWordAttempt(word, true);
                    }
                    _nextBeat();
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Yes! ✓'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    for (final word in beat.targetWords) {
                      _recordWordAttempt(word, false);
                    }
                    _nextBeat();
                  },
                  icon: const Icon(Icons.replay),
                  label: const Text('Try Again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    
    // Standard continue button
    return ElevatedButton(
      onPressed: _nextBeat,
      style: ElevatedButton.styleFrom(
        backgroundColor: isLastBeat ? Colors.green : Colors.deepPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        isLastBeat ? 'Finish Story 🎉' : 'Continue →',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

