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
  /// [expectedWord] is the word we're expecting to hear (for context-aware matching)
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
    String? expectedWord,  // Optional: pass expected word for better matching
  });
  
  /// Stop listening
  Future<void> stopListening();
  
  /// Check if currently listening
  bool get isListening;
  
  /// Check if available on this platform
  Future<bool> get isAvailable;
  
  /// Request microphone permissions
  Future<bool> requestPermission();
  
  /// Start narration tracking (V7 word onset detection)
  /// [scriptText] - Full narration text to track
  /// [onWordUpdate] - Callback with (wordIndex, confidence, source)
  Future<bool> startNarrationTracking({
    required String scriptText,
    required Function(int wordIndex, double confidence, String source) onWordUpdate,
  });
  
  /// Stop narration tracking
  Future<void> stopNarrationTracking();
  
  /// Dispose and clean up resources
  void dispose();
}


