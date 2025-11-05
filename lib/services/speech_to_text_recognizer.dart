import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'speech_recognizer_interface.dart';

/// Speech recognition implementation using speech_to_text package
class SpeechToTextRecognizer implements ISpeechRecognizer {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  
  Function(SpeechRecognitionResult)? _onResult;
  Function(PartialSpeechResult)? _onPartial;
  Function(String)? _onError;

  @override
  Future<bool> initialize() async {
    try {
      return await _speech.initialize(
        onError: (error) {
          print('Speech recognition error: ${error.errorMsg}');
          _onError?.call(error.errorMsg);
        },
        onStatus: (status) {
          print('Speech recognition status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
      );
    } catch (e) {
      print('Error initializing speech recognition: $e');
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
  }) async {
    _onResult = onResult;
    _onPartial = onPartial;
    _onError = onError;

    try {
      _isListening = true;
      await _speech.listen(
        onResult: (stt_result.SpeechRecognitionResult result) {
          if (result.finalResult) {
            // Final result
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
          } else {
            // Partial result
            _onPartial?.call(PartialSpeechResult(
              partial: result.recognizedWords,
            ));
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.confirmation,
        ),
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isListening = false;
      _onError?.call(e.toString());
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _speech.stop();
      _isListening = false;
    } catch (e) {
      print('Error stopping speech recognition: $e');
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
    _speech.stop();
    _speech.cancel();
  }
}

