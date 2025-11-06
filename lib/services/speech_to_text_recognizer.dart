import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'speech_recognizer_interface.dart';

/// Speech recognition implementation using speech_to_text package
class SpeechToTextRecognizer implements ISpeechRecognizer {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _shouldKeepListening = false;
  bool _isRestarting = false;
  DateTime? _lastResultTime;
  
  Function(SpeechRecognitionResult)? _onResult;
  Function(PartialSpeechResult)? _onPartial;
  Function(String)? _onError;
  
  // Sight words vocabulary for better recognition
  static const List<String> _sightWords = [
    'you', 'see', 'go', 'i', 'has', 'he', 'the', 'had', 'and', 'of',
    'a', 'we', 'is', 'am', 'at', 'to', 'as', 'have', 'in', 'it',
    'can', 'his', 'him', 'on', 'did', 'girl', 'for', 'but', 'up', 'all',
    'look', 'with', 'her', 'what', 'was', 'were', 'said', 'that', 'down', 'they',
    'boy', 'out', 'do', 'little', 'be', 'she', 'there', 'then', 'when', 'some',
    'red', 'orange', 'yellow', 'green', 'blue', 'purple', 'black', 'gray', 'pink',
    'white', 'brown'
  ];

  @override
  Future<bool> initialize() async {
    try {
      return await _speech.initialize(
        onError: (error) {
          print('❌ Speech recognition error: ${error.errorMsg}');
          _onError?.call(error.errorMsg);
          // Try to restart after error if we should keep listening
          if (_shouldKeepListening) {
            Future.delayed(const Duration(seconds: 1), () {
              if (_shouldKeepListening) {
                print('🔄 Auto-restarting after error...');
                _restartListening();
              }
            });
          }
        },
        onStatus: (status) {
          print('🔔 Speech recognition status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            // Auto-restart if we should keep listening and not already restarting
            if (_shouldKeepListening && status == 'done' && !_isRestarting) {
              print('🔄 Listening session ended, auto-restarting...');
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_shouldKeepListening && !_isRestarting) {
                  _restartListening();
                }
              });
            }
          } else if (status == 'listening') {
            _isListening = true;
            print('🎤 Now actively listening...');
          }
        },
      );
    } catch (e) {
      print('❌ Error initializing speech recognition: $e');
      return false;
    }
  }
  
  Future<void> _restartListening() async {
    if (!_shouldKeepListening || _isRestarting) {
      if (_isRestarting) {
        print('⚠️  Already restarting, skipping duplicate restart');
      }
      return;
    }
    
    try {
      _isRestarting = true;
      print('🔄 Restarting listening session...');
      await _startListeningSession();
    } catch (e) {
      print('❌ Error restarting: $e');
    } finally {
      _isRestarting = false;
    }
  }

  @override
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
    String? expectedWord,  // Optional: not used by speech_to_text but kept for interface compatibility
  }) async {
    _onResult = onResult;
    _onPartial = onPartial;
    _onError = onError;
    _shouldKeepListening = true;

    await _startListeningSession();
  }
  
  Future<void> _startListeningSession() async {
    try {
      // Stop any existing session before starting a new one
      if (_speech.isListening) {
        print('🛑 Speech recognizer already listening, stopping first...');
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!_shouldKeepListening) {
        print('⚠️  Should not keep listening, aborting start');
        return;
      }

      print('🎤 Starting speech recognition session with sight words vocabulary...');
      _isListening = true;
      _lastResultTime = DateTime.now();
      
      // Start watchdog timer to detect stuck sessions
      _startWatchdog();
      
      await _speech.listen(
        onResult: (stt_result.SpeechRecognitionResult result) {
          _lastResultTime = DateTime.now();
          print('📥 Got speech result: "${result.recognizedWords}" (final: ${result.finalResult})');
          
          // Only process non-empty final results
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            // Final result with actual content
            final alternatives = result.alternates.map((alt) {
              return SpeechAlternative(
                text: alt.recognizedWords,
                confidence: alt.confidence,
              );
            }).toList();

            _onResult?.call(SpeechRecognitionResult(
              text: result.recognizedWords,
              alternatives: alternatives,
            ));
          } else if (!result.finalResult && result.recognizedWords.isNotEmpty) {
            // Partial result
            _onPartial?.call(PartialSpeechResult(
              partial: result.recognizedWords,
            ));
          }
          // Ignore empty results - they'll be handled by auto-restart
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          onDevice: true,  // Use on-device recognition for better performance
        ),
      );
      print('✅ Speech recognition session started with ${_sightWords.length} sight words');
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
      _isListening = false;
      _onError?.call(e.toString());
    }
  }
  
  void _startWatchdog() {
    Future.delayed(const Duration(seconds: 15), () {
      if (!_shouldKeepListening || _isRestarting) {
        return; // Stop watchdog if we shouldn't be listening or already restarting
      }
      
      if (_lastResultTime != null) {
        final timeSinceLastResult = DateTime.now().difference(_lastResultTime!);
        if (timeSinceLastResult.inSeconds > 12 && !_isRestarting) {
          print('⚠️  Watchdog: No results for ${timeSinceLastResult.inSeconds}s, forcing restart...');
          if (_speech.isListening) {
            _speech.stop();
          }
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_shouldKeepListening && !_isRestarting) {
              _restartListening();
            }
          });
        } else if (_shouldKeepListening && !_isRestarting) {
          // Continue watching only if not restarting
          _startWatchdog();
        }
      } else if (_shouldKeepListening) {
        // Continue watching
        _startWatchdog();
      }
    });
  }

  @override
  Future<void> stopListening() async {
    try {
      print('🛑 Stopping speech recognition...');
      _shouldKeepListening = false;
      _isRestarting = false;
      await _speech.stop();
      _isListening = false;
    } catch (e) {
      print('❌ Error stopping speech recognition: $e');
    }
  }

  @override
  bool get isListening => _isListening && _speech.isListening;

  @override
  Future<bool> get isAvailable async {
    return await _speech.initialize();
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final available = await _speech.initialize();
      return available;
    } catch (e) {
      print('Error requesting microphone permission: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _shouldKeepListening = false;
    _isRestarting = false;
    _speech.stop();
    _speech.cancel();
  }
}

