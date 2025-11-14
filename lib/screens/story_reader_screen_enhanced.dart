import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_models.dart';
import '../models/coaching_session.dart';
import '../models/word_list.dart';
import '../controllers/game_controller.dart';
import '../services/speech_recognizer_interface.dart';
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
  bool _recognizerInitialized = false;
  String? _currentTargetWord;
  Map<String, bool> _validatedWords = {}; // word -> validated
  
  // Word tracking for parent narration
  List<String> _narrationWords = [];  // All words in current narration
  int _currentWordIndex = 0;  // Which word parent is currently on
  
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
    
    // Initialize speech recognizer and start listening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndStartListening();
    });
    
    AppLogger.system.d('Enhanced story reader opened: ${widget.story.title}');
  }
  
  Future<void> _initializeAndStartListening() async {
    // Initialize speech recognizer first
    final controller = context.read<GameController>();
    
    AppLogger.speech.d('Initializing speech recognizer for story...');
    final initialized = await controller.initializeSpeechRecognizer();
    
    if (initialized) {
      setState(() {
        _recognizerInitialized = true;
      });
      AppLogger.speech.success('Speech recognizer initialized successfully');
      
      // Now check if we should start listening
      _checkAndStartListening();
    } else {
      AppLogger.speech.e('Failed to initialize speech recognizer');
      // Show error to user?
    }
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
    // Auto-start for narration beats - track parent's reading
    else if (currentBeat.type == BeatType.narration) {
      _startNarrationTracking(currentBeat);
    }
  }
  
  void _startNarrationTracking(StoryBeat beat) {
    // Parse all words from narration text
    _narrationWords = _parseNarrationWords(beat.text);
    _currentWordIndex = 0;
    
    // Start continuous listening for parent's reading
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _startListeningForNarration();
      }
    });
  }
  
  List<String> _parseNarrationWords(String text) {
    // Remove punctuation and split into words
    final cleaned = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .trim();
    return cleaned.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }
  
  void _startListeningForNarration() async {
    if (!_recognizerInitialized) {
      return;
    }
    
    setState(() {
      _isListening = true;
      _currentTargetWord = null;  // No specific target, tracking sequence
    });
    
    AppLogger.speech.d('📖 Tracking parent narration (${_narrationWords.length} words)');
    
    final controller = context.read<GameController>();
    
    try {
      await controller.speechRecognizer.startListening(
        onResult: (result) => _handleNarrationResult(result),
        onPartial: (partial) {
          // Optionally show partial recognition feedback
          AppLogger.speech.v('Narration partial: ${partial.partial}');
        },
        onError: (error) {
          AppLogger.speech.e('Narration recognition error: $error');
        },
        expectedWord: null,  // No specific word expected
      );
      AppLogger.speech.success('📖 Narration tracking active');
    } catch (e) {
      AppLogger.speech.e('Failed to start narration tracking', error: e);
    }
  }
  
  void _handleNarrationResult(SpeechRecognitionResult result) {
    if (!_isListening || result.text.isEmpty) {
      return;
    }
    
    final spokenWords = result.text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    
    AppLogger.speech.v('📖 Heard: ${spokenWords.join(" ")} (at position $_currentWordIndex/${_narrationWords.length})');
    
    // Try to match spoken words to upcoming narration words
    final matchedIndex = _findBestMatchInSequence(spokenWords);
    
    if (matchedIndex != null && matchedIndex > _currentWordIndex) {
      // Advance to the matched word
      setState(() {
        _currentWordIndex = matchedIndex;
      });
      
      AppLogger.speech.d('📖 Advanced to word ${_currentWordIndex + 1}/${_narrationWords.length}: "${_narrationWords[_currentWordIndex]}"');
      
      // Check if we've validated any target words
      final currentBeat = widget.story.beats[_currentBeatIndex];
      _checkForValidatedTargetWords(currentBeat, spokenWords);
    }
  }
  
  int? _findBestMatchInSequence(List<String> spokenWords) {
    // Look for the best match in the next few words of narration
    // This is forgiving - allows skips, extras, and background noise
    
    final lookAhead = 10;  // Check next 10 words max
    final endIndex = (_currentWordIndex + lookAhead).clamp(0, _narrationWords.length);
    
    // Find the furthest matching word in sequence
    int? bestMatch;
    
    for (int i = _currentWordIndex; i < endIndex; i++) {
      final narrationWord = _narrationWords[i];
      
      // Check if any spoken word matches this narration word
      for (final spokenWord in spokenWords) {
        if (_wordsMatch(spokenWord, narrationWord)) {
          bestMatch = i;
          // Don't break - keep looking for further matches
        }
      }
    }
    
    return bestMatch;
  }
  
  bool _wordsMatch(String spoken, String expected) {
    // Simple matching - exact or very close
    if (spoken == expected) return true;
    
    // Handle common variations (plurals, tense)
    if (spoken.startsWith(expected) || expected.startsWith(spoken)) {
      return true;
    }
    
    // Homophone check (from WordList if available)
    if (WordList.phraseContainsWord(spoken, expected)) {
      return true;
    }
    
    return false;
  }
  
  void _checkForValidatedTargetWords(StoryBeat beat, List<String> spokenWords) {
    // Check if any target words were spoken
    for (final targetWord in beat.targetWords) {
      if (!(_validatedWords[targetWord] ?? false)) {
        for (final spoken in spokenWords) {
          if (_wordsMatch(spoken, targetWord)) {
            // Target word was spoken! Validate it
            setState(() {
              _validatedWords[targetWord] = true;
            });
            
            // Launch fireworks!
            _fireworksController.launchSingle(MediaQuery.of(context).size);
            _recordWordAttempt(targetWord, true);
            
            AppLogger.system.emoji('✨', 'Target word validated during narration: $targetWord');
            break;
          }
        }
      }
    }
  }
  
  void _startListeningForWord(String word) async {
    if (!_recognizerInitialized) {
      AppLogger.speech.w('Cannot start listening - recognizer not initialized');
      return;
    }
    
    setState(() {
      _isListening = true;
      _currentTargetWord = word;
    });
    
    AppLogger.speech.emoji('🎤', 'Starting to listen for: $word');
    
    // Integrate actual Sherpa recognition
    final controller = context.read<GameController>();
    
    try {
      await controller.speechRecognizer.startListening(
        onResult: (result) => _handleSpeechResult(result, word),
        onPartial: (partial) {
          AppLogger.speech.v('Partial: ${partial.partial}');
        },
        onError: (error) {
          AppLogger.speech.e('Recognition error: $error');
        },
        expectedWord: word,
      );
      AppLogger.speech.success('🎤 Voice recognition ACTIVE for: $word');
    } catch (e) {
      AppLogger.speech.e('Failed to start voice recognition', error: e);
      setState(() {
        _isListening = false;
        _currentTargetWord = null;
      });
    }
  }
  
  void _handleSpeechResult(SpeechRecognitionResult result, String expectedWord) {
    if (!_isListening || _currentTargetWord != expectedWord) {
      AppLogger.speech.w('Ignoring stale result');
      return;
    }
    
    // Check if result matches expected word
    if (result.text.isEmpty) {
      AppLogger.speech.w('Empty result, ignoring');
      return;
    }
    
    final expectedLower = expectedWord.toLowerCase();
    bool gotExpected = false;
    
    // Check main result
    if (WordList.phraseContainsWord(result.text, expectedLower)) {
      gotExpected = true;
    }
    
    // Check alternatives
    if (!gotExpected && result.alternatives.isNotEmpty) {
      for (final alt in result.alternatives) {
        if (alt.text.isNotEmpty && WordList.phraseContainsWord(alt.text, expectedLower)) {
          gotExpected = true;
          break;
        }
      }
    }
    
    if (gotExpected) {
      AppLogger.speech.success('Recognized: $expectedWord');
      _onWordRecognized(expectedWord, correct: true);
    } else {
      AppLogger.speech.w('Did not recognize expected word. Heard: ${result.text}');
      // Don't auto-fail - let parent use buttons or wait for next attempt
      // Recognition will auto-restart
    }
  }
  
  void _stopListening() async {
    if (_isListening) {
      final controller = context.read<GameController>();
      await controller.speechRecognizer.stopListening();
      
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
          // Show mic status in app bar
          if (!_recognizerInitialized)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          if (_recognizerInitialized)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.mic, size: 20),
            ),
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
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '👂 Speak the word now!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Manual override (if needed):',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            if (_currentTargetWord != null) {
                              _onWordRecognized(_currentTargetWord!, correct: true);
                            }
                          },
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text('Mark Correct'),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.green.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            if (_currentTargetWord != null) {
                              _onWordRecognized(_currentTargetWord!, correct: false, heard: 'manual skip');
                            }
                          },
                          icon: const Icon(Icons.skip_next, size: 16),
                          label: const Text('Skip'),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.orange.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade300, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 14),
              const Text(
                'Parent reads:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Constrained width for fewer words per line
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _buildHighlightedText(beat.text, beat.targetWords),
            ),
          ),
          const SizedBox(height: 24),
          // Show progress of validated words
          if (beat.targetWords.isNotEmpty)
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: beat.targetWords.map((word) {
                  final isValidated = _validatedWords[word] ?? false;
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isValidated ? Colors.green.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isValidated ? Colors.green : Colors.grey,
                        width: 3,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isValidated ? Icons.check_circle : Icons.circle_outlined,
                          color: isValidated ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          word.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isValidated ? Colors.green.shade900 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildHighlightedText(String text, List<String> targetWords) {
    // Build text with word-by-word highlighting for reading tracking
    
    if (_narrationWords.isEmpty) {
      // Fallback if not parsed yet
      return Text(
        text,
        style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black87),
      );
    }
    
    // Split original text into words preserving punctuation/spacing
    final words = text.split(RegExp(r'(\s+)'));
    final spans = <TextSpan>[];
    
    int wordIndex = 0;  // Track actual words (not spaces)
    
    for (final segment in words) {
      if (segment.trim().isEmpty) {
        // It's whitespace - preserve it
        spans.add(TextSpan(text: segment));
        continue;
      }
      
      // It's a word - check if it's a target word
      final cleanWord = segment.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
      final isTargetWord = targetWords.any((t) => t.toLowerCase() == cleanWord);
      
      if (isTargetWord) {
        // Target words get special amber box treatment
        spans.add(TextSpan(
          text: segment,
          style: TextStyle(
            fontSize: 24,  // Match larger child-friendly size
            fontWeight: FontWeight.bold,
            color: (_validatedWords[cleanWord] ?? false) 
                ? Colors.green.shade900 
                : Colors.orange.shade900,
            backgroundColor: (_validatedWords[cleanWord] ?? false)
                ? Colors.green.shade100
                : Colors.amber.shade100,
            decoration: (_validatedWords[cleanWord] ?? false)
                ? TextDecoration.none
                : TextDecoration.underline,
          ),
        ));
      } else {
        // Regular word - apply reading tracking highlight
        final isCurrent = wordIndex == _currentWordIndex;
        final isUnread = wordIndex > _currentWordIndex;
        
        Color? backgroundColor;
        Color textColor = Colors.black87;
        FontWeight fontWeight = FontWeight.normal;
        double fontSize = 22;  // Larger default for child-friendly
        
        if (isCurrent) {
          // Current word - highlighted
          backgroundColor = Colors.blue.shade100;
          textColor = Colors.blue.shade900;
          fontWeight = FontWeight.bold;
          fontSize = 24;
        } else if (isUnread) {
          // Unread - dimmed
          textColor = Colors.grey.shade400;
        } else {
          // Read - normal
          textColor = Colors.black87;
        }
        
        spans.add(TextSpan(
          text: segment,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: textColor,
            backgroundColor: backgroundColor,
            height: 1.5,
          ),
        ));
      }
      
      wordIndex++;
    }
    
    return RichText(
      text: TextSpan(
        children: spans,
        style: const TextStyle(fontSize: 22, height: 1.8, fontFamily: 'Roboto'),
      ),
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

