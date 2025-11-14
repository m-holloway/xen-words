import 'package:flutter/material.dart';
import '../models/story_models.dart';
import '../models/coaching_session.dart';
import '../widgets/fireworks_overlay.dart';
import '../utils/app_logger.dart';

/// Enhanced story reader with voice recognition and word highlighting
class StoryReaderScreenEnhanced extends StatefulWidget {
  final StoryChapter story;
  final String profileId;
  final String childName;

  const StoryReaderScreenEnhanced({
    Key? key,
    required this.story,
    required this.profileId,
    required this.childName,
  }) : super(key: key);

  @override
  State<StoryReaderScreenEnhanced> createState() => _StoryReaderScreenEnhancedState();
}

class _StoryReaderScreenEnhancedState extends State<StoryReaderScreenEnhanced>
    with SingleTickerProviderStateMixin {
  int _currentBeatIndex = 0;
  late CoachingSession _session;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final FireworksController _fireworksController = FireworksController();
  
  // Voice recognition state
  bool _isListening = false;
  String? _currentTargetWord;
  Map<String, bool> _validatedWords = {}; // word -> validated
  
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
    
    // Auto-start listening if beat has target words
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartListening();
    });
    
    AppLogger.system.d('Enhanced story reader opened: ${widget.story.title}');
  }
  
  @override
  void dispose() {
    _fadeController.dispose();
    _stopListening();
    super.dispose();
  }
  
  void _checkAndStartListening() {
    final currentBeat = widget.story.beats[_currentBeatIndex];
    
    // Auto-start for child turn beats
    if (currentBeat.type == BeatType.childTurn && currentBeat.targetWords.isNotEmpty) {
      _startListeningForWord(currentBeat.targetWords.first);
    }
    // Auto-start for narration beats with target words
    else if (currentBeat.type == BeatType.narration && currentBeat.targetWords.isNotEmpty) {
      final firstUnvalidated = currentBeat.targetWords
          .where((w) => !(_validatedWords[w] ?? false))
          .firstOrNull;
      if (firstUnvalidated != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _startListeningForWord(firstUnvalidated);
        });
      }
    }
  }
  
  void _startListeningForWord(String word) {
    setState(() {
      _isListening = true;
      _currentTargetWord = word;
    });
    
    AppLogger.speech.emoji('🎤', 'Listening for: $word');
    
    // TODO: Integrate actual Sherpa recognition
    // For now, waiting for parent to manually validate via button
    // (No auto-advance - parent controls the flow)
  }
  
  void _stopListening() {
    if (_isListening) {
      setState(() {
        _isListening = false;
        _currentTargetWord = null;
      });
      AppLogger.speech.d('Stopped listening');
    }
  }
  
  void _onWordRecognized(String word, {required bool correct, String? heard}) {
    _stopListening();
    
    if (correct) {
      // Mark as validated
      setState(() {
        _validatedWords[word] = true;
      });
      
      // Launch fireworks!
      _fireworksController.launchSingle(MediaQuery.of(context).size);
      
      // Record attempt
      _recordWordAttempt(word, true);
      
      AppLogger.system.emoji('✨', 'Word validated: $word');
      
      // Check if there are more words to validate in this beat
      final currentBeat = widget.story.beats[_currentBeatIndex];
      final remainingWords = currentBeat.targetWords
          .where((w) => !(_validatedWords[w] ?? false))
          .toList();
      
      if (remainingWords.isNotEmpty) {
        // More words to go - start listening for next one
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _startListeningForWord(remainingWords.first);
          }
        });
      }
      // All words validated - parent will tap "Continue" to advance
      // (No auto-advance - parent controls the flow)
    } else {
      // Recognition failed
      _showRetryDialog(expected: word, heard: heard);
    }
  }
  
  void _showRetryDialog({required String expected, String? heard}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.replay, color: Colors.orange),
            SizedBox(width: 12),
            Text('Let\'s try again!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (heard != null) ...[
              Text('I heard: "$heard"'),
              const SizedBox(height: 8),
            ],
            Text(
              'The word is: "$expected"',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Parent can model the word, then tap "Try Again"'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Mark as validated anyway (parent override)
              setState(() {
                _validatedWords[expected] = true;
              });
              _recordWordAttempt(expected, false); // Still record as incorrect
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startListeningForWord(expected);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
  
  void _nextBeat() {
    if (_currentBeatIndex < widget.story.beats.length - 1) {
      _fadeController.reset();
      setState(() {
        _currentBeatIndex++;
        _validatedWords.clear(); // Reset for new beat
      });
      _fadeController.forward();
      
      // Check if new beat needs voice recognition
      _checkAndStartListening();
    } else {
      _completeStory();
    }
  }
  
  void _completeStory() {
    _stopListening();
    
    final completedSession = _session.copyWith(
      endTime: DateTime.now(),
    );
    
    AppLogger.system.emoji('✅', 'Story completed: ${widget.story.title}');
    
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
    final choicePoint = widget.story.choicePoints
        .where((cp) => cp.beatIndex == _currentBeatIndex)
        .firstOrNull;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.story.title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentBeatIndex + 1} / ${widget.story.beats.length}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Story content
          SafeArea(
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
                          _buildBeatWidget(currentBeat),
                          const SizedBox(height: 24),
                          if (choicePoint != null)
                            _buildChoiceWidget(choicePoint),
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
          
          // Fireworks overlay
          FireworksOverlay(controller: _fireworksController),
          
          // Listening indicator with manual test buttons
          if (_isListening)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.mic, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Listening for "$_currentTargetWord"...',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Testing mode - Tap to simulate:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_currentTargetWord != null) {
                              _onWordRecognized(_currentTargetWord!, correct: true);
                            }
                          },
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Success'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_currentTargetWord != null) {
                              _onWordRecognized(_currentTargetWord!, correct: false, heard: 'test');
                            }
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Fail'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildBeatWidget(StoryBeat beat) {
    // Use enhanced narration for narration beats with target words
    if (beat.type == BeatType.narration && beat.targetWords.isNotEmpty) {
      return _buildEnhancedNarrationBubble(beat);
    }
    
    // Use enhanced child turn for child turn beats
    if (beat.type == BeatType.childTurn) {
      return _buildEnhancedChildTurnBubble(beat);
    }
    
    // Use standard bubbles for other types
    switch (beat.type) {
      case BeatType.narration:
        return _buildStandardNarrationBubble(beat);
      case BeatType.coachIntervention:
        return _buildCoachBubble(beat);
      case BeatType.celebration:
        return _buildCelebrationBubble(beat);
      default:
        return _buildStandardNarrationBubble(beat);
    }
  }
  
  Widget _buildEnhancedNarrationBubble(StoryBeat beat) {
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHighlightedText(beat.text, beat.targetWords),
          const SizedBox(height: 16),
          // Show progress of validated words
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: beat.targetWords.map((word) {
              final isValidated = _validatedWords[word] ?? false;
              final isListening = _isListening && _currentTargetWord == word;
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isValidated
                      ? Colors.green.shade100
                      : isListening
                          ? Colors.amber.shade100
                          : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isValidated
                        ? Colors.green
                        : isListening
                            ? Colors.amber
                            : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isValidated)
                      const Icon(Icons.check_circle, color: Colors.green, size: 16)
                    else if (isListening)
                      const Icon(Icons.mic, color: Colors.amber, size: 16)
                    else
                      const Icon(Icons.circle_outlined, color: Colors.grey, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      word,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isValidated ? Colors.green.shade900 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHighlightedText(String text, List<String> targetWords) {
    // Simple version: just show text (can enhance later with RichText)
    return Text(
      text,
      style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black87),
    );
  }
  
  Widget _buildEnhancedChildTurnBubble(StoryBeat beat) {
    final word = beat.targetWords.isNotEmpty ? beat.targetWords.first : '';
    final isValidated = _validatedWords[word] ?? false;
    
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
          const SizedBox(height: 16),
          const Text(
            'Can you say this word?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: isValidated ? Colors.green.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isValidated ? Colors.green : Colors.orange.shade400,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isValidated ? Colors.green : Colors.orange).withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isValidated)
                    const Icon(Icons.check_circle, color: Colors.green, size: 32),
                  if (isValidated) const SizedBox(width: 12),
                  Text(
                    word.toUpperCase(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isValidated ? Colors.green.shade900 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // Standard bubble methods (unchanged from original)
  Widget _buildStandardNarrationBubble(StoryBeat beat) {
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black87),
          ),
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black87),
          ),
          if (beat.coachPhrase != null) ...[
            const SizedBox(height: 12),
            Text(
              '💪 ${beat.coachPhrase}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.purple),
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            beat.text,
            style: const TextStyle(fontSize: 20, height: 1.5, fontWeight: FontWeight.w600, color: Colors.black87),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  choice.previewText,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }
  
  Widget _buildContinueButton(StoryBeat beat, bool isLastBeat) {
    // Check if all target words are validated
    final allValidated = beat.targetWords.isEmpty ||
        beat.targetWords.every((w) => _validatedWords[w] ?? false);
    
    // Always show continue button - parent controls the flow
    // Show different style if words aren't validated yet
    return ElevatedButton(
      onPressed: _nextBeat,
      style: ElevatedButton.styleFrom(
        backgroundColor: isLastBeat 
            ? Colors.green 
            : (allValidated ? Colors.deepPurple : Colors.grey),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLastBeat ? 'Finish Story 🎉' : 'Continue →',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (!allValidated && beat.targetWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '(${beat.targetWords.where((w) => !(_validatedWords[w] ?? false)).length} word${beat.targetWords.where((w) => !(_validatedWords[w] ?? false)).length > 1 ? 's' : ''} remaining)',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

