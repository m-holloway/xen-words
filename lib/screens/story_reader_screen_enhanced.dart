import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../models/story_models.dart';
import '../models/story_generation_models.dart';
import '../services/story_generator_service.dart';
import '../models/coaching_session.dart';
import '../models/word_list.dart';
import '../controllers/game_controller.dart';
import '../services/speech_recognizer_interface.dart';
import '../services/word_grouping_service.dart';
import '../widgets/fireworks_overlay.dart';
import '../widgets/grouped_word_display.dart';
import '../widgets/plush_microphone_meter.dart';
import '../widgets/star_rating.dart';
import '../utils/app_logger.dart';

/// Enhanced story reader with voice recognition and word highlighting
class StoryReaderScreenEnhanced extends StatefulWidget {
  final StoryChapter story;
  final String profileId;
  final String childName;
  final GeneratedStoryRecord? generatedStory;

  const StoryReaderScreenEnhanced({
    Key? key,
    required this.story,
    required this.profileId,
    required this.childName,
    this.generatedStory,
  }) : super(key: key);

  @override
  State<StoryReaderScreenEnhanced> createState() => _StoryReaderScreenEnhancedState();
}

class _StoryReaderScreenEnhancedState extends State<StoryReaderScreenEnhanced>
    with SingleTickerProviderStateMixin {
  static const bool _enableChildPracticeBeats = false;
  static const bool _enableCelebrationBeats = false;
  static const bool _enableTargetWordCelebrations = false;
  static const bool _showTargetWordCallouts = false;
  int _currentBeatIndex = 0;
  late CoachingSession _session;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final FireworksController _fireworksController = FireworksController();
  final ScrollController _contentScrollController = ScrollController();
  final StoryGeneratorService _storyGeneratorService = StoryGeneratorService();
  
  // V13 tracking state (Sherpa-anchored VAD)
  bool _narrationTrackingActive = false;
  double _currentTrackingConfidence = 0.0;
  int _lastTrackedWord = -1;
  int _v13VadPredictions = 0;
  int _v13Anchors = 0;
  int _v13Corrections = 0;
  bool _finalWordConfirmed = false;
  
  // Legacy voice recognition state (for STT anchoring + child turns)
  bool _isListening = false;
  bool _isUserMuted = false;
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
  Timer? _finalWordCompletionTimer;
  static const Duration _finalWordCompletionDelay = Duration(milliseconds: 1000);
  bool _finalWordCompletionPending = false;
  bool _listeningForContinue = false;
  static const String _continueCommandPhrase = 'continue';
  bool _suppressNextLinger = false;
  bool _manualSeekInFlight = false;
  int? _pendingManualSeekIndex;
  List<String?> _panelAssignments = [];
  int _lastAutoScrollLine = -1;
  double _idealScrollOffset = 0.0;
  double _currentScrollOffset = 0.0;
  bool _manualScrollActive = false; // Track manual scroll state
  
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
    _currentBeatIndex = _findNextEnabledBeatIndex(_currentBeatIndex);
    final bool hasEnabledBeat = _currentBeatIndex < widget.story.beats.length;
    _preparePanelAssignments();
    
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
      if (!mounted) return;
      if (!hasEnabledBeat) {
        _completeStory();
      } else {
      _initializeAndStartListening();
      }
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
    _finalWordCompletionTimer?.cancel();
    _contentScrollController.dispose();
    super.dispose();
  }
  
  void _checkAndStartListening() {
    if (_currentBeatIndex >= widget.story.beats.length) {
      AppLogger.speech.w('No enabled beats remaining; completing story');
      _completeStory();
      return;
    }
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
      _finalWordCompletionPending = false;
      _manualScrollActive = false; // Reset manual scroll on new beat
    });
    _finalWordCompletionTimer?.cancel();
    
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
    
    if (_isUserMuted) {
      setState(() {
        _narrationTrackingActive = true;
        _wordLinesReady = true;
        _listeningStatusLabel = 'Microphone muted';
      });
      AppLogger.speech.i('ℹ️ Microphone muted - tracking UI active but hardware disabled');
      return;
    }
    
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
      
      if (_isUserMuted) {
        AppLogger.speech.i('🔇 Narration tracking start aborted - user muted during startup');
        if (started) {
          await controller.speechRecognizer.stopNarrationTracking();
        }
        setState(() {
          _narrationTrackingActive = true;
          _wordLinesReady = true;
          _listeningStatusLabel = 'Microphone muted';
        });
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
    final bool trackerReportedEnd = totalWords > 0 && wordIndex >= totalWords;
    int clampedIndex;
    if (totalWords <= 0) {
      clampedIndex = 0;
    } else {
      final int desiredIndex = trackerReportedEnd ? totalWords : wordIndex;
      clampedIndex = desiredIndex.clamp(0, totalWords).toInt();
    }
    final now = DateTime.now();
    final bool progressed = clampedIndex != _lastTrackedWord;
    final bool anchorSource = _isAnchorSource(source);
    bool finalWordConfirmed = _finalWordConfirmed;
    bool shouldScheduleFinalCompletion = false;

    // Check if we should trigger completion
    // Primary: Sherpa anchor confirms final word
    // Fallback: VAD predicts final word and we're at/past the end
    final bool sherpaConfirmedEnd = anchorSource && trackerReportedEnd;
    final bool vadPredictedEnd = source == 'vad' && clampedIndex >= totalWords - 1;
    
    if ((sherpaConfirmedEnd || vadPredictedEnd) && !_finalWordConfirmed && !_finalWordCompletionPending) {
      shouldScheduleFinalCompletion = true;
      final confirmSource = sherpaConfirmedEnd ? 'Sherpa anchor' : 'VAD prediction';
      AppLogger.speech.d('✅ Final word confirmed via $confirmSource (delayed completion)');
    } else if ((sherpaConfirmedEnd || vadPredictedEnd) && (_finalWordConfirmed || _finalWordCompletionPending)) {
      AppLogger.speech.v('⏭️ Skipping final completion schedule: confirmed=$_finalWordConfirmed, pending=$_finalWordCompletionPending');
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
      _lastTrackedWord = clampedIndex;
      _v13VadPredictions = vadPredictions;
      _v13Anchors = anchors;
      _v13Corrections = corrections;
      _estimatedWPM = updatedWpm;
      _currentTargetWord = 'tracking';
      _finalWordConfirmed = finalWordConfirmed;
      _manualScrollActive = false; // Reset manual scroll on progress
      if (anchorSource) {
        _scrollAnchorWordIndex = clampedIndex;
      }
    });

    if (shouldScheduleFinalCompletion) {
      _scheduleFinalWordCompletion();
    }
    
    _lastWordTime = updatedLastWordTime;
    
    final int safeDisplayIndex = totalWords > 0
        ? clampedIndex.clamp(0, maxIndex >= 0 ? maxIndex : 0)
        : 0;
    AppLogger.speech.v(
      '🎯 V13 update [$source] → word ${safeDisplayIndex + 1}/${_narrationWords.length} '
      '(conf ${(confidence * 100).toStringAsFixed(0)}%)',
    );
    
    if (_enableTargetWordCelebrations && progressed && beat.targetWords.isNotEmpty && clampedIndex > 0) {
      _checkForValidatedTargetWords(beat, [_narrationWords[clampedIndex - 1]]);
    }
  }
  
  void _toggleMute() async {
    setState(() {
      _isUserMuted = !_isUserMuted;
    });
    
    final controller = context.read<GameController>();
    
    if (_isUserMuted) {
      // Stop hardware but keep UI intent flags active
    if (_narrationTrackingActive) {
        await controller.speechRecognizer.stopNarrationTracking();
        setState(() => _listeningStatusLabel = 'Microphone muted');
      } else if (_isListening) { 
        await controller.speechRecognizer.stopListening();
      }
      AppLogger.speech.i('🔇 Microphone muted by user');
    } else {
      // Resume hardware based on current intent
      AppLogger.speech.i('🔊 Microphone unmuted by user - resuming...');
      _resumeListening();
    }
  }

  Future<void> _resumeListening() async {
    final controller = context.read<GameController>();
    
    if (_narrationTrackingActive && _narrationWords.isNotEmpty) {
      // Resume narration tracking
      final scriptForTracker = _narrationWords.join(' ');
      final beat = widget.story.beats[_currentBeatIndex];
      
      try {
        final started = await controller.speechRecognizer.startNarrationTracking(
          scriptText: scriptForTracker,
          onWordUpdate: (index, confidence, source) {
            _handleNarrationWordUpdate(beat, index, confidence, source);
          },
          initialWordIndex: _currentWordIndex
        );
        
        if (!mounted) {
          return;
        }
        
        if (_isUserMuted) {
          AppLogger.speech.i('🔇 Narration resume aborted - user muted during startup');
          if (started) {
            await controller.speechRecognizer.stopNarrationTracking();
          }
          setState(() => _listeningStatusLabel = 'Microphone muted');
          return;
        }
        
        if (started) {
          setState(() => _listeningStatusLabel = 'Listening – resume reading');
        }
      } catch (e) {
        AppLogger.speech.e('Failed to resume narration tracking', error: e);
      }
    } else if (_isListening && _currentTargetWord != null && _currentTargetWord != 'tracking') {
       // Resume single word listening
       try {
         await controller.speechRecognizer.startListening(
          onResult: (result) => _handleSpeechResult(result, _currentTargetWord!),
          onPartial: (partial) {
            AppLogger.speech.v('Partial: ${partial.partial}');
          },
          onError: (error) {
            AppLogger.speech.e('Recognition error: $error');
          },
          expectedWord: _currentTargetWord!,
        );
       } catch (e) {
         AppLogger.speech.e('Failed to resume listening', error: e);
       }
    } else if (_finalWordConfirmed && !_currentBeatHasChoicePoint) {
      await _listenForContinueCommandIfReady();
    }
  }

  bool get _shouldShowMicPanel => _isUserMuted || _isListening || _narrationTrackingActive || _manualScrollActive;

  bool get _isMeterActive => !_isUserMuted && (_isListening || _narrationTrackingActive);
  bool get _shouldRevealCurrentPanel =>
      _finalWordConfirmed && _panelPathForBeat(_currentBeatIndex) != null;
  
  Widget _buildListeningPanelContent(bool isTrackingMode) {
    final energyStream = context.read<GameController>().speechRecognizer.energyStream;
    final showManualOverrides = !_isUserMuted && _currentTargetWord != null && _currentTargetWord != 'tracking';
    final confidence = _currentTrackingConfidence.clamp(0.0, 1.0);
    
    final List<Color> buttonGradient;
    if (_isUserMuted) {
      buttonGradient = [Colors.grey.shade800, Colors.black54];
    } else if (isTrackingMode) {
      buttonGradient = [
        Color.lerp(Colors.green.shade400, Colors.greenAccent, confidence) ?? Colors.greenAccent,
        Color.lerp(Colors.green.shade900, Colors.teal.shade800, confidence) ?? Colors.teal.shade800,
      ];
    } else {
      buttonGradient = [Colors.teal.shade200, Colors.teal.shade700];
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggleMute,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(60),
                  gradient: LinearGradient(
                    colors: buttonGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PlushMicrophoneMeter(
                      energyStream: energyStream,
                      isListening: _isMeterActive,
                      isMuted: _isUserMuted,
                      onMuteChanged: (_) => _toggleMute(),
                      size: 80,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (showManualOverrides) ...[
          const SizedBox(width: 18),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.18),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (_currentTargetWord != null && _currentTargetWord != 'tracking') {
                    _onWordRecognized(_currentTargetWord!, correct: true);
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
              ),
              const SizedBox(height: 6),
              IconButton.filled(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.12),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (_currentTargetWord != null && _currentTargetWord != 'tracking') {
                    _onWordRecognized(_currentTargetWord!, correct: false, heard: 'manual skip');
                  }
                },
                icon: const Icon(Icons.skip_next_rounded, size: 18),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _preparePanelAssignments() {
    final beats = widget.story.beats;
    final artPaths = widget.generatedStory?.panelArt?.panelImagePaths ?? [];
    if (beats.isEmpty) {
      _panelAssignments = const [];
      return;
    }

    final assignments = List<String?>.filled(beats.length, null);
    if (artPaths.isEmpty) {
      _panelAssignments = assignments;
      return;
    }

    final narrationIndices = <int>[];
    for (var i = 0; i < beats.length; i++) {
      if (beats[i].type == BeatType.narration) {
        narrationIndices.add(i);
      }
    }
    final targetIndices = narrationIndices.isNotEmpty
        ? narrationIndices
        : List.generate(beats.length, (index) => index);
    for (var i = 0; i < targetIndices.length && i < artPaths.length; i++) {
      assignments[targetIndices[i]] = artPaths[i];
    }
    _panelAssignments = assignments;
  }

  String? _panelPathForBeat(int index) {
    if (_panelAssignments.isEmpty ||
        index < 0 ||
        index >= _panelAssignments.length) {
      return null;
    }
    return _panelAssignments[index];
  }

  double _panelScrollProgress() {
    if (widget.story.beats.isEmpty) {
      return 0.0;
    }
    final beat = widget.story.beats[_currentBeatIndex];
    if (beat.type == BeatType.narration && _narrationWords.isNotEmpty) {
      final maxIndex = _narrationWords.length - 1;
      if (maxIndex <= 0) {
        return _finalWordConfirmed ? 1.0 : 0.0;
      }
      final ratio = _currentWordIndex / maxIndex;
      return ratio.clamp(0.0, 1.0).toDouble();
    }
    return _finalWordConfirmed ? 1.0 : 0.0;
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

  Widget _buildPanelBackdrop() {
    final panelPath = _panelPathForBeat(_currentBeatIndex);
    if (panelPath == null) {
      return Positioned.fill(
        child: Container(color: Colors.grey.shade100),
      );
    }
    final progress = _panelScrollProgress();
    return Positioned.fill(
      child: _PanelBackdropImage(
        key: ValueKey(
          'panel-backdrop-$panelPath-$_currentBeatIndex-$_finalWordConfirmed',
        ),
        imagePath: panelPath,
        reveal: _shouldRevealCurrentPanel,
        progress: progress,
      ),
    );
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
    
    if (_isUserMuted) {
       AppLogger.speech.i('ℹ️ Microphone muted - listening UI active but hardware disabled');
       return;
    }
    
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
          _listeningForContinue = false;
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
  
  Future<void> _nextBeat() async {
    await _cancelContinueCommandListening();
    final nextIndex = _findNextEnabledBeatIndex(_currentBeatIndex + 1);
    if (nextIndex >= widget.story.beats.length) {
      _completeStory();
      return;
    }
    
      _fadeController.reset();
      setState(() {
      _currentBeatIndex = nextIndex;
      _validatedWords.clear();
        _finalWordConfirmed = false;
      _finalWordCompletionPending = false;
      _scrollAnchorWordIndex = -1;
      });
      _fadeController.forward();
      
      // Check if new beat needs voice recognition
      _checkAndStartListening();
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
      builder: (context) {
        int selectedRating = widget.generatedStory?.childRating ?? 0;
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
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
                if (widget.generatedStory != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'How did you like it?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  StarRating(
                    rating: selectedRating,
                    size: 32,
                    allowClear: true,
                    onRatingChanged: (value) async {
                      setStateDialog(() => selectedRating = value);
                      await _storyGeneratorService.setChildRating(
                        widget.generatedStory!.id,
                        value == 0 ? null : value,
                      );
                    },
                  ),
                ],
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
      },
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
    final bool showPanelShowcase = _shouldRevealCurrentPanel;
    final String? currentPanelPath =
        showPanelShowcase ? _panelPathForBeat(_currentBeatIndex) : null;
    
    // Check if there's a choice point at this beat
    final choicePoint = widget.story.choicePoints
        .where((cp) => cp.beatIndex == _currentBeatIndex)
        .firstOrNull;
    final bool isTrackingMode =
        _narrationTrackingActive && _currentTargetWord == 'tracking';
    final bool showMicPanel = _shouldShowMicPanel;
    final bool showContinueButton =
        choicePoint == null || !_finalWordConfirmed;
    final bool showBottomControls = showMicPanel || showContinueButton;
    
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
          _buildPanelBackdrop(),
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (_currentBeatIndex + 1) / widget.story.beats.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                  minHeight: 4,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  child: currentPanelPath != null
                      ? _buildPanelShowcase(context, currentPanelPath)
                      : const SizedBox(width: double.infinity),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // Track manual scrolling
                        if (notification is UserScrollNotification) {
                          if (!_manualScrollActive) {
                            setState(() {
                              _manualScrollActive = true;
                              
                              // Stop tracking immediately on manual interaction
                              if (_narrationTrackingActive) {
                                _narrationTrackingActive = false;
                                _listeningStatusLabel = 'Paused - tap a word to resume';
                                // Stop actual recognizer to prevent fighting with scroll
                                context.read<GameController>().speechRecognizer.stopNarrationTracking();
                              }
                            });
                          }
                        }
                        
                        if (notification is ScrollUpdateNotification) {
                          // Track manual scrolling to adjust focus
                          if (mounted && notification.metrics.axis == Axis.vertical) {
                            setState(() {
                              _currentScrollOffset = notification.metrics.pixels;
                            });
                          }
                        }
                        return false;
                      },
                    child: SingleChildScrollView(
                      controller: _contentScrollController,
                        padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        showBottomControls ? 260 : 40,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildBeatWidget(currentBeat),
                          const SizedBox(height: 24),
                          if (choicePoint != null && _finalWordConfirmed)
                            _buildChoiceWidget(choicePoint),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
          if (showBottomControls)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomControls(
              currentBeat,
              isLastBeat,
              choicePoint != null,
              isTrackingMode,
                ),
            ),
          FireworksOverlay(controller: _fireworksController),
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

  Widget _buildBottomControls(
    StoryBeat beat,
    bool isLastBeat,
    bool hasChoicePoint,
    bool isTrackingMode,
  ) {
    final showMic = _shouldShowMicPanel;
    final instructionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          shadows: const [
            Shadow(
              color: Colors.black45,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        );
    // For choice points, we want to hide the continue button when the choice widget appears
    final showContinue = !hasChoicePoint || !_finalWordConfirmed;
    if (!showMic && !showContinue) {
      return const SizedBox(height: 8);
    }
    
    final continueButton = showContinue ? _buildContinueButton(beat, isLastBeat) : null;
    
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showMic)
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(56),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _buildListeningPanelContent(isTrackingMode),
                ),
              ),
            if (showMic && continueButton != null)
              const SizedBox(height: 18),
            if (continueButton != null) ...[
              Text(
                'Press or say "Continue"',
                textAlign: TextAlign.center,
                style: instructionStyle,
              ),
              const SizedBox(height: 6),
            ],
            if (continueButton != null)
              SizedBox(
                width: double.infinity,
                child: continueButton,
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEnhancedNarrationBubble(StoryBeat beat) {
    if (_shouldRevealCurrentPanel &&
        _panelPathForBeat(_currentBeatIndex) != null) {
      return const SizedBox(height: 16);
    }
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHighlightedText(beat.text, beat.targetWords),
        const SizedBox(height: 18),
        if (_showTargetWordCallouts && beat.targetWords.isNotEmpty)
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
                    color: isValidated ? Colors.green.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isValidated ? Colors.green : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isValidated ? Icons.check_circle : Icons.circle_outlined,
                        color: isValidated ? Colors.green : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        word.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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
    );
  }

  Widget _buildPanelShowcase(BuildContext context, String panelPath) {
    final media = MediaQuery.of(context);
    final double panelHeight = math.max(
      220.0,
      math.min(360.0, media.size.height * 0.35),
    );
    final double squareSize = math.max(
      160.0,
      math.min(panelHeight - 48, media.size.width - 80),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        key: ValueKey('panel-showcase-$panelPath'),
        height: panelHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: _MirroredPanelFill(path: panelPath),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withOpacity(0.85),
                        Colors.transparent,
                        Colors.white.withOpacity(0.85),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.45),
                        Colors.transparent,
                        Colors.white.withOpacity(0.15),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: squareSize,
                  height: squareSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                    image: DecorationImage(
                      image: FileImage(File(panelPath)),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      )
      .animate()
      .fadeIn(duration: 600.ms)
      .blurXY(
        begin: 12,
        end: 0,
        duration: 800.ms,
        curve: Curves.easeOut,
      )
      .scale(
        begin: const Offset(0.8, 0.8),
        end: const Offset(1.0, 1.0),
        duration: 1000.ms,
        curve: Curves.elasticOut,
      )
      .shimmer(
        delay: 600.ms,
        duration: 1800.ms,
        color: Colors.white.withOpacity(0.4),
        angle: -0.5,
        size: 1.5,
        curve: Curves.easeInOut,
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
    
    // Calculate effective focus line based on scroll position
    // If user scrolls up, effective focus moves to earlier lines
    double effectiveFocusLine = -1.0;
    if (currentLine >= 0) {
      // Default to current active line
      effectiveFocusLine = currentLine.toDouble();
      
      // Adjust based on scroll deviation from ideal
      // If we haven't established an ideal yet, assume current is ideal
      if (_idealScrollOffset > 0) {
        final deviation = _idealScrollOffset - _currentScrollOffset;
        // If deviation is positive (scrolled UP), we look back
        // 100.0 is approx line height
        final linesShift = deviation / 100.0;
        effectiveFocusLine = currentLine - linesShift;
      }
    }
    
    final groupedWords = GroupedWordDisplay(
      key: ValueKey('narration-words-${_currentBeatIndex}'), // Stable key to prevent remounting
      displayWords: _narrationDisplayWords,
      wordGroups: _wordGroups,
      currentWordIndex: _currentWordIndex,
      smoothProgress: lineProgress,
      onWordTap: (index) => _jumpToWord(index),
      readingComplete: isComplete,
      scrollWordIndex: _getScrollWordIndex(),
      suppressNextLinger: _suppressNextLinger,
      shouldAutoExpand: true,
      showCompletionCard: isComplete,
      completionCard: isComplete ? _buildCompletionCard() : null,
      focusLineIndex: effectiveFocusLine, // Pass the scroll-adjusted focus
      showAllLines: _manualScrollActive, // NEW: Pass manual scroll state
    );
    
    // Trigger auto-scroll when word index changes
    if (_wordGroups.isNotEmpty) {
      final currentLine = WordGroupingService.getLineForWord(_wordGroups, _currentWordIndex);
      if (currentLine >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToNarrationLine(currentLine);
        });
      }
    }
    
    final Widget readyContent = groupedWords;
    
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
  
  bool _isBeatEnabled(StoryBeat beat) {
    if (!_enableChildPracticeBeats &&
        (beat.type == BeatType.childTurn || beat.type == BeatType.coachIntervention)) {
      return false;
    }
    if (!_enableCelebrationBeats && beat.type == BeatType.celebration) {
      return false;
    }
    return true;
  }
  
  int _findNextEnabledBeatIndex(int startIndex) {
    final beats = widget.story.beats;
    for (int i = startIndex; i < beats.length; i++) {
      if (_isBeatEnabled(beats[i])) {
        return i;
      }
    }
    return beats.length;
  }

  bool get _currentBeatHasChoicePoint {
    return widget.story.choicePoints.any((cp) => cp.beatIndex == _currentBeatIndex);
  }

  Future<void> _listenForContinueCommandIfReady() async {
    if (!mounted) return;
    if (!_finalWordConfirmed) return;
    if (_currentBeatHasChoicePoint) return;
    if (_isUserMuted) return;
    if (_listeningForContinue) return;
    if (!_recognizerInitialized) return;

    final controller = context.read<GameController>();

    if (_narrationTrackingActive) {
      try {
        await controller.speechRecognizer.stopNarrationTracking();
      } catch (e, stackTrace) {
        AppLogger.speech.e(
          'Failed to stop narration tracking before continue listener: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    if (!mounted) return;
    // Consolidate both state updates into a single setState to avoid double rebuild
    setState(() {
      _narrationTrackingActive = false;
      _isListening = true;
      _listeningForContinue = true;
      _currentTargetWord = null;
      _listeningStatusLabel = 'Say "continue" to keep going';
    });

    try {
      await controller.speechRecognizer.startListening(
        expectedWord: _continueCommandPhrase,
        onResult: _handleContinueCommandResult,
        onError: (error) {
          AppLogger.speech.e('Continue command listener error: $error');
          _cancelContinueCommandListening(retry: true);
        },
      );
      AppLogger.speech.i('🎧 Listening for "continue"...');
    } catch (e, stackTrace) {
      AppLogger.speech.e(
        'Failed to start continue command listener: $e',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _isListening = false;
          _listeningForContinue = false;
        });
      }
    }
  }

  Future<void> _handleContinueCommandResult(SpeechRecognitionResult result) async {
    if (!_listeningForContinue) {
      AppLogger.speech.v('Continue result received while idle');
      return;
    }
    final heard = _resultContainsKeyword(result, _continueCommandPhrase);
    if (heard) {
      AppLogger.speech.success('✅ Heard "continue" command');
      await _cancelContinueCommandListening();
      await _nextBeat();
    } else {
      AppLogger.speech.v('Continue command not detected: "${result.text}"');
    }
  }

  bool _resultContainsKeyword(SpeechRecognitionResult result, String keyword) {
    if (keyword.isEmpty) return false;
    final target = keyword.toLowerCase();
    bool _phraseMatches(String phrase) {
      if (phrase.isEmpty) return false;
      return WordList.phraseContainsWord(phrase.toLowerCase(), target);
    }

    if (_phraseMatches(result.text)) {
      return true;
    }
    for (final alt in result.alternatives) {
      if (_phraseMatches(alt.text)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _cancelContinueCommandListening({bool retry = false}) async {
    if (!_listeningForContinue) {
      return;
    }
    if (!mounted) {
      _listeningForContinue = false;
      return;
    }
    final controller = context.read<GameController>();
    try {
      await controller.speechRecognizer.stopListening();
    } catch (e, stackTrace) {
      AppLogger.speech.e(
        'Failed to stop continue command listener: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (!mounted) {
      _listeningForContinue = false;
      return;
    }

    setState(() {
      _isListening = false;
      _listeningForContinue = false;
    });

    if (retry && mounted && _finalWordConfirmed && !_currentBeatHasChoicePoint) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _listenForContinueCommandIfReady();
      });
    }
  }

  void _scheduleFinalWordCompletion() {
    AppLogger.speech.i('📅 Scheduling final word completion in ${_finalWordCompletionDelay.inMilliseconds}ms');
    _finalWordCompletionTimer?.cancel();
    _finalWordCompletionPending = true;
    _finalWordCompletionTimer = Timer(_finalWordCompletionDelay, () async {
      if (!mounted) {
        AppLogger.speech.w('⚠️ Final completion timer fired but widget not mounted');
        _finalWordCompletionPending = false;
        return;
      }
      AppLogger.speech.success('🎉 Final word completion timer fired - showing completion card');
      
      setState(() {
        _finalWordConfirmed = true;
        _finalWordCompletionPending = false;
      });
      
      // Launch fireworks finale!
      if (mounted) {
        _fireworksController.launchMultiple(MediaQuery.of(context).size, count: 5);
      }
      
      // Scroll to bottom AFTER layout settles to show completion card
      // Single smooth scroll operation - no intermediate jumps/restores
      _scrollCompletionIntoView();
      await _listenForContinueCommandIfReady();
    });
  }

  void _scrollCompletionIntoView() {
    if (!mounted) return;
    
    // Wait for layout to fully settle after GroupedWordDisplay expansion
    // Single delayed scroll to avoid competing scroll operations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // Wait for expansion to complete - single delay to ensure layout is stable
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        if (!_contentScrollController.hasClients) return;
        
        final position = _contentScrollController.position;
        final maxExtent = position.maxScrollExtent;
        final currentPos = position.pixels;
        
        // Single smooth scroll to bottom - only if needed
        if (maxExtent > 0 && maxExtent > currentPos + 10) {
          _contentScrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    });
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
  
  void _scrollToNarrationLine(int lineIndex) {
    if (lineIndex == _lastAutoScrollLine) return;
    _lastAutoScrollLine = lineIndex;

    if (!_contentScrollController.hasClients) return;

    // GroupedWordDisplay constants
    const double lineHeight = 100.0;
    const double headerPadding = 20.0;

    final viewportHeight = _contentScrollController.position.viewportDimension;
    final lineTop = headerPadding + (lineIndex * lineHeight);

    // Position line at 35% of viewport height (higher up than center)
    double targetOffset = lineTop - (viewportHeight * 0.35) + (lineHeight / 2);

    final maxScroll = _contentScrollController.position.maxScrollExtent;
    final minScroll = _contentScrollController.position.minScrollExtent;

    targetOffset = targetOffset.clamp(minScroll, maxScroll);

    // Update ideal offset for focus calculations
    if (_idealScrollOffset != targetOffset) {
      _idealScrollOffset = targetOffset;
      // We don't setState here to avoid infinite loops during build/layout
      // The next frame or scroll event will pick it up
    }

    _contentScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }
  
  Future<void> _jumpToWord(int wordIndex) async {
    if (_narrationWords.isEmpty) {
      return;
    }
    await _cancelContinueCommandListening();
    
    final int maxIndex = _narrationWords.length - 1;
    final int targetIndex = wordIndex.clamp(0, maxIndex).toInt();
    
    AppLogger.speech.d('🔄 Jumping to word $targetIndex (tap override)');
    _finalWordCompletionTimer?.cancel();
    
    setState(() {
      _currentWordIndex = targetIndex;
      _scrollAnchorWordIndex = targetIndex;
      _finalWordConfirmed = false;
      _finalWordCompletionPending = false;
      _currentTrackingConfidence = 1.0;
      _lastTrackedWord = targetIndex;
      _suppressNextLinger = true;
      _manualScrollActive = false; // Reset manual scroll on tap
    });

    _enqueueManualNarrationSeek(targetIndex);
    _scheduleLingerReset();
  }

  void _scheduleLingerReset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_suppressNextLinger) {
        setState(() {
          _suppressNextLinger = false;
        });
      }
    });
  }

  void _enqueueManualNarrationSeek(int targetIndex) {
    _pendingManualSeekIndex = targetIndex;
    if (_manualSeekInFlight) {
      return;
    }
    _manualSeekInFlight = true;
    Future.microtask(_processManualNarrationSeekQueue);
  }

  Future<void> _processManualNarrationSeekQueue() async {
    while (_pendingManualSeekIndex != null) {
      final target = _pendingManualSeekIndex!;
      _pendingManualSeekIndex = null;
      await _restartNarrationTrackingAt(target);
    }
    _manualSeekInFlight = false;
  }

  Future<void> _restartNarrationTrackingAt(int targetIndex) async {
    if (_narrationWords.isEmpty) {
      AppLogger.speech.w('Manual seek requested without narration words');
      return;
    }
    final scriptText = _narrationWords.join(' ').trim();
    if (scriptText.isEmpty) {
      AppLogger.speech.w('Manual seek aborted due to empty script text');
      return;
    }

    final beatIndex = _currentBeatIndex;
    final StoryBeat beat = widget.story.beats[beatIndex];
    final controller = context.read<GameController>();

    setState(() {
      _listeningStatusLabel = 'Rewinding narration…';
    });

    if (_narrationTrackingActive) {
    try {
      await controller.speechRecognizer.stopNarrationTracking();
    } catch (e, stackTrace) {
      AppLogger.speech.e(
        'Failed to stop narration tracking before rewind: $e',
        error: e,
        stackTrace: stackTrace,
      );
      }
    }

    if (!mounted || beatIndex != _currentBeatIndex) {
      return;
    }

    setState(() {
      _narrationTrackingActive = false;
    });

    try {
      final started = await controller.speechRecognizer.startNarrationTracking(
        scriptText: scriptText,
        onWordUpdate: (index, confidence, source) {
          _handleNarrationWordUpdate(beat, index, confidence, source);
        },
        initialWordIndex: targetIndex,
      );

      if (!mounted || beatIndex != _currentBeatIndex) {
        return;
      }
      
      if (_isUserMuted) {
        AppLogger.speech.i('🔇 Narration rewind aborted - user muted during startup');
        if (started) {
          await controller.speechRecognizer.stopNarrationTracking();
        }
        setState(() {
          _narrationTrackingActive = true;
          _wordLinesReady = true;
          _listeningStatusLabel = 'Microphone muted';
        });
        return;
      }

      setState(() {
        _narrationTrackingActive = started;
        _wordLinesReady = started && _wordGroups.isNotEmpty;
        _listeningStatusLabel = started
            ? 'Listening – resume when ready'
            : 'Listener unavailable';
        if (started) {
          _currentWordIndex = targetIndex;
          _lastTrackedWord = targetIndex;
          _scrollAnchorWordIndex = targetIndex;
          _currentTargetWord = 'tracking';
        }
      });
    } catch (e, stackTrace) {
      AppLogger.speech.e(
        'Failed to restart narration tracking after rewind: $e',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _listeningStatusLabel = 'Listener unavailable';
          _narrationTrackingActive = false;
        });
      }
    }
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
              onPressed: () {
                _nextBeat();
              },
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
    final requiresValidation = _enableTargetWordCelebrations && beat.targetWords.isNotEmpty;
    final validatedCount = requiresValidation
        ? beat.targetWords.where((w) => _validatedWords[w] ?? false).length
        : 0;
    final allValidated = !requiresValidation || validatedCount == beat.targetWords.length;

    return ElevatedButton(
      onPressed: allValidated
          ? () {
              _nextBeat();
            }
          : null,
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

class _MirroredPanelFill extends StatelessWidget {
  const _MirroredPanelFill({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(-1.0, 1.0),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Expanded(
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}

class _PanelBackdropImage extends StatefulWidget {
  const _PanelBackdropImage({
    super.key,
    required this.imagePath,
    required this.reveal,
    required this.progress,
  });

  final String imagePath;
  final bool reveal;
  final double progress;

  @override
  State<_PanelBackdropImage> createState() => _PanelBackdropImageState();
}

class _PanelBackdropImageState extends State<_PanelBackdropImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panController;

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    )..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    _panController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PanelBackdropImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reveal != widget.reveal) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always pan slowly to create visual interest, even when blurred
    final double horizontalAlignment = 
        ui.lerpDouble(-0.85, 0.85, _panController.value) ?? 0.0;
        
    final double verticalAlignment =
        ui.lerpDouble(-0.3, 0.3, widget.progress) ?? 0.0;
    final double topOverlay =
        ui.lerpDouble(0.5, 0.15, widget.progress) ?? 0.3;
    final double bottomOverlay =
        ui.lerpDouble(0.35, 0.05, widget.progress) ?? 0.15;
    final double targetSigma = widget.reveal ? 4.0 : 6.0;

    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.reveal),
      tween: Tween<double>(
        begin: widget.reveal ? 8.0 : 0.0,
        end: targetSigma,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, sigma, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
                alignment: Alignment(horizontalAlignment, verticalAlignment),
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(topOverlay),
                    Colors.black.withOpacity(bottomOverlay),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
