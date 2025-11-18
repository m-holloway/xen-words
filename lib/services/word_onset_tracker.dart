import 'dart:math';
import 'dart:typed_data';
import '../utils/app_logger.dart';
import 'phoneme_matcher.dart';

/// V13: Sherpa-Anchored VAD Tracker
/// 
/// Two-phase approach for robust word tracking:
/// 1. Sherpa ANCHORS position (confirms where we are)
/// 2. VAD PREDICTS next word immediately (low latency)
/// 
/// Key Innovation: Uses Sherpa word count (not text matching) for anchoring.
/// Robust to pronunciation errors and partial transcriptions.
/// 
/// Performance: 60/61 words (98.4%), VAD=33, Anchors=57, Corrections=3
/// Tested spacing: 300ms optimal (tested 180-300ms range)
class WordOnsetTracker {
  // VAD Parameters (tuned for V13)
  static const double energyThreshold = 0.011;      // Speech vs silence
  static const double onsetThreshold = 0.007;       // Onset sensitivity
  static const double minWordSpacing = 0.30;        // 300ms - avoids syllable triggers
  static const double minSilenceGap = 0.12;         // need 120ms of silence between words
  static const int energyHistorySize = 4;           // Frames for smoothing
  
  // Anchor management
  static const int maxPredictionsBeforeLostAnchor = 5;  // Lose anchor after 5 VAD predictions
  static const int maxLookaheadWords = 1;               // Only run at most 1 word ahead of last confirmation
  static const int maxUnconfirmedCatchup = 1;           // Limit blind Sherpa catch-ups
  
  // State
  late final List<String> _scriptWords;
  int _currentWordIndex = 0;
  
  // Anchor state
  bool _isAnchored = false;                         // Do we trust our position?
  int _wordsPredictedSinceAnchor = 0;               // VAD predictions since last Sherpa confirmation
  int _lastConfirmedWordIndex = -1;                 // Last Sherpa-confirmed index
  
  // Tracking stats
  int _vadPredictions = 0;
  int _sherpaAnchors = 0;
  int _sherpaCorrections = 0;
  
  // VAD state
  final List<double> _energyHistory = [];
  bool _isSpeech = false;
  double _lastSilenceTime = 0.0;
  double _lastOnsetAudioTime = 0.0;
  
  // Sherpa state
  String _lastSherpaText = '';
  int _lastSherpaWordCount = 0;
  
  /// Create tracker with script words
  WordOnsetTracker(List<String> scriptWords) {
    _scriptWords = List.from(scriptWords);
    
    AppLogger.speech.i(
      'V13 WordOnsetTracker initialized: ${_scriptWords.length} words'
    );
  }
  
