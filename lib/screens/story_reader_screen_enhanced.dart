import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_models.dart';
import '../models/coaching_session.dart';
import '../models/word_list.dart';
import '../controllers/game_controller.dart';
import '../services/speech_recognizer_interface.dart';
import '../services/word_grouping_service.dart';
import '../widgets/fireworks_overlay.dart';
import '../widgets/grouped_word_display.dart';
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
  
  // V13 tracking state (Sherpa-anchored VAD)
  bool _narrationTrackingActive = false;
  double _currentTrackingConfidence = 0.0;
  String _currentTrackingSource = 'init';
  int _lastTrackedWord = -1;
  int _v13VadPredictions = 0;
  int _v13Anchors = 0;
  int _v13Corrections = 0;
  bool _finalWordConfirmed = false;
  
  // Legacy voice recognition state (for STT anchoring + child turns)
  bool _isListening = false;
  bool _recognizerInitialized = false;
  String? _currentTargetWord;
  Map<String, bool> _validatedWords = {}; // word -> validated
  
  // Word tracking for parent narration
  List<String> _narrationWords = [];  // Clean words for tracking
  List<String> _narrationDisplayWords = []; // Original words with punctuation for UI
  int _currentWordIndex = 0;  // Current display position (blend of VAD + STT)
  
  // Word grouping for smooth display
  List<List<int>> _wordGroups = [];
  DateTime _lastWordTime = DateTime.now();
  double _estimatedWPM = 120.0;  // Default reading rate (words per minute)
  bool _wordLinesReady = false;
  String _listeningStatusLabel = 'Initializing speech recognition...';
  int _scrollAnchorWordIndex = -1;
  
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
    setState(() {
      _listeningStatusLabel = 'Initializing speech recognizer...';
      _wordLinesReady = false;
    });
    
    AppLogger.speech.d('Initializing speech recognizer for story...');
    final initialized = await controller.initializeSpeechRecognizer();
    
    if (initialized) {
      setState(() {
        _recognizerInitialized = true;
        _listeningStatusLabel = 'Preparing story view...';
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
    
    final previewText = currentBeat.text;
    final snippet = previewText.length > 30 ? '${previewText.substring(0, 30)}…' : previewText;
    AppLogger.speech.d('📖 Beat ${_currentBeatIndex + 1}: Type=${currentBeat.type}, Text="$snippet"');
    
    final hasTargetWords = currentBeat.targetWords.isNotEmpty;

    final isChildPracticeBeat = currentBeat.type == BeatType.childTurn ||
        currentBeat.type == BeatType.coachIntervention ||
        currentBeat.type == BeatType.celebration;

    if (hasTargetWords && isChildPracticeBeat) {
      AppLogger.speech.d('🎯 Beat requires spoken word, listening for: ${currentBeat.targetWords.first}');
      _startListeningForWord(currentBeat.targetWords.first);
    } else if (currentBeat.type == BeatType.narration) {
      AppLogger.speech.d('📚 Narration beat detected, starting tracking');
      _startNarrationTracking(currentBeat);
    } else {
      AppLogger.speech.d('ℹ️ Other beat type: ${currentBeat.type}');
    }
  }
  
  void _startNarrationTracking(StoryBeat beat) async {
    if (!_recognizerInitialized) {
      AppLogger.speech.w('Speech recognizer not initialized; cannot start narration tracking');
      return;
    }
    
    final controller = context.read<GameController>();
    
    if (_narrationTrackingActive) {
      await controller.speechRecognizer.stopNarrationTracking();
    }
    
    final parsedWords = _parseNarrationText(beat.text);
    final groupedWords = WordGroupingService.groupWords(
      parsedWords.cleanWords,
      displayWords: parsedWords.displayWords,
    );
    
    setState(() {
      _narrationWords = parsedWords.cleanWords;
      _narrationDisplayWords = parsedWords.displayWords;
      _wordGroups = groupedWords;
      _currentWordIndex = 0;
      _currentTargetWord = 'tracking';
      _currentTrackingConfidence = 0.0;
      _currentTrackingSource = 'init';
      _lastTrackedWord = -1;
      _v13VadPredictions = 0;
      _v13Anchors = 0;
      _v13Corrections = 0;
      _estimatedWPM = 120.0;
      _narrationTrackingActive = false;
      _scrollAnchorWordIndex = -1;
      _wordLinesReady = false;
      _listeningStatusLabel = 'Preparing listener...';
      _finalWordConfirmed = false;
    });
    
    _lastWordTime = DateTime.now();
    final totalWords = _narrationWords.length;
    final tailStart = totalWords > 12 ? totalWords - 12 : 0;
    final tailWords = _narrationWords.sublist(tailStart);
    AppLogger.speech.d(
      '📝 Narration script (${_narrationWords.length} words). Tail: ${tailWords.join(' ')}',
    );
    
    if (_narrationWords.isEmpty) {
      AppLogger.speech.w('Narration beat contains no readable words');
      if (mounted) {
        setState(() {
          _currentTargetWord = null;
        });
      }
      return;
    }
    
    AppLogger.speech.i('🎧 Starting V13 tracking for ${_narrationWords.length} words');
    
    final scriptForTracker = _narrationWords.join(' ');
    
    try {
      final started = await controller.speechRecognizer.startNarrationTracking(
        scriptText: scriptForTracker,
        onWordUpdate: (index, confidence, source) {
          _handleNarrationWordUpdate(beat, index, confidence, source);
        },
      );
      
      if (!mounted) {
        return;
      }
      
      if (started) {
        setState(() {
          _narrationTrackingActive = true;
          _wordLinesReady = true;
          _listeningStatusLabel = 'Listening – start reading when ready';
        });
        AppLogger.speech.success('✅ V13 narration tracking active');
      } else {
        setState(() {
          _currentTargetWord = null;
          _wordLinesReady = false;
          _listeningStatusLabel = 'Unable to start listener';
        });
        AppLogger.speech.e('❌ Failed to start V13 narration tracking');
      }
    } catch (e, stackTrace) {
      AppLogger.speech.e('Failed to start narration tracking: $e', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _currentTargetWord = null;
          _narrationTrackingActive = false;
          _wordLinesReady = false;
          _listeningStatusLabel = 'Listener unavailable';
        });
      }
    }
  }
  
  void _handleNarrationWordUpdate(
    StoryBeat beat,
    int wordIndex,
    double confidence,
    String source,
  ) {
    if (!mounted || _narrationWords.isEmpty) {
      return;
    }
    
    final int totalWords = _narrationWords.length;
    final int maxIndex = totalWords - 1;
    final int clampedIndex;
    if (totalWords <= 0) {
      clampedIndex = 0;
    } else {
      clampedIndex = wordIndex.clamp(0, maxIndex).toInt();
    }
    final now = DateTime.now();
    final bool progressed = clampedIndex != _lastTrackedWord;
    final bool anchorSource = _isAnchorSource(source);
    bool finalWordConfirmed = _finalWordConfirmed;

    final bool trackerReportedEnd = totalWords > 0 && wordIndex >= totalWords;

    if (!finalWordConfirmed && anchorSource && trackerReportedEnd) {
      finalWordConfirmed = true;
      AppLogger.speech.d('✅ Final word confirmed via Sherpa anchor');
    }
    
    double updatedWpm = _estimatedWPM;
    DateTime updatedLastWordTime = _lastWordTime;
    
    if (progressed) {
      final seconds = now.difference(_lastWordTime).inMilliseconds / 1000.0;
      if (seconds > 0.12 && seconds < 3.0) {
        updatedWpm = 60.0 / seconds;
      }
      updatedLastWordTime = now;
    }
    
    int vadPredictions = _v13VadPredictions;
    int anchors = _v13Anchors;
    int corrections = _v13Corrections;
    
    switch (source) {
      case 'vad':
        vadPredictions++;
        break;
      case 'sherpa_anchor':
      case 'sherpa_catchup':
        anchors++;
        break;
      case 'sherpa_correction':
        corrections++;
        break;
      default:
        break;
    }
    
    if (!mounted) {
      return;
    }
    
    setState(() {
      _currentWordIndex = clampedIndex;
      _currentTrackingConfidence = confidence;
      _currentTrackingSource = source;
      _lastTrackedWord = clampedIndex;
      _v13VadPredictions = vadPredictions;
      _v13Anchors = anchors;
      _v13Corrections = corrections;
      _estimatedWPM = updatedWpm;
      _currentTargetWord = 'tracking';
      _finalWordConfirmed = finalWordConfirmed;
      if (anchorSource) {
        _scrollAnchorWordIndex = clampedIndex;
      }
    });
    
    _lastWordTime = updatedLastWordTime;
    
    AppLogger.speech.v(
      '🎯 V13 update [$source] → word ${clampedIndex + 1}/${_narrationWords.length} '
      '(conf ${(confidence * 100).toStringAsFixed(0)}%)',
    );
    
    if (progressed && beat.targetWords.isNotEmpty) {
      _checkForValidatedTargetWords(beat, [_narrationWords[clampedIndex]]);
    }
  }
  
  String _buildMicStatusText() {
    if (_narrationTrackingActive) {
      final total = _narrationWords.length;
      final int safeIndex = total > 0
          ? ((_wordIndexSafe(_currentWordIndex, total)) + 1)
          : 0;
      final confidence = (_currentTrackingConfidence.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
      final sourceLabel = _describeTrackingSource(_currentTrackingSource);
      final stats = '⚡$_v13VadPredictions | ⚓$_v13Anchors | 🔧$_v13Corrections';
      return 'V13 $safeIndex/${total == 0 ? "?" : total.toString()} · $sourceLabel · $confidence% · $stats';
    }
    
    if (_currentTargetWord != null) {
      return 'Listening for "${_currentTargetWord!}"...';
    }
    
    if (!_recognizerInitialized) {
      return 'Initializing microphone...';
    }
    
    return 'Ready';
  }
  
  int _wordIndexSafe(int index, int total) {
    if (total <= 0) return 0;
    if (index < 0) return 0;
    if (index >= total) return total - 1;
    return index;
  }
  
  String _describeTrackingSource(String source) {
    switch (source) {
      case 'vad':
        return '⚡ VAD';
      case 'sherpa_anchor':
        return '⚓ Anchor';
      case 'sherpa_catchup':
        return '⚓ Catch-up';
      case 'sherpa_correction':
        return '🔧 Correction';
      case 'hold':
        return '…';
      default:
        return '…';
    }
  }
  
  _ParsedNarrationText _parseNarrationText(String text) {
    final normalized = text.replaceAll(RegExp(r'[-–—]+'), ' ');
    final rawTokens = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    
    final cleanWords = <String>[];
    final displayWords = <String>[];
    
    for (final token in rawTokens) {
      final cleanToken = token
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w]'), '');
      
      if (cleanToken.isEmpty) {
        continue;
      }
      
      cleanWords.add(cleanToken);
      displayWords.add(token);
    }
    
    return _ParsedNarrationText(
      cleanWords: cleanWords,
      displayWords: displayWords,
    );
  }
  bool _wordsMatch(String spoken, String expected) {
    // Simple matching for anchoring
    if (spoken == expected) return true;
    
    // Handle common variations
    if (spoken.startsWith(expected) || expected.startsWith(spoken)) {
      return true;
    }
    
    // Homophone check
    if (WordList.phraseContainsWord(spoken, expected)) {
      return true;
    }
    
    return false;
  }
  
  // DEPRECATED: Old STT-only methods (replaced by hybrid VAD+STT)
  // ignore: unused_element
  
  
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
    final controller = context.read<GameController>();
    
    if (_narrationTrackingActive) {
      await controller.speechRecognizer.stopNarrationTracking();
      if (mounted) {
        setState(() {
          _narrationTrackingActive = false;
          _currentTargetWord = null;
        });
      }
      AppLogger.speech.d('Stopped V13 narration tracking');
    }
    
    if (_isListening) {
      await controller.speechRecognizer.stopListening();
      if (mounted) {
        setState(() {
          _isListening = false;
          _currentTargetWord = null;
        });
      }
      AppLogger.speech.d('Stopped STT listening');
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
        _finalWordConfirmed = false;
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
    final micStatusText = _buildMicStatusText();
    final bool isTrackingMode = _narrationTrackingActive && _currentTargetWord == 'tracking';
    
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
                  color: _currentTargetWord == 'tracking' 
                      ? Colors.blue.withOpacity(0.95)
                      : Colors.deepPurple.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_currentTargetWord == 'tracking' ? Colors.blue : Colors.deepPurple)
                          .withOpacity(0.3),
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
                        Expanded(
                          child: Text(
                            micStatusText,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
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
                      child: Text(
                        isTrackingMode
                            ? '📚 Reading along with you (V13)'
                            : '👂 Speak the word now!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_currentTargetWord != 'tracking') ...[
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
                              if (_currentTargetWord != null && _currentTargetWord != 'tracking') {
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
                              if (_currentTargetWord != null && _currentTargetWord != 'tracking') {
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
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildBeatWidget(StoryBeat beat) {
    // Use enhanced narration for ALL narration beats (with or without target words)
    if (beat.type == BeatType.narration) {
      return _buildEnhancedNarrationBubble(beat);
    }
    
    // Use enhanced child turn for child turn beats
    if (beat.type == BeatType.childTurn) {
      return _buildEnhancedChildTurnBubble(beat);
    }
    
    // Use standard bubbles for other types
    switch (beat.type) {
      case BeatType.coachIntervention:
        return _buildCoachBubble(beat);
      case BeatType.celebration:
        return _buildCelebrationBubble(beat);
      default:
        return _buildStandardNarrationBubble(beat);
    }
  }
  
  Widget _buildEnhancedNarrationBubble(StoryBeat beat) {
    // If narration words not yet parsed, parse them now
    if (_narrationWords.isEmpty || _narrationDisplayWords.isEmpty) {
      AppLogger.speech.w('⚠️ Narration words not yet parsed, parsing now');
      final parsed = _parseNarrationText(beat.text);
      _narrationWords = parsed.cleanWords;
      _narrationDisplayWords = parsed.displayWords;
      _wordGroups = WordGroupingService.groupWords(
        parsed.cleanWords,
        displayWords: parsed.displayWords,
      );
    }
    
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
              Text(
                '📖 Parent reads (word ${_currentWordIndex + 1}/${_narrationWords.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Full width for word boxes
          _buildHighlightedText(beat.text, beat.targetWords),
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
    // NEW: Use grouped word display with smooth progress
    
    AppLogger.speech.v('🎨 Building grouped text: ${_narrationWords.length} words, ${_wordGroups.length} lines, current=$_currentWordIndex');
    
    // Fallback if groups not initialized
    if (_narrationWords.isEmpty || _wordGroups.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 20));
    }
    
    // Check if we're at the end
    final lastWordIndex = _narrationWords.isEmpty ? 0 : _narrationWords.length - 1;
    final isComplete = _finalWordConfirmed && _currentWordIndex >= lastWordIndex;
    
    // Calculate discrete progress for current line (no time-based smoothing)
    final currentLine = WordGroupingService.getLineForWord(_wordGroups, _currentWordIndex);
    final lineProgress = currentLine >= 0 && currentLine < _wordGroups.length
        ? WordGroupingService.getLineProgress(_wordGroups[currentLine], _currentWordIndex)
        : 0.0;
    
    final groupedWords = GroupedWordDisplay(
      displayWords: _narrationDisplayWords,
      wordGroups: _wordGroups,
      currentWordIndex: _currentWordIndex,
      smoothProgress: lineProgress,
      onWordTap: (index) => _jumpToWord(index),
      showProgressBar: !isComplete,
      readingComplete: isComplete,
      scrollWordIndex: _getScrollWordIndex(),
    );
    
    final Widget readyContent = KeyedSubtree(
      key: const ValueKey('narration-words'),
      child: isComplete
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                groupedWords,
                const SizedBox(height: 24),
                _buildCompletionCard(),
              ],
            )
          : groupedWords,
    );
    
    final Widget loadingContent = _buildNarrationPrepCard();
    final bool showWordLines = _wordLinesReady && _wordGroups.isNotEmpty;
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: showWordLines ? readyContent : loadingContent,
    );
  }
  
  bool _isAnchorSource(String source) {
    return source == 'sherpa_anchor' ||
        source == 'sherpa_catchup' ||
        source == 'sherpa_correction';
  }
  
  int _getScrollWordIndex() {
    if (_scrollAnchorWordIndex < 0) {
      return _currentWordIndex;
    }
    final int maxVisible = (_scrollAnchorWordIndex + 1).clamp(0, _narrationWords.length - 1);
    if (_currentWordIndex <= maxVisible) {
      return _currentWordIndex;
    }
    return maxVisible;
  }
  Widget _buildNarrationPrepCard() {
    return Container(
      key: const ValueKey('narration-prep'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.shade100.withOpacity(0.4),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
          ),
          const SizedBox(height: 20),
          Text(
            _listeningStatusLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'We’ll show the words as soon as the microphone is ready.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  void _jumpToWord(int wordIndex) {
    AppLogger.speech.d('🔄 Jumping to word $wordIndex');
    setState(() {
      _currentWordIndex = wordIndex;
    });
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

  Widget _buildCompletionCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade600, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade200.withOpacity(0.6),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reading complete! ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextBeat,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue →',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
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
    final requiresValidation = beat.targetWords.isNotEmpty;
    final validatedCount = beat.targetWords.where((w) => _validatedWords[w] ?? false).length;
    final allValidated = !requiresValidation || validatedCount == beat.targetWords.length;

    return ElevatedButton(
      onPressed: allValidated ? _nextBeat : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isLastBeat
            ? Colors.green
            : (allValidated ? Colors.deepPurple : Colors.grey.shade500),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        disabledBackgroundColor: Colors.grey.shade400,
        disabledForegroundColor: Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLastBeat ? 'Finish Story 🎉' : 'Continue →',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (!allValidated && requiresValidation)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Say the highlighted word (${validatedCount}/${beat.targetWords.length})',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

class _ParsedNarrationText {
  final List<String> cleanWords;
  final List<String> displayWords;

  const _ParsedNarrationText({
    required this.cleanWords,
    required this.displayWords,
  });
}



