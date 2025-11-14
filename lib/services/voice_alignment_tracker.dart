import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';
import '../utils/app_logger.dart';

/// Lightweight voice alignment tracker using VAD + syllable counting
/// 
/// This approach:
/// - Detects voice activity via energy/RMS
/// - Counts syllables from energy peaks
/// - Maps syllables to known word positions
/// - No ML model needed!
/// - Much faster and more accurate than STT for known text
class VoiceAlignmentTracker {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isTracking = false;
  
  // Audio processing parameters
  static const int _sampleRate = 16000;
  
  // VAD parameters
  double _energyThreshold = 0.0;
  final List<double> _energyHistory = [];
  static const int _energyHistorySize = 50; // ~1.6 seconds
  
  // Syllable detection parameters
  final List<double> _syllableTimes = [];
  double _lastPeakTime = 0.0;
  static const double _minPeakDistance = 0.15; // Min 150ms between syllables
  
  // Word tracking
  List<String> _words = [];
  int _currentWordIndex = 0;
  double _startTime = 0.0;
  
  // Callbacks
  Function(int wordIndex)? _onWordAdvance;
  Function(double energy)? _onEnergyUpdate;
  
  /// Initialize the tracker with the known word sequence
  void initialize({
    required List<String> words,
    Function(int wordIndex)? onWordAdvance,
    Function(double energy)? onEnergyUpdate,
  }) {
    _words = words;
    _onWordAdvance = onWordAdvance;
    _onEnergyUpdate = onEnergyUpdate;
    _currentWordIndex = 0;
    _syllableTimes.clear();
    _energyHistory.clear();
    
    AppLogger.speech.i('Voice alignment tracker initialized with ${words.length} words');
  }
  
  /// Start tracking voice alignment
  Future<bool> startTracking() async {
    if (_isTracking) {
      AppLogger.speech.w('Already tracking');
      return false;
    }
    
    try {
      // Check permissions
      if (!await _recorder.hasPermission()) {
        AppLogger.speech.e('Microphone permission denied');
        return false;
      }
      
      // Start recording with stream
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      
      _isTracking = true;
      _startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      _energyThreshold = 0.0; // Will be calculated adaptively
      
      AppLogger.speech.i('Voice alignment tracking started');
      
      // Process audio stream
      stream.listen(
        _processAudioChunk,
        onError: (error) {
          AppLogger.speech.e('Audio stream error: $error');
          _isTracking = false;
        },
        onDone: () {
          AppLogger.speech.i('Audio stream ended');
          _isTracking = false;
        },
      );
      
      return true;
    } catch (e) {
      AppLogger.speech.e('Failed to start tracking: $e');
      _isTracking = false;
      return false;
    }
  }
  
  /// Stop tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;
    
    _isTracking = false;
    await _recorder.stop();
    
    AppLogger.speech.i('Voice alignment tracking stopped');
    AppLogger.speech.d('  Detected ${_syllableTimes.length} syllables');
    AppLogger.speech.d('  Advanced to word ${_currentWordIndex}/${_words.length}');
  }
  
  /// Process a chunk of audio data
  void _processAudioChunk(Uint8List audioData) {
    if (!_isTracking) return;
    
    // Convert PCM16 to float samples
    final samples = _pcm16ToFloat(audioData);
    
    // Calculate RMS energy
    final energy = _calculateRMS(samples);
    
    // Update energy history for adaptive threshold
    _energyHistory.add(energy);
    if (_energyHistory.length > _energyHistorySize) {
      _energyHistory.removeAt(0);
    }
    
    // Adaptive threshold (35th percentile)
    if (_energyHistory.length >= 10) {
      final sorted = List<double>.from(_energyHistory)..sort();
      _energyThreshold = sorted[(sorted.length * 0.35).floor()];
    }
    
    // Notify energy update (for visual feedback)
    _onEnergyUpdate?.call(energy);
    
    // Check for voice activity
    if (energy > _energyThreshold && _energyThreshold > 0) {
      _detectSyllable(energy);
    }
  }
  
  /// Detect syllables from energy peaks
  void _detectSyllable(double energy) {
    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final elapsed = currentTime - _startTime;
    
    // Check if this is a new peak (not too close to last one)
    if (elapsed - _lastPeakTime >= _minPeakDistance) {
      // Check if this is a local maximum
      // (Simple heuristic: if energy is higher than recent average)
      if (_energyHistory.length >= 5) {
        final recentAvg = _energyHistory.sublist(_energyHistory.length - 5).reduce((a, b) => a + b) / 5;
        
        if (energy > recentAvg * 1.3) {
          // New syllable detected!
          _syllableTimes.add(elapsed);
          _lastPeakTime = elapsed;
          
          AppLogger.speech.v('Syllable at ${elapsed.toStringAsFixed(2)}s (energy: ${energy.toStringAsFixed(3)})');
          
          // Update word position
          _updateWordPosition();
        }
      }
    }
  }
  
  /// Update the current word position based on syllables detected
  void _updateWordPosition() {
    if (_words.isEmpty || _currentWordIndex >= _words.length) return;
    
    // Estimate: English averages ~1.5 syllables per word
    // So syllable_count / 1.5 = approximate word count
    final estimatedWords = (_syllableTimes.length / 1.5).floor();
    
    // Advance word position if we've detected enough syllables
    if (estimatedWords > _currentWordIndex) {
      final newIndex = math.min(estimatedWords, _words.length - 1);
      
      if (newIndex > _currentWordIndex) {
        _currentWordIndex = newIndex;
        
        AppLogger.speech.i('Advanced to word ${_currentWordIndex + 1}/${_words.length}: "${_words[_currentWordIndex]}"');
        AppLogger.speech.d('  Based on ${_syllableTimes.length} syllables detected');
        
        // Notify callback
        _onWordAdvance?.call(_currentWordIndex);
      }
    }
  }
  
  /// Convert PCM16 bytes to float samples
  List<double> _pcm16ToFloat(Uint8List pcm16Data) {
    final numSamples = pcm16Data.length ~/ 2;
    final samples = <double>[];
    
    for (int i = 0; i < numSamples; i++) {
      // Little-endian PCM16
      final int16Value = (pcm16Data[i * 2 + 1] << 8) | pcm16Data[i * 2];
      // Handle negative values (two's complement)
      final signedValue = int16Value > 32767 ? int16Value - 65536 : int16Value;
      samples.add(signedValue / 32768.0);
    }
    
    return samples;
  }
  
  /// Calculate RMS (Root Mean Square) energy
  double _calculateRMS(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    
    double sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    
    return math.sqrt(sumSquares / samples.length);
  }
  
  /// Get current word index
  int get currentWordIndex => _currentWordIndex;
  
  /// Get total words
  int get totalWords => _words.length;
  
  /// Check if tracking
  bool get isTracking => _isTracking;
  
  /// Dispose resources
  Future<void> dispose() async {
    if (_isTracking) {
      await stopTracking();
    }
    await _recorder.dispose();
  }
}