  /// Process audio frame and return current word index
  /// 
  /// [audioChunk]: 16ms audio frame (typically ~256 samples at 16kHz)
  /// [audioTime]: Current time in audio (seconds)
  /// [sherpaText]: Latest Sherpa transcription (empty if none)
  /// 
  /// Returns: (wordIndex, confidence, source)
  /// where source is 'vad', 'sherpa_anchor', 'sherpa_catchup', 'sherpa_correction', or 'hold'
  (int, double, String) update(
    Float32List audioChunk,
    double audioTime,
    String sherpaText,
  ) {
    String source = 'hold';
    double confidence = 0.5;
    
    // STEP 1: SHERPA ANCHORING (check if we're aligned)
    if (sherpaText.isNotEmpty && sherpaText != _lastSherpaText) {
      final sherpaWords = sherpaText
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final newWordCount = sherpaWords.length;
      final wordIncrease = newWordCount - _lastSherpaWordCount;
      final newTokens = wordIncrease > 0 && newWordCount >= wordIncrease
          ? sherpaWords.sublist(newWordCount - wordIncrease)
          : const <String>[];
      
      if (wordIncrease > 0) {
        // Sherpa detected new words
        final int matchedTokens = _applyPhoneticAnchors(newTokens);
        final bool anchoredBySimilarity = matchedTokens > 0;
        int residualIncrease = max(0, wordIncrease - matchedTokens);
        if (matchedTokens == 0) {
          residualIncrease = min(residualIncrease, maxUnconfirmedCatchup);
        }
        
        // Check if we over-predicted or under-predicted
        if (_wordsPredictedSinceAnchor > wordIncrease) {
          // We got ahead of ourselves - pull back
          final correction = _wordsPredictedSinceAnchor - wordIncrease;
          _currentWordIndex = max(0, _currentWordIndex - correction);
          _sherpaCorrections++;
          source = 'sherpa_correction';
          
          AppLogger.speech.w(
            '🔧 V13 Correction: -$correction words (predicted $_wordsPredictedSinceAnchor, Sherpa saw $wordIncrease)'
          );
        } else if (_wordsPredictedSinceAnchor < residualIncrease) {
          // We didn't predict enough - Sherpa is ahead
          final catchUp = residualIncrease - _wordsPredictedSinceAnchor;
          _currentWordIndex = min(_scriptWords.length, _currentWordIndex + catchUp);
          
          if (_wordsPredictedSinceAnchor == 0) {
            source = 'sherpa_anchor';
          } else {
            source = 'sherpa_catchup';
          }
          
          AppLogger.speech.d(
            '📝 V13 Catch-up: +$catchUp words (Sherpa ahead)'
          );
        }
        
        // ANCHOR: We now trust our position
        _isAnchored = true;
        _wordsPredictedSinceAnchor = 0;
        _sherpaAnchors++;
        _lastConfirmedWordIndex = _currentWordIndex;
        _lastSilenceTime = _lastOnsetAudioTime;
        
        if (anchoredBySimilarity && (source == 'hold' || source.startsWith('sherpa'))) {
          source = 'sherpa_anchor';
          confidence = 0.95;
        } else {
          confidence = 0.9;
        }
        
        if (newWordCount <= 3) {
          final lastWord = sherpaWords.isNotEmpty ? sherpaWords.last : '';
          AppLogger.speech.d(
            "⚓ V13 Anchored at word $_currentWordIndex (Sherpa: '$lastWord')"
          );
        }
      }
      
      _lastSherpaText = sherpaText;
      _lastSherpaWordCount = newWordCount;
    }
    
    // STEP 2: VAD PREDICTION (only when anchored)
    final onset = _detectOnset(audioChunk, audioTime);
    
    if (onset && _isAnchored) {
      // Predict next word immediately
      if (_currentWordIndex < _scriptWords.length) {
        final bool hasConfirmed = _lastConfirmedWordIndex >= 0;
        final int maxAllowedWord = hasConfirmed
            ? min(_scriptWords.length, _lastConfirmedWordIndex + maxLookaheadWords)
            : _scriptWords.length;
        
        if (hasConfirmed && _currentWordIndex >= maxAllowedWord) {
          source = 'hold';
          confidence = 0.7;
          AppLogger.speech.d(
            '🛑 V13 lookahead cap hit (idx $_currentWordIndex, confirmed $_lastConfirmedWordIndex)'
          );
        } else {
          _currentWordIndex++;
          _vadPredictions++;
          _wordsPredictedSinceAnchor++;
          source = 'vad';
          confidence = 0.85;
          
          AppLogger.speech.d(
            '⚡ V13 VAD Predicts: word ${_currentWordIndex - 1} '
            '"${_scriptWords[_currentWordIndex - 1]}"'
          );
          
          // Lose anchor confidence after too many predictions
          if (_wordsPredictedSinceAnchor >= maxPredictionsBeforeLostAnchor) {
            _isAnchored = false;
            AppLogger.speech.w(
              '⚠ V13 Lost anchor (too many predictions without confirmation)'
            );
          }
        }
      }
    }
    
    return (_currentWordIndex, confidence, source);
  }
  
  /// Detect word onset using VAD with 300ms spacing
  bool _detectOnset(Float32List audioChunk, double currentTime) {
    if (audioChunk.isEmpty) return false;
    
    // Calculate RMS energy
    double sumSquares = 0.0;
    for (final sample in audioChunk) {
      sumSquares += sample * sample;
    }
    final rmsEnergy = sqrt(sumSquares / audioChunk.length);
    
    // Add to history
    _energyHistory.add(rmsEnergy);
    if (_energyHistory.length > energyHistorySize) {
      _energyHistory.removeAt(0);
    }
    
    if (_energyHistory.length < 3) {
      return false;  // Need history
    }
    
    // Check if transitioning from silence to speech
    final bool wasSpeech = _isSpeech;
    _isSpeech = rmsEnergy > energyThreshold;
    
    if (! _isSpeech && wasSpeech) {
      _lastSilenceTime = currentTime;
    }
    
    if (!wasSpeech && _isSpeech) {
      // Check inter-word spacing (300ms minimum)
      final timeSinceLast = currentTime - _lastOnsetAudioTime;
      final timeSinceSilence = currentTime - _lastSilenceTime;
      
      if (timeSinceLast >= minWordSpacing && timeSinceSilence >= minSilenceGap) {
        // Check for energy jump (confirms real onset, not noise)
        final avgEnergy = _energyHistory.reduce((a, b) => a + b) / _energyHistory.length;
        
        if (avgEnergy > onsetThreshold) {
          // Check for energy ramp-up (not just noise spike)
          final energyIncreasing = _energyHistory.length >= 3 &&
              _energyHistory[_energyHistory.length - 1] > _energyHistory[_energyHistory.length - 2] * 0.8 &&
              _energyHistory[_energyHistory.length - 2] > _energyHistory[_energyHistory.length - 3] * 0.8;
          
          if (energyIncreasing || avgEnergy > onsetThreshold * 1.5) {
            _lastOnsetAudioTime = currentTime;
            return true;
          }
        }
      }
    }
    
    return false;
  }
  
