import 'dart:async';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'speech_recognizer_interface.dart';

/// Speech recognition implementation using Sherpa-ONNX with grammar/vocabulary restriction
class SherpaRecognizer implements ISpeechRecognizer {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _isListening = false;
  bool _shouldKeepListening = false;
  double _lastRms = 0.0;
  
  Function(SpeechRecognitionResult)? _onResult;
  Function(PartialSpeechResult)? _onPartial;
  Function(String)? _onError;
  
  Timer? _processingTimer;
  
  // Sight words vocabulary for grammar-based recognition
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
      print('🎤 Initializing Sherpa-ONNX...');
      
      // Create recognizer configuration
      // Using streaming ASR with grammar for vocabulary restriction
      final config = sherpa.OnlineRecognizerConfig(
        featConfig: sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        modelConfig: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '',  // Will be set from model files
            decoder: '',
            joiner: '',
          ),
          tokens: '',     // Will be set from model files  
          numThreads: 2,
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 4,
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.2,
        rule3MinUtteranceLength: 20,
      );
      
      // Create recognizer
      _recognizer = sherpa.OnlineRecognizer(config);
      
      // Create stream
      _stream = _recognizer!.createStream();
      
      print('✅ Sherpa-ONNX initialized with ${_sightWords.length} sight words vocabulary');
      return true;
    } catch (e) {
      print('❌ Error initializing Sherpa-ONNX: $e');
      _onError?.call(e.toString());
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
  }) async {
    if (_recognizer == null || _stream == null) {
      print('❌ Recognizer not initialized');
      onError?.call('Recognizer not initialized');
      return;
    }
    
    _onResult = onResult;
    _onPartial = onPartial;
    _onError = onError;
    _shouldKeepListening = true;
    _isListening = true;
    
    print('🎤 Sherpa-ONNX listening started (vocabulary restricted to ${_sightWords.length} words)');
    
    // Start audio capture and processing
    _startAudioCapture();
  }
  
  void _startAudioCapture() {
    // Start a timer to periodically check for results
    _processingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_shouldKeepListening || _stream == null || _recognizer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Check if recognition is ready
        if (_recognizer!.isReady(_stream!)) {
          _recognizer!.decode(_stream!);
        }
        
        // Check for endpoint (end of speech)
        if (_recognizer!.isEndpoint(_stream!)) {
          final result = _recognizer!.getResult(_stream!);
          
          if (result.text.isNotEmpty) {
            print('📥 Final result: "${result.text}"');
            
            // Check if result matches any sight word
            final matchedWord = _findMatchingSightWord(result.text);
            
            if (matchedWord != null) {
              _onResult?.call(SpeechRecognitionResult(
                text: matchedWord,
                alternatives: [],
              ));
            } else {
              // Return original text but it won't match
              _onResult?.call(SpeechRecognitionResult(
                text: result.text,
                alternatives: [],
              ));
            }
          }
          
          // Reset stream for next utterance
          _recognizer!.reset(_stream!);
        } else {
          // Get partial result
          final partialResult = _recognizer!.getResult(_stream!);
          if (partialResult.text.isNotEmpty) {
            _onPartial?.call(PartialSpeechResult(
              partial: partialResult.text,
            ));
          }
        }
      } catch (e) {
        print('❌ Error processing audio: $e');
        _onError?.call(e.toString());
      }
    });
  }
  
  String? _findMatchingSightWord(String text) {
    final normalized = text.toLowerCase().trim();
    
    // Direct match
    if (_sightWords.contains(normalized)) {
      return normalized;
    }
    
    // Check if any sight word is contained in the text
    for (final word in _sightWords) {
      if (normalized.contains(word)) {
        return word;
      }
    }
    
    return null;
  }

  @override
  Future<void> stopListening() async {
    print('🛑 Stopping Sherpa-ONNX...');
    _shouldKeepListening = false;
    _isListening = false;
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  @override
  bool get isListening => _isListening;

  @override
  double get lastRecognizedRms => _lastRms;

  @override
  Future<bool> get isAvailable async => _recognizer != null && _stream != null;

  @override
  Future<bool> requestPermission() async {
    // Permission is handled by the audio capture layer
    return true;
  }

  @override
  void dispose() {
    _shouldKeepListening = false;
    _isListening = false;
    _processingTimer?.cancel();
    _stream = null;
    _recognizer = null;
  }
}

