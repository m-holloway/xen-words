import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_models.dart';
import '../models/coaching_session.dart';
import '../models/word_list.dart';
import '../controllers/game_controller.dart';
import '../services/speech_recognizer_interface.dart';
import '../services/voice_alignment_tracker.dart';
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
  
  // HYBRID ALIGNMENT: VAD (fast estimate) + STT (anchoring/validation)
  final VoiceAlignmentTracker _alignmentTracker = VoiceAlignmentTracker();
  bool _isTracking = false;
  double _currentEnergy = 0.0;
  
  // Dual position tracking
  int _vadEstimatedPosition = 0;  // VAD's real-time estimate (may drift)
  // ignore: unused_field
  int _lastConfirmedPosition = 0; // STT-confirmed position (for logging)
  Set<int> _confirmedWordIndices = {}; // Words confirmed by STT (for UI checkmarks)
  
  // Legacy voice recognition state (for STT anchoring + child turns)
  bool _isListening = false;
  bool _recognizerInitialized = false;
  String? _currentTargetWord;
  Map<String, bool> _validatedWords = {}; // word -> validated
  
  // Word tracking for parent narration
  List<String> _narrationWords = [];  // All words in current narration
  int _currentWordIndex = 0;  // Current display position (blend of VAD + STT)
  
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
    _alignmentTracker.dispose();
    super.dispose();
  }
  
  void _checkAndStartListening() {
    final currentBeat = widget.story.beats[_currentBeatIndex];
    
    AppLogger.speech.d('📖 Beat ${_currentBeatIndex + 1}: Type=${currentBeat.type}, Text="${currentBeat.text.substring(0, 30)}..."');
    
    // Auto-start for child turn beats
    if (currentBeat.type == BeatType.childTurn && currentBeat.targetWords.isNotEmpty) {
      AppLogger.speech.d('👦 Child turn detected, listening for: ${currentBeat.targetWords.first}');
      _startListeningForWord(currentBeat.targetWords.first);
    }
    // Auto-start for narration beats - track parent's reading
    else if (currentBeat.type == BeatType.narration) {
      AppLogger.speech.d('📚 Narration beat detected, starting tracking');
      _startNarrationTracking(currentBeat);
    } else {
      AppLogger.speech.d('ℹ️ Other beat type: ${currentBeat.type}');
    }
  }
  
  void _startNarrationTracking(StoryBeat beat) async {
    // Parse all words from narration text
    _narrationWords = _parseNarrationWords(beat.text);
    _currentWordIndex = 0;
    _vadEstimatedPosition = 0;
    _lastConfirmedPosition = 0;
    _confirmedWordIndices.clear();
    
    AppLogger.speech.d('📖 Parsed ${_narrationWords.length} words from narration');
    AppLogger.speech.d('📖 First 5 words: ${_narrationWords.take(5).join(", ")}');
    
    // PHASE 1: Initialize VAD tracker for real-time estimation
    _alignmentTracker.initialize(
      words: _narrationWords,
      onWordAdvance: (wordIndex) {
        if (mounted) {
          // Store VAD estimate
          _vadEstimatedPosition = wordIndex;
          
          // Update display position (tentative)
          setState(() {
            _currentWordIndex = wordIndex;
          });
          
          AppLogger.speech.v('⚡ VAD estimate: word ${wordIndex + 1}/${_narrationWords.length}');
        }
      },
      onEnergyUpdate: (energy) {
        if (mounted) {
          setState(() {
            _currentEnergy = energy;
          });
        }
      },
    );
    
    // Force UI update to show initial state
    setState(() {
      // Trigger rebuild with narration words loaded
    });
    
    // Start VAD tracking (Phase 1: fast estimate)
    AppLogger.speech.i('⚡ PHASE 1: Starting VAD real-time estimation...');
    final vadStarted = await _alignmentTracker.startTracking();
    
    if (vadStarted) {
      setState(() {
        _isTracking = true;
      });
      AppLogger.speech.success('✅ VAD real-time tracking active!');
    } else {
      AppLogger.speech.e('❌ Failed to start VAD tracking');
      return;
    }
    
    // PHASE 2: Start STT for anchoring/validation (runs in parallel)
    AppLogger.speech.i('⚓ PHASE 2: Starting STT anchoring...');
    _startSttAnchoring(beat);
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
  
  void _startSttAnchoring(StoryBeat beat) async {
    if (!_recognizerInitialized) {
      AppLogger.speech.w('STT not initialized, skipping anchoring');
      return;
    }
    
    final controller = context.read<GameController>();
    
    try {
      // Start listening with partial results for anchoring
      await controller.speechRecognizer.startListening(
        onResult: (result) => _handleSttAnchor(result, beat),
        onPartial: (partial) => _handleSttAnchorPartial(partial.partial, beat),
        onError: (error) {
          AppLogger.speech.w('STT anchoring error (non-critical): $error');
        },
        expectedWord: null,  // Open listening
      );
      
      setState(() {
        _isListening = true;
      });
      
      AppLogger.speech.i('⚓ STT anchoring active (validates VAD estimates)');
    } catch (e) {
      AppLogger.speech.w('Could not start STT anchoring: $e');
      // Not critical - VAD will continue working
    }
  }
  
  void _handleSttAnchorPartial(String partialText, StoryBeat beat) {
    if (partialText.isEmpty || _narrationWords.isEmpty) return;
    
    final spokenWords = partialText.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    
    if (spokenWords.isEmpty) return;
    
    // Try to find anchor points in the text
    _findAndApplyAnchors(spokenWords, beat);
  }
  
  void _handleSttAnchor(SpeechRecognitionResult result, StoryBeat beat) {
    if (result.text.isEmpty) return;
    
    final spokenWords = result.text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    
    AppLogger.speech.d('⚓ STT heard: ${spokenWords.join(" ")}');
    
    // Apply anchors from final result
    _findAndApplyAnchors(spokenWords, beat);
  }
  
  void _findAndApplyAnchors(List<String> spokenWords, StoryBeat beat) {
    // Find where these words appear in the narration
    // Look in a window around VAD estimate (VAD may have drifted)
    
    final searchStart = math.max(0, _vadEstimatedPosition - 5);
    final searchEnd = math.min(_narrationWords.length, _vadEstimatedPosition + 10);
    
    // Find longest consecutive match in search window
    int bestMatchStart = -1;
    int bestMatchLength = 0;
    
    for (int i = searchStart; i < searchEnd; i++) {
      int matchLength = 0;
      
      for (int j = 0; j < spokenWords.length && (i + j) < _narrationWords.length; j++) {
        if (_wordsMatch(spokenWords[j], _narrationWords[i + j])) {
          matchLength++;
        } else {
          break;  // Consecutive match broken
        }
      }
      
      if (matchLength > bestMatchLength) {
        bestMatchLength = matchLength;
        bestMatchStart = i;
      }
    }
    
    // Apply anchor if we found a good match (at least 2 consecutive words)
    if (bestMatchLength >= 2 && bestMatchStart >= 0) {
      AppLogger.speech.i('⚓ ANCHOR: Found ${bestMatchLength} words at position $bestMatchStart');
      AppLogger.speech.i('   Words: ${_narrationWords.sublist(bestMatchStart, bestMatchStart + bestMatchLength).join(" ")}');
      
      // Mark these words as confirmed
      for (int i = 0; i < bestMatchLength; i++) {
        _confirmedWordIndices.add(bestMatchStart + i);
      }
      
      // Update confirmed position
      final newConfirmedPosition = bestMatchStart + bestMatchLength - 1;
      
      // If VAD has drifted significantly, adjust it
      if ((_vadEstimatedPosition - newConfirmedPosition).abs() > 3) {
        AppLogger.speech.w('⚠️ VAD drift detected! VAD=$_vadEstimatedPosition, STT=$newConfirmedPosition');
        AppLogger.speech.i('🔄 Correcting VAD position to match STT anchor');
        
        // Don't jump backwards unless very far off
        if (newConfirmedPosition > _vadEstimatedPosition || 
            (_vadEstimatedPosition - newConfirmedPosition) > 5) {
          _vadEstimatedPosition = newConfirmedPosition;
          _lastConfirmedPosition = newConfirmedPosition;
          
          setState(() {
            _currentWordIndex = newConfirmedPosition;
          });
        }
      } else {
        // Small drift - just note the confirmed position
        _lastConfirmedPosition = newConfirmedPosition;
        
        setState(() {
          // Trigger UI update to show confirmed words
        });
      }
      
      // Check for target words
      _checkForValidatedTargetWords(beat, spokenWords);
    }
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
  void _startListeningForNarration() async {
    if (!_recognizerInitialized) {
      return;
    }
    
    setState(() {
      _isListening = true;
      _currentTargetWord = 'tracking';  // Indicate we're in tracking mode
    });
    
    AppLogger.speech.d('📖 Continuous tracking: ${_narrationWords.length} words total');
    
    final controller = context.read<GameController>();
    
    try {
      await controller.speechRecognizer.startListening(
        onResult: (result) => _handleNarrationResult(result),
        onPartial: (partial) {
          // CRITICAL: Use partial results for real-time tracking!
          _handleNarrationPartial(partial.partial);
        },
        onError: (error) {
          AppLogger.speech.e('Narration recognition error: $error');
        },
        expectedWord: null,  // No specific word expected - open listening
      );
      AppLogger.speech.success('📖 Real-time tracking ACTIVE');
    } catch (e) {
      AppLogger.speech.e('Failed to start narration tracking', error: e);
    }
  }
  
  void _handleNarrationPartial(String partialText) {
    if (!_isListening || partialText.isEmpty) {
      return;
    }
    
    final spokenWords = partialText.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    
    if (spokenWords.isEmpty) return;
    
    AppLogger.speech.v('📖 Partial: ${spokenWords.join(" ")}');
    
    // Try to find where parent is in the text based on partial results
    // Look for the BEST match in upcoming text
    final newPosition = _findBestPositionFromPartial(spokenWords);
    
    if (newPosition != null && newPosition > _currentWordIndex) {
      setState(() {
        _currentWordIndex = newPosition;
      });
      
      AppLogger.speech.v('📖 → Position ${_currentWordIndex + 1}/${_narrationWords.length}');
      
      // Check for target words in the partial
      final currentBeat = widget.story.beats[_currentBeatIndex];
      _checkForValidatedTargetWords(currentBeat, spokenWords);
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
  
  int? _findBestPositionFromPartial(List<String> spokenWords) {
    // HYBRID CONFIDENCE MATCHING:
    // - High confidence (exact match) → 1 word OK
    // - Medium confidence (fuzzy) → 2+ words required
    // - Small lookahead window to prevent jumping
    
    if (spokenWords.isEmpty) return null;
    
    // STRICT CONSTRAINT: Only look ahead 3-5 words
    // This prevents matching random words from background conversation
    final lookAhead = 5;
    final startIndex = _currentWordIndex;
    final endIndex = (startIndex + lookAhead).clamp(0, _narrationWords.length);
    
    AppLogger.speech.v('🔍 Analyzing: "${spokenWords.join(" ")}" (${spokenWords.length} words)');
    AppLogger.speech.v('🔍 Looking in window: $_currentWordIndex → $endIndex');
    
    int? bestPosition;
    int bestScore = 0;
    int bestConsecutiveMatches = 0;
    bool bestHasHighConfidence = false;
    
    // Try each position in the small lookahead window
    for (int i = startIndex; i < endIndex; i++) {
      int score = 0;
      int longestStreak = 0;
      int currentStreak = 0;
      bool hasHighConfidenceMatch = false;
      
      // Try to match sequences starting at position i
      final maxCheck = math.min(spokenWords.length, _narrationWords.length - i);
      
      for (int j = 0; j < maxCheck; j++) {
        final spokenWord = spokenWords[j];
        final narrationWord = _narrationWords[i + j];
        
        if (_wordsMatch(spokenWord, narrationWord)) {
          // Match found!
          currentStreak++;
          longestStreak = math.max(longestStreak, currentStreak);
          
          // Check confidence level
          final isHighConfidence = _isHighConfidenceMatch(spokenWord, narrationWord);
          if (isHighConfidence) {
            hasHighConfidenceMatch = true;
            // High confidence match gets bonus
            score += currentStreak * 4;  // 4, 8, 12, 16...
          } else {
            // Regular match
            score += currentStreak * 3;  // 3, 6, 9, 12...
          }
        } else {
          // Break in sequence - reset streak but allow ONE skip
          if (currentStreak > 0 && j < maxCheck - 1) {
            // Allow one word skip, but penalize
            score -= 2;
          }
          currentStreak = 0;
        }
      }
      
      AppLogger.speech.v('   Pos $i: score=$score, consecutive=$longestStreak, highConf=$hasHighConfidenceMatch');
      
      // Update best if this is better
      if (longestStreak >= 1) {  // At least 1 match required
        if (score > bestScore || 
            (score == bestScore && longestStreak > bestConsecutiveMatches)) {
          bestScore = score;
          bestPosition = i;
          bestConsecutiveMatches = longestStreak;
          bestHasHighConfidence = hasHighConfidenceMatch;
        }
      }
    }
    
    // HYBRID CONFIDENCE THRESHOLD:
    // High confidence: 1 word OK if score >= 4 (exact match)
    // Medium confidence: 2+ words required with score >= 6
    bool shouldAdvance = false;
    
    if (bestHasHighConfidence && bestConsecutiveMatches >= 1 && bestScore >= 4) {
      // Single high-confidence word can advance (e.g., "YOU" → "you")
      shouldAdvance = true;
      AppLogger.speech.i('✅ ADVANCE (HIGH CONF): pos=$bestPosition, score=$bestScore, consecutive=$bestConsecutiveMatches');
    } else if (bestConsecutiveMatches >= 2 && bestScore >= 6) {
      // Multiple words with moderate confidence
      shouldAdvance = true;
      AppLogger.speech.i('✅ ADVANCE (MULTI WORD): pos=$bestPosition, score=$bestScore, consecutive=$bestConsecutiveMatches');
    } else {
      AppLogger.speech.v('⏸️ HOLD: score=$bestScore, consecutive=$bestConsecutiveMatches, highConf=$bestHasHighConfidence');
    }
    
    return shouldAdvance ? bestPosition : null;
  }
  
  int? _findBestMatchInSequence(List<String> spokenWords) {
    // Fallback method for final results (less aggressive than partial)
    return _findBestPositionFromPartial(spokenWords);
  }
  
  // DEPRECATED: Duplicate _wordsMatch (see line 339 for active version)
  // ignore: unused_element
  bool _wordsMatchOld(String spoken, String expected) {
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
  
  /// Check if match is high confidence (exact match, not homonym/fuzzy)
  bool _isHighConfidenceMatch(String spoken, String expected) {
    // Only exact matches or very close prefix matches are high confidence
    return spoken == expected || 
           (spoken.length >= 3 && expected.startsWith(spoken)) ||
           (expected.length >= 3 && spoken.startsWith(expected));
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
    // Stop alignment tracking
    if (_isTracking) {
      await _alignmentTracker.stopTracking();
      setState(() {
        _isTracking = false;
      });
      AppLogger.speech.d('Stopped alignment tracking');
    }
    
    // Stop legacy STT listening (for child turns)
    if (_isListening) {
      final controller = context.read<GameController>();
      await controller.speechRecognizer.stopListening();
      
      setState(() {
        _isListening = false;
        _currentTargetWord = null;
      });
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
                        Flexible(
                          child: Text(
                            _isTracking
                                ? '⚡ VAD: ${_vadEstimatedPosition + 1}/${_narrationWords.length} | ⚓ STT: ${_confirmedWordIndices.length} confirmed ${_currentEnergy > 0.01 ? "🔊" : ""}'
                                : _currentTargetWord != null
                                    ? 'Listening for "$_currentTargetWord"...'
                                    : 'Ready',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                        _currentTargetWord == 'tracking'
                            ? '📚 Reading along with you!'
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
    if (_narrationWords.isEmpty) {
      AppLogger.speech.w('⚠️ Narration words not yet parsed, parsing now');
      _narrationWords = _parseNarrationWords(beat.text);
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
    // Simple word-by-word highlighting with VAD alignment
    // Show ALL words, highlight current position
    
    AppLogger.speech.v('🎨 Building highlighted text: ${_narrationWords.length} words, current=$_currentWordIndex');
    
    // Parse into clean words
    final segments = text.split(RegExp(r'\s+'));
    
    final words = <Widget>[];
    
    // Check if we're at the end
    final isComplete = _currentWordIndex >= segments.length - 1;
    
    if (isComplete) {
      // Show completion message
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade600, width: 3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Reading complete! ✨',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _nextBeat,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue →',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }
    
    int wordIndex = 0;
    
    for (final segment in segments) {
      if (segment.trim().isEmpty) continue;
      
      // Remove trailing punctuation for matching
      final cleanWord = segment.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
      final isTargetWord = targetWords.any((t) => t.toLowerCase() == cleanWord);
      
      final isCurrent = wordIndex == _currentWordIndex;
      final isRead = wordIndex < _currentWordIndex;
      final isConfirmed = _confirmedWordIndices.contains(wordIndex);
      
      Widget wordWidget;
      
      if (isTargetWord) {
        // Target words - special amber/green boxes
        final isValidated = _validatedWords[cleanWord] ?? false;
        wordWidget = GestureDetector(
          onTap: () => _jumpToWord(wordIndex),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isValidated ? Colors.green.shade100 : Colors.amber.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isValidated ? Colors.green.shade600 : Colors.amber.shade600,
                width: 3,
              ),
            ),
            child: Text(
              segment,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: isValidated ? Colors.green.shade900 : Colors.orange.shade900,
              ),
            ),
          ),
        );
      } else if (isCurrent) {
        // CURRENT WORD - Different styling for VAD estimate vs STT-confirmed
        if (isConfirmed) {
          // STT-CONFIRMED: Solid blue with checkmark
          wordWidget = GestureDetector(
            onTap: () => _jumpToWord(wordIndex),
            child: Container(
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.shade900,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade300,
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    segment,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // VAD ESTIMATE: Lighter blue, tentative (no checkmark yet)
          wordWidget = GestureDetector(
            onTap: () => _jumpToWord(wordIndex),
            child: Container(
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade300,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.shade400,
                  width: 2,
                ),
              ),
              child: Text(
                segment,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }
      } else if (isRead) {
        // Read - with checkmark (smaller, subtle)
        wordWidget = GestureDetector(
          onTap: () => _jumpToWord(wordIndex),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, color: Colors.green.shade400, size: 12),
                const SizedBox(width: 3),
                Text(
                  segment,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Unread - dimmed
        wordWidget = GestureDetector(
          onTap: () => _jumpToWord(wordIndex),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              segment,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        );
      }
      
      words.add(wordWidget);
      wordIndex++;
    }
    
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 10,
      children: words,
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