  int _applyPhoneticAnchors(List<String> newTokens) {
    int matched = 0;
    for (final token in newTokens) {
      final normalized = token.trim();
      if (normalized.isEmpty) continue;
      final matchIndex = _findBestScriptMatch(normalized);
      if (matchIndex >= 0) {
        final previousIndex = _currentWordIndex;
        _currentWordIndex = min(_scriptWords.length, matchIndex + 1);
        _lastConfirmedWordIndex = matchIndex;
        _wordsPredictedSinceAnchor = 0;
        _isAnchored = true;
        matched += 1;
        
        AppLogger.speech.d(
          "🔉 Phonetic anchor: '$normalized' → script[${matchIndex}]='${_scriptWords[matchIndex]}' "
          '(idx $previousIndex → $_currentWordIndex)',
        );
      }
    }
    return matched;
  }
  
  int _findBestScriptMatch(String candidate) {
    final clean = candidate.replaceAll(RegExp(r'[^a-z]'), '');
    if (clean.isEmpty || _scriptWords.isEmpty) return -1;
    
    final windowStart = max(0, _currentWordIndex - 1);
    final windowEnd = min(_scriptWords.length - 1, _currentWordIndex + 1);
    
    double bestScore = 0.0;
    int bestIndex = -1;
    
    for (int i = windowStart; i <= windowEnd; i++) {
      final score = PhonemeMatcher.wordSimilarity(clean, _scriptWords[i]);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    
    if (bestScore >= 0.68) {
      AppLogger.speech.d(
        "🔍 Phonetic window match '$clean' → script[${bestIndex}]='${_scriptWords[bestIndex]}' (score=${bestScore.toStringAsFixed(2)})",
      );
      return bestIndex;
    } else {
      AppLogger.speech.d(
        "🔍 Phonetic window miss '$clean' (best=${bestScore.toStringAsFixed(2)}) around idx $_currentWordIndex",
      );
      return -1;
    }
  }
  
  /// Reset tracker state
  void reset() {
    _currentWordIndex = 0;
    _isAnchored = false;
    _wordsPredictedSinceAnchor = 0;
    _lastConfirmedWordIndex = -1;
    _energyHistory.clear();
    _isSpeech = false;
    _lastSilenceTime = 0.0;
    _lastOnsetAudioTime = 0.0;
    _lastSherpaText = '';
    _lastSherpaWordCount = 0;
    _vadPredictions = 0;
    _sherpaAnchors = 0;
    _sherpaCorrections = 0;
    
    AppLogger.speech.i('V13 WordOnsetTracker reset');
  }
  
  /// Get current word (safe accessor)
  String get currentWord => _currentWordIndex < _scriptWords.length
      ? _scriptWords[_currentWordIndex]
      : '';
  
  /// Get script words
  List<String> get scriptWords => _scriptWords;
  
  /// Get current word index
  int get currentWordIndex => _currentWordIndex;
  
  /// Get anchor status
  bool get isAnchored => _isAnchored;
  
  /// Get statistics
  Map<String, dynamic> get statistics => {
    'algorithm': 'V13 Sherpa-Anchored VAD',
    'vad_predictions': _vadPredictions,
    'sherpa_anchors': _sherpaAnchors,
    'sherpa_corrections': _sherpaCorrections,
    'current_position': '$_currentWordIndex/${_scriptWords.length}',
    'is_anchored': _isAnchored,
    'predictions_since_anchor': _wordsPredictedSinceAnchor,
  };
  
  /// Log statistics summary
  void logStatistics() {
    final stats = statistics;
    AppLogger.speech.i('┌─────────────────────────────────────────────');
    AppLogger.speech.i('│ V13 Word Tracker Statistics');
    AppLogger.speech.i('├─────────────────────────────────────────────');
    AppLogger.speech.i('│ VAD predictions:    ${stats['vad_predictions']}');
    AppLogger.speech.i('│ Sherpa anchors:     ${stats['sherpa_anchors']}');
    AppLogger.speech.i('│ Sherpa corrections: ${stats['sherpa_corrections']}');
    AppLogger.speech.i('│ Final position:     ${stats['current_position']}');
    AppLogger.speech.i('│ Anchored:           ${stats['is_anchored']}');
    AppLogger.speech.i('└─────────────────────────────────────────────');
  }
}

/// Helper to convert audio buffer to Float32List
extension AudioConversion on Uint8List {
  /// Convert Int16 PCM to Float32 normalized [-1.0, 1.0]
  Float32List toFloat32Normalized() {
    if (length % 2 != 0) {
      throw ArgumentError('Audio data must have even number of bytes (Int16 pairs)');
    }
    
    final samples = Float32List(length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      // Read Int16 sample (little-endian)
      final byte1 = this[i * 2];
      final byte2 = this[i * 2 + 1];
      final int16Value = (byte2 << 8) | byte1;
      
      // Convert to signed Int16
      final signedValue = int16Value > 32767 ? int16Value - 65536 : int16Value;
      
      // Normalize to [-1.0, 1.0]
      samples[i] = signedValue / 32768.0;
    }
    
    return samples;
  }
}
