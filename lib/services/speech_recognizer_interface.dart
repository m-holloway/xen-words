/// Result from speech recognition containing recognized text and alternatives
class SpeechRecognitionResult {
  final String text;
  final List<SpeechAlternative> alternatives;
  
  SpeechRecognitionResult({
    required this.text,
    this.alternatives = const [],
  });
}

/// Alternative recognition result with confidence score
class SpeechAlternative {
  final String text;
  final double confidence;
  
  SpeechAlternative({
    required this.text,
    required this.confidence,
  });
}

/// Partial result during recognition
class PartialSpeechResult {
  final String partial;
  
  PartialSpeechResult({required this.partial});
}

/// Abstract interface for speech recognition
abstract class ISpeechRecognizer {
  /// Initialize the speech recognizer
  Future<bool> initialize();
  
  /// Start listening for speech
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
  });
  
  /// Stop listening
  Future<void> stopListening();
  
  /// Check if currently listening
  bool get isListening;
  
  /// Check if available on this platform
  Future<bool> get isAvailable;
  
  /// Request microphone permissions
  Future<bool> requestPermission();
  
  /// Dispose and clean up resources
  void dispose();
}


