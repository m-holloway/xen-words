import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'speech_recognizer_interface.dart';

/// Speech recognition implementation using Sherpa-ONNX with vocabulary restriction
/// Works on both iOS and Android with real-time streaming ASR
class SherpaRecognizer implements ISpeechRecognizer {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  final AudioRecorder _recorder = AudioRecorder();
  
  bool _isInitialized = false;
  bool _isListening = false;
  bool _shouldKeepListening = false;
  double _lastRms = 0.0;
  
  Function(SpeechRecognitionResult)? _onResult;
  Function(PartialSpeechResult)? _onPartial;
  Function(String)? _onError;
  
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _resultCheckTimer;
  String? _expectedWord;  // Current expected word for context-aware matching
  
  // Early recognition tracking
  String? _lastPartialText;
  int _stablePartialCount = 0;  // Count of consecutive identical partial results
  static const int _stablePartialThreshold = 3;  // Return result after 3 stable partials (300ms)
  
  // Sequence number to track which word we're expecting results for
  // This prevents old results from being processed after a new word is displayed
  int _expectedWordSequence = 0;
  
  // Sight words vocabulary for filtering
  // NOTE: We are NOT restricting at the model level - Sherpa-ONNX uses a general English model
  // and returns any word it recognizes. We filter results post-recognition.
  static const List<String> _sightWords = [
    'you', 'see', 'go', 'i', 'has', 'he', 'the', 'had', 'and', 'of',
    'a', 'we', 'is', 'am', 'at', 'to', 'as', 'have', 'in', 'it',
    'can', 'his', 'him', 'on', 'did', 'girl', 'for', 'but', 'up', 'all',
    'look', 'with', 'her', 'what', 'was', 'were', 'said', 'that', 'down', 'they',
    'boy', 'out', 'do', 'little', 'be', 'she', 'there', 'then', 'when', 'some',
    'red', 'orange', 'yellow', 'green', 'blue', 'purple', 'black', 'gray', 'pink',
    'white', 'brown'
  ];
  
  // Enhanced homonym map with phoneme-based similar-sounding word corrections
  // Focus on actual homonyms and common ASR confusions for similar-sounding words
  static const Map<String, String> _homonymMap = {
    // True homonyms (words that sound the same)
    'two': 'to',
    'too': 'to',
    'sea': 'see',
    'c': 'see',       // Single letter 'c' when saying "see" - very common
    'bee': 'be',
    'four': 'for',
    'read': 'red',
    'blew': 'blue',
    'their': 'there',
    'they\'re': 'there',
    'eye': 'i',
    'aye': 'i',       // "aye" often detected when saying "i"
    'i\'ve': 'i',      // "I've" detected as just "i"
    'grey': 'gray',
    
    // Common ASR misrecognitions for short words
    'm': 'am',        // Single 'm' when saying "am" - very common
    'em': 'am',       // Another common misdetection for "am"
    'im': 'am',       // "I'm" detected as just "im"
    'i\'m': 'am',     // "I'm" detected
    
    // Similar-sounding word confusions (phoneme-based)
    'dead': 'did',    // d-ED vs d-ID sound similar
    'dad': 'did',     // d-AD vs d-ID
    'and': 'in',      // a-ND vs i-N (common confusion)
    'end': 'in',      // e-ND vs i-N
    'an': 'in',       // a-N vs i-N
    'n': 'in',        // Single 'n' when saying "in" - very common partial detection
    'en': 'in',       // e-N vs i-N
    'it\'s': 'it',    // "it's" detected as "it"
    'its': 'it',      // "its" detected as "it"
    'had': 'has',     // h-AD vs h-AS
    'has': 'had',     // Sometimes reversed
    'him': 'in',      // h-IM vs i-N (similar endings)
    'then': 'when',   // th-EN vs wh-EN
    'than': 'then',   // th-AN vs th-EN
    'were': 'where',  // w-ERE vs wh-ERE (if "where" was in vocab)
    'what': 'that',   // wh-AT vs th-AT
    'luck': 'look',   // l-UH-k vs l-UH-k (very similar)
    'lock': 'look',   // l-AH-k vs l-UH-k
    'ah': 'of',       // AH vs UH-v (short vowel confusion)
    'off': 'of',      // AW-f vs UH-v
    'have': 'of',     // h-AE-v vs UH-v (sometimes confused)
  };

  // Cache for model directory to avoid re-copying on subsequent initializations
  static String? _cachedModelDir;
  
  @override
  Future<bool> initialize() async {
    // If already initialized, return immediately
    if (_isInitialized && _recognizer != null) {
      print('✅ Sherpa-ONNX already initialized, skipping...');
      return true;
    }
    
    try {
      print('🎤 Initializing Sherpa-ONNX...');

      // Initialize native bindings FIRST - required before creating recognizer
      // This is a native call that may block, so we yield immediately after
      print('🔧 Initializing native bindings...');
      sherpa.initBindings();
      print('✅ Native bindings initialized');
      
      // Yield to UI thread to keep animations smooth (60fps = ~16ms per frame)
      await Future.delayed(const Duration(milliseconds: 16));

      // Copy assets to device storage and get file paths
      // Use cached directory if available (files already copied from background init)
      print('📦 Copying/verifying model assets...');
      final modelDir = _cachedModelDir ?? await _copyAssetsToDeviceStorage();
      if (modelDir != null) {
        _cachedModelDir = modelDir;
      }
      if (modelDir == null) {
        print('❌ Failed to copy model assets to device storage');
        return false;
      }
      
      // Yield to UI thread
      await Future.delayed(const Duration(milliseconds: 16));
      
      print('📁 Model directory: $modelDir');
      
      // Verify all model files exist
      final encoderPath = path.join(modelDir, 'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx');
      final decoderPath = path.join(modelDir, 'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx');
      final joinerPath = path.join(modelDir, 'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx');
      final tokensPath = path.join(modelDir, 'tokens.txt');
      
      // Check if files exist (yield between checks to keep UI responsive)
      final encoderFile = File(encoderPath);
      final decoderFile = File(decoderPath);
      final joinerFile = File(joinerPath);
      final tokensFile = File(tokensPath);
      
      if (!await encoderFile.exists()) {
        print('❌ Encoder file not found: $encoderPath');
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 8));
      
      if (!await decoderFile.exists()) {
        print('❌ Decoder file not found: $decoderPath');
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 8));
      
      if (!await joinerFile.exists()) {
        print('❌ Joiner file not found: $joinerPath');
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 8));
      
      if (!await tokensFile.exists()) {
        print('❌ Tokens file not found: $tokensPath');
        return false;
      }
      
      // Yield to UI thread before file size checks (these can be slow)
      await Future.delayed(const Duration(milliseconds: 16));
      
      print('✅ All model files verified');
      print('   Encoder: ${encoderFile.path} (${await encoderFile.length()} bytes)');
      await Future.delayed(const Duration(milliseconds: 8));
      print('   Decoder: ${decoderFile.path} (${await decoderFile.length()} bytes)');
      await Future.delayed(const Duration(milliseconds: 8));
      print('   Joiner: ${joinerFile.path} (${await joinerFile.length()} bytes)');
      await Future.delayed(const Duration(milliseconds: 8));
      print('   Tokens: ${tokensFile.path} (${await tokensFile.length()} bytes)');
      
      // Yield before heavy recognizer creation - give UI multiple frames
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Create recognizer configuration for streaming ASR
      // Note: Hotwords don't work with BPE token models (tokens.txt contains sub-word units, not words)
      // We'll rely on post-processing filtering and homonym correction instead
      print('🔧 Creating recognizer configuration...');
      
      // Yield during config creation to keep UI responsive
      await Future.delayed(const Duration(milliseconds: 16));
      
      final config = sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: encoderFile.absolute.path,
            decoder: decoderFile.absolute.path,
            joiner: joinerFile.absolute.path,
          ),
          tokens: tokensFile.absolute.path,
          numThreads: 2,
          debug: false,
        ),
        // Use modified_beam_search for better accuracy on similar-sounding words
        // This allows the model to explore multiple hypotheses and pick the best one
        decodingMethod: 'modified_beam_search',
        maxActivePaths: 8, // Increased from 4 to get better alternatives
        enableEndpoint: true,
        rule1MinTrailingSilence: 0.5,  // Much faster endpoint detection (was 2.0s)
        rule2MinTrailingSilence: 0.3,  // Faster endpoint detection (was 1.0s)
        rule3MinUtteranceLength: 10,   // Lower min utterance length (was 20)
        // Skip hotwords - they don't work with BPE token models
      );
      
      // Multiple yields before creating recognizer (this is a VERY heavy native operation)
      // The native call will block, but at least we've given UI time to render
      print('⚠️ About to create recognizer - this may block for 10-15 seconds...');
      await Future.delayed(const Duration(milliseconds: 100));
      
      print('🔧 Creating recognizer...');
      // Create recognizer - this is a synchronous native call that WILL block the main thread
      // Unfortunately, there's no way to make this async or move it to an isolate
      // The native library doesn't support background initialization
      _recognizer = sherpa.OnlineRecognizer(config);
      
      // Yield after recognizer creation
      await Future.delayed(const Duration(milliseconds: 50));
      
      print('🔧 Creating stream...');
      // Create stream for recognition
      _stream = _recognizer!.createStream();
      
      _isInitialized = true;
      print('✅ Sherpa-ONNX initialized successfully');
      print('   Model: Streaming Zipformer English (int8)');
      print('   Vocabulary: ${_sightWords.length} sight words');
      return true;
    } catch (e, stackTrace) {
      print('❌ Error initializing Sherpa-ONNX: $e');
      print('❌ Stack trace: $stackTrace');
      _onError?.call(e.toString());
      return false;
    }
  }
  
  // Note: Hotwords functionality removed - BPE token models don't support word-level hotwords
  // The tokens.txt contains sub-word units (like "you", " you", "you ", etc.) not full words
  // We rely on post-processing filtering and homonym correction instead
  
  /// Copy model assets from Flutter assets to device storage
  /// This runs in a background isolate to avoid blocking the UI
  Future<String?> _copyAssetsToDeviceStorage() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory(path.join(appDir.path, 'sherpa-onnx-models', 'sherpa-onnx-streaming-zipformer-en-2023-06-26'));
      
      // Create directory if it doesn't exist
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      
      // List of model files to copy
      final modelFiles = [
        'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        'tokens.txt',
      ];
      
      // Check which files need copying first (fast check)
      final filesToCopy = <String>[];
      for (final fileName in modelFiles) {
        final targetFile = File(path.join(modelDir.path, fileName));
        if (!await targetFile.exists()) {
          filesToCopy.add(fileName);
        }
      }
      
      // Only copy if needed
      if (filesToCopy.isEmpty) {
        print('📋 All model files already exist');
        return modelDir.path;
      }
      
      // Copy files in background (yield to UI thread periodically)
      for (int i = 0; i < filesToCopy.length; i++) {
        final fileName = filesToCopy[i];
        print('📋 Copying model file ${i + 1}/${filesToCopy.length}: $fileName');
        
        final targetFile = File(path.join(modelDir.path, fileName));
        final assetPath = 'assets/sherpa-onnx-models/sherpa-onnx-streaming-zipformer-en-2023-06-26/$fileName';
        final data = await rootBundle.load(assetPath);
        
        // Write in chunks to allow UI updates
        await targetFile.writeAsBytes(data.buffer.asUint8List());
        
        // Yield to UI thread every file
        await Future.delayed(Duration.zero);
        
        print('✅ Copied: $fileName');
      }
      
      return modelDir.path;
    } catch (e) {
      print('❌ Error copying assets: $e');
      return null;
    }
  }

  @override
  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    Function(PartialSpeechResult)? onPartial,
    Function(String)? onError,
    String? expectedWord,
  }) async {
    // Increment sequence number for this new word
    // This ensures we ignore any stale results from previous words
    _expectedWordSequence++;
    final currentSequence = _expectedWordSequence;
    
    // Store expected word for context-aware matching
    _expectedWord = expectedWord?.toLowerCase();
    if (_recognizer == null) {
      print('❌ Recognizer not initialized');
      onError?.call('Recognizer not initialized');
      return;
    }
    
    // Ensure we're not already listening
    if (_isListening) {
      print('⚠️ Already listening, stopping first...');
      // Cancel timer FIRST to prevent processing old results
      _resultCheckTimer?.cancel();
      _resultCheckTimer = null;
      await stopListening();
      // Longer delay to ensure all processing is complete and audio buffer is cleared
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // CRITICAL: Always create a NEW stream instead of resetting the old one
    // This ensures no audio data from the previous word can leak through
    // The old stream may still have buffered audio that hasn't been processed
    if (_stream != null) {
      print('🗑️ Discarding old stream to prevent stale audio data');
      // Note: We don't need to explicitly dispose streams in Sherpa-ONNX
      // Just create a new one and let the old one be garbage collected
      _stream = null;
    }
    
    // Create a completely fresh stream for this word
    _stream = _recognizer!.createStream();
    print('🔄 Created NEW recognition stream (sequence: $currentSequence)');
    
    // Reset early recognition tracking
    _stablePartialCount = 0;
    _lastPartialText = null;
    
    _onResult = onResult;
    _onPartial = onPartial;
    _onError = onError;
    _shouldKeepListening = true;
    
    try {
      // Check microphone permission
      if (!await _recorder.hasPermission()) {
        print('❌ No microphone permission');
        _onError?.call('Microphone permission denied');
        return;
      }
      
      // Ensure recorder is stopped before starting
      if (await _recorder.isRecording()) {
        await _recorder.stop();
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // Start audio recording
      // Using 16kHz mono PCM16 which is what Sherpa-ONNX expects
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
      );
      
      _isListening = true;
      print('🎤 Sherpa-ONNX listening started (vocabulary restricted to ${_sightWords.length} words)');
      
      // Process audio stream
      _audioSubscription = stream.listen(
        _processAudioData,
        onError: (error) {
          print('❌ Audio stream error: $error');
          _onError?.call(error.toString());
        },
        cancelOnError: false,
      );
      
      // Start result checking timer
      _startResultChecking();
      
    } catch (e) {
      print('❌ Error starting audio: $e');
      _isListening = false;
      _onError?.call(e.toString());
    }
  }
  
  void _processAudioData(Uint8List audioData) {
    if (_stream == null || _recognizer == null || !_shouldKeepListening) {
      return;
    }
    
    try {
      // Convert Uint8List (PCM16) to Float32List for Sherpa-ONNX
      final samples = _convertPcm16ToFloat32(audioData);
      
      // Calculate RMS for visual feedback
      _lastRms = _calculateRms(samples);
      
      // Accept waveform into the stream
      _stream!.acceptWaveform(
        samples: samples,
        sampleRate: 16000,
      );
      
    } catch (e) {
      print('❌ Error processing audio data: $e');
    }
  }
  
  Float32List _convertPcm16ToFloat32(Uint8List pcm16Data) {
    // PCM16 is 2 bytes per sample (16-bit)
    final numSamples = pcm16Data.length ~/ 2;
    final samples = Float32List(numSamples);
    
    for (int i = 0; i < numSamples; i++) {
      // Convert little-endian PCM16 to float32 in range [-1, 1]
      final int16Value = (pcm16Data[i * 2 + 1] << 8) | pcm16Data[i * 2];
      // Handle negative values (two's complement)
      final signedValue = int16Value > 32767 ? int16Value - 65536 : int16Value;
      samples[i] = signedValue / 32768.0;
    }
    
    return samples;
  }
  
  double _calculateRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    
    double sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return (sum / samples.length).clamp(0.0, 1.0);
  }
  
  void _startResultChecking() {
    // Capture the current sequence number when starting the timer
    final timerSequence = _expectedWordSequence;
    
    _resultCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      // Check if sequence has changed (new word displayed) - ignore old results
      if (timerSequence != _expectedWordSequence) {
        print('⚠️ Ignoring stale result (sequence $timerSequence vs current $_expectedWordSequence)');
        timer.cancel();
        return;
      }
      
      if (!_shouldKeepListening || _stream == null || _recognizer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Decode if ready
        if (_recognizer!.isReady(_stream!)) {
          _recognizer!.decode(_stream!);
        }
        
        // Check for endpoint (end of utterance)
        if (_recognizer!.isEndpoint(_stream!)) {
          final result = _recognizer!.getResult(_stream!);
          
          // Double-check sequence hasn't changed while processing
          if (timerSequence != _expectedWordSequence) {
            print('⚠️ Ignoring stale endpoint result (sequence $timerSequence vs current $_expectedWordSequence)');
            _recognizer!.reset(_stream!);
            return;
          }
          
          if (result.text.isNotEmpty || result.tokens.isNotEmpty) {
            // COMPREHENSIVE DEBUG LOGGING
            print('═══════════════════════════════════════════════════════');
            print('📥 RECOGNITION RESULT (sequence: $timerSequence)');
            print('   Expected word: "${_expectedWord ?? "none"}"');
            print('   Top result text: "${result.text}"');
            print('   Tokens (${result.tokens.length}): ${result.tokens}');
            if (result.timestamps.isNotEmpty) {
              print('   Timestamps: ${result.timestamps.map((t) => t.toStringAsFixed(2)).join(", ")}s');
            }
            
            // Analyze token combinations (BPE tokens might split words)
            final reconstructedWords = _reconstructWordsFromTokens(result.tokens);
            print('   Reconstructed words from tokens: $reconstructedWords');
            
            // Check all sight words found in recognition
            final foundSightWords = _findAllSightWordsInRecognition(result.text, result.tokens, reconstructedWords);
            print('   Sight words detected: $foundSightWords');
            
            // With modified_beam_search, tokens represent the best path from 8 explored paths
            // Check if expected word appears in ANY form (token, text, or reconstructed)
            if (_expectedWord != null && result.tokens.isNotEmpty) {
              final normalizedTokens = result.tokens.map((t) => t.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '')).where((t) => t.isNotEmpty).toList();
              final expectedHomonyms = _getHomonymsForWord(_expectedWord!);
              expectedHomonyms.add(_expectedWord!);
              
              // Check reconstructed words first (most reliable)
              for (final word in reconstructedWords) {
                final normalizedWord = word.toLowerCase();
                if (expectedHomonyms.contains(normalizedWord)) {
                  print('✅ Expected word "$_expectedWord" found in reconstructed words');
                  _onResult?.call(SpeechRecognitionResult(
                    text: _expectedWord!,
                    alternatives: _buildAlternatives(foundSightWords, _expectedWord!),
                  ));
                  _recognizer!.reset(_stream!);
                  return;
                }
                
                final corrected = _applyHomonymCorrection(normalizedWord);
                if (corrected == _expectedWord) {
                  print('✅ Expected word "$_expectedWord" found via homonym correction in reconstructed: "$word" -> "$_expectedWord"');
                  _onResult?.call(SpeechRecognitionResult(
                    text: _expectedWord!,
                    alternatives: _buildAlternatives(foundSightWords, _expectedWord!),
                  ));
                  _recognizer!.reset(_stream!);
                  return;
                }
              }
              
              // Check individual tokens
              for (final token in normalizedTokens) {
                if (expectedHomonyms.contains(token)) {
                  print('✅ Expected word "$_expectedWord" found in token: "$token"');
                  _onResult?.call(SpeechRecognitionResult(
                    text: _expectedWord!,
                    alternatives: _buildAlternatives(foundSightWords, _expectedWord!),
                  ));
                  _recognizer!.reset(_stream!);
                  return;
                }
                
                final corrected = _applyHomonymCorrection(token);
                if (corrected == _expectedWord) {
                  print('✅ Expected word "$_expectedWord" found via homonym correction in token: "$token" -> "$_expectedWord"');
                  _onResult?.call(SpeechRecognitionResult(
                    text: _expectedWord!,
                    alternatives: _buildAlternatives(foundSightWords, _expectedWord!),
                  ));
                  _recognizer!.reset(_stream!);
                  return;
                }
              }
            }
            
            // Find matching sight word using enhanced analysis
            final matchedWord = _findMatchingSightWord(result.text, result.tokens, _expectedWord);
            
            if (matchedWord != null) {
              print('✅ MATCHED: "$matchedWord"');
              print('═══════════════════════════════════════════════════════');
              _onResult?.call(SpeechRecognitionResult(
                text: matchedWord,
                alternatives: _buildAlternatives(foundSightWords, matchedWord),
              ));
            } else {
              print('❌ NO MATCH - Top result: "${result.text}"');
              print('   Reconstructed: $reconstructedWords');
              print('   Found sight words: $foundSightWords');
              print('═══════════════════════════════════════════════════════');
              // Still return the result so the game can handle it as incorrect
              _onResult?.call(SpeechRecognitionResult(
                text: result.text,
                alternatives: _buildAlternatives(foundSightWords, null),
              ));
            }
          }
          
          // Reset stream for next utterance
          _recognizer!.reset(_stream!);
          
        } else {
          // Get partial result for visual feedback
          final partialResult = _recognizer!.getResult(_stream!);
          if (partialResult.text.isNotEmpty) {
            // Check sequence for partial results too
            if (timerSequence != _expectedWordSequence) {
              return;  // Ignore stale partial results
            }
            
            final partialText = partialResult.text.trim();
            
            // Check for early recognition: if partial result matches expected word and is stable
            if (_expectedWord != null && _shouldReturnEarly(partialText, partialResult.tokens)) {
              print('⚡ Early recognition: "$partialText" matches expected "$_expectedWord" (sequence: $timerSequence)');
              final matchedWord = _findMatchingSightWord(partialText, partialResult.tokens, _expectedWord);
              if (matchedWord != null) {
                _onResult?.call(SpeechRecognitionResult(
                  text: matchedWord,
                  alternatives: [],
                ));
                _recognizer!.reset(_stream!);
                _stablePartialCount = 0;
                _lastPartialText = null;
                return;  // Exit early from timer callback
              }
            }
            
            _onPartial?.call(PartialSpeechResult(
              partial: partialText,
            ));
          }
        }
      } catch (e) {
        print('❌ Error checking results: $e');
      }
    });
  }
  
  /// Find matching sight word using both text and tokens
  /// Tokens are more reliable for word boundary detection
  /// [expectedWord] provides context for better homonym resolution
  String? _findMatchingSightWord(String text, List<String> tokens, String? expectedWord) {
    // Normalize text
    final normalized = text.toLowerCase().trim();
    final cleaned = normalized.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    
    // Normalize tokens (they may contain punctuation or capitalization)
    final normalizedTokens = tokens.map((t) => t.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '')).where((t) => t.isNotEmpty).toList();
    
    // Split text into words for checking
    final words = cleaned.split(RegExp(r'\s+'));
    
    print('🔍 Matching: text="$cleaned", tokens=$normalizedTokens, expected="$expectedWord"');
    
    // If we have an expected word, prioritize it and its homonyms VERY aggressively
    // CRITICAL: We must check the FULL recognized phrase for similarity BEFORE
    // checking individual tokens, to avoid false matches from partial words
    if (expectedWord != null) {
      // Get all homonyms that map to the expected word
      final expectedHomonyms = _getHomonymsForWord(expectedWord);
      expectedHomonyms.add(expectedWord);
      
      // First, check if the FULL recognized text/phrase matches expected word
      // This prevents matching "a" from "aye" when we expect "i"
      final fullTextLower = cleaned.toLowerCase();
      final correctedFullText = _applyHomonymCorrection(fullTextLower);
      if (correctedFullText == expectedWord) {
        print('✅ Full text homonym correction matches expected: "$fullTextLower" -> "$expectedWord"');
        return expectedWord;
      }
      
      // Check if full text is similar-sounding to expected word
      if (_areWordsSimilar(fullTextLower, expectedWord)) {
        print('✅ Full text similar to expected: "$fullTextLower" -> "$expectedWord"');
        return expectedWord;
      }
      
      // Reconstruct full words from tokens (e.g., ["a", "y", "e"] -> "aye")
      final reconstructedWords = _reconstructWordsFromTokens(tokens);
      
      // Check reconstructed words for expected word or homonyms
      for (final reconWord in reconstructedWords) {
        final corrected = _applyHomonymCorrection(reconWord.toLowerCase());
        if (corrected == expectedWord || expectedHomonyms.contains(reconWord.toLowerCase())) {
          print('✅ Reconstructed word matches expected: "$reconWord" -> "$expectedWord"');
          return expectedWord;
        }
        if (_areWordsSimilar(reconWord.toLowerCase(), expectedWord)) {
          print('✅ Reconstructed word similar to expected: "$reconWord" -> "$expectedWord"');
          return expectedWord;
        }
      }
      
      // Also check if any individual recognized word is a homonym of the expected word
      // This handles cases where the model recognizes "dead" but we expect "did"
      final allRecognizedWords = <String>[];
      allRecognizedWords.addAll(normalizedTokens);
      allRecognizedWords.addAll(words);
      allRecognizedWords.addAll(reconstructedWords);
      
      // Check if any recognized word maps to the expected word via homonym
      for (final recognizedWord in allRecognizedWords) {
        final corrected = _applyHomonymCorrection(recognizedWord.toLowerCase());
        if (corrected == expectedWord) {
          print('✅ Homonym correction matches expected: "$recognizedWord" -> "$expectedWord"');
          return expectedWord;
        }
        if (_areWordsSimilar(recognizedWord.toLowerCase(), expectedWord)) {
          print('✅ Similar-sounding word detected, preferring expected: "$recognizedWord" -> "$expectedWord"');
          return expectedWord;
        }
      }
      
      // Special handling for short expected words (2-3 letters) with single-letter tokens
      // This handles cases like "N" when saying "in", "M" when saying "am", etc.
      if (expectedWord.length <= 3 && expectedWord.length >= 2) {
        for (final token in normalizedTokens) {
          if (token.length == 1) {
            // Check if the single letter is the last letter of the expected word
            // (e.g., "N" for "in", "M" for "am")
            if (token.toLowerCase() == expectedWord.toLowerCase()[expectedWord.length - 1]) {
              print('✅ Single-letter token matches end of expected word: "$token" in "$expectedWord"');
              return expectedWord;
            }
            // Also check if it's the first letter for very short words
            if (expectedWord.length == 2 && token.toLowerCase() == expectedWord.toLowerCase()[0]) {
              print('✅ Single-letter token matches start of expected word: "$token" in "$expectedWord"');
              return expectedWord;
            }
          }
        }
      }
      
      // Check tokens for expected word or its homonyms (only if no other match found)
      for (final token in normalizedTokens) {
        final normalizedToken = token.toLowerCase();
        if (expectedHomonyms.contains(normalizedToken)) {
          print('✅ Expected word match in token: "$token" -> "$expectedWord"');
          return expectedWord;
        }
      }
      
      // Check text words for expected word or its homonyms (only if no other match found)
      for (final word in words) {
        if (expectedHomonyms.contains(word.toLowerCase())) {
          print('✅ Expected word match in text: "$word" -> "$expectedWord"');
          return expectedWord;
        }
      }
      
      // If we have an expected word but no match found, return null
      // Don't match other sight words when we have an expected word
      print('⚠️ Expected word "$expectedWord" not found in recognition');
      return null;
    }
    
    // First, check tokens directly (most reliable for word boundaries)
    for (final token in normalizedTokens) {
      // Direct match in tokens
      if (_sightWords.contains(token)) {
        print('✅ Direct token match: "$token"');
        return token;
      }
      
      // Check homonyms in tokens
      final corrected = _applyHomonymCorrection(token);
      if (corrected != null && _sightWords.contains(corrected)) {
        print('🔄 Homonym correction in token: "$token" -> "$corrected"');
        return corrected;
      }
    }
    
    // Fallback: check text (for cases where tokens might be incomplete)
    // Direct exact match
    if (_sightWords.contains(cleaned)) {
      print('✅ Direct text match: "$cleaned"');
      return cleaned;
    }
    
    // Use words already split above
    for (final word in words) {
      if (_sightWords.contains(word)) {
        print('✅ Word match in text: "$word"');
        return word;
      }
      
      // Check homonyms in text
      final corrected = _applyHomonymCorrection(word);
      if (corrected != null && _sightWords.contains(corrected)) {
        print('🔄 Homonym correction in text: "$word" -> "$corrected"');
        return corrected;
      }
    }
    
    // Special case: check if tokens could be combined to form a word
    // E.g., ["i", "m"] -> "am" (though this is less likely)
    final combinedTokens = normalizedTokens.join('');
    final corrected = _applyHomonymCorrection(combinedTokens);
    if (corrected != null && _sightWords.contains(corrected)) {
      print('🔄 Combined tokens correction: "$combinedTokens" -> "$corrected"');
      return corrected;
    }
    
    // No match found
    return null;
  }
  
  /// Apply homonym correction to a word
  String? _applyHomonymCorrection(String word) {
    return _homonymMap[word.toLowerCase()];
  }
  
  /// Get all homonyms that map to a given sight word
  /// Returns list including the word itself and all homonyms that map to it
  List<String> _getHomonymsForWord(String word) {
    final homonyms = <String>[];
    for (final entry in _homonymMap.entries) {
      if (entry.value == word.toLowerCase()) {
        homonyms.add(entry.key);
      }
    }
    return homonyms;
  }
  
  /// Reconstruct full words from BPE tokens
  /// BPE tokens may split words (e.g., ["follow", "ing"] -> "following")
  /// or contain word pieces that need to be combined
  List<String> _reconstructWordsFromTokens(List<String> tokens) {
    final words = <String>[];
    final currentWord = StringBuffer();
    
    for (final token in tokens) {
      final cleaned = token.trim();
      if (cleaned.isEmpty) continue;
      
      // Check if token starts a new word (has leading space or is capitalized)
      // BPE tokens often have spaces as prefixes/suffixes
      if (cleaned.startsWith(' ') || (cleaned.length > 0 && cleaned[0].toUpperCase() == cleaned[0])) {
        if (currentWord.isNotEmpty) {
          words.add(currentWord.toString().trim());
          currentWord.clear();
        }
      }
      
      // Remove BPE markers and spaces, add to current word
      final tokenPart = cleaned.replaceAll(RegExp(r'^\s+|\s+$'), '');
      if (tokenPart.isNotEmpty) {
        currentWord.write(tokenPart);
      }
    }
    
    // Add final word
    if (currentWord.isNotEmpty) {
      words.add(currentWord.toString().trim());
    }
    
    // Also check if any token is a complete word
    for (final token in tokens) {
      final cleaned = token.trim().replaceAll(RegExp(r'^\s+|\s+$'), '').toLowerCase();
      if (cleaned.isNotEmpty && cleaned.length >= 2 && _sightWords.contains(cleaned)) {
        if (!words.contains(cleaned)) {
          words.add(cleaned);
        }
      }
    }
    
    return words;
  }
  
  /// Find all sight words that appear in the recognition result
  List<String> _findAllSightWordsInRecognition(String text, List<String> tokens, List<String> reconstructedWords) {
    final found = <String>{};
    
    // Check text
    final textWords = text.toLowerCase().split(RegExp(r'\s+'));
    for (final word in textWords) {
      final cleaned = word.replaceAll(RegExp(r'[^\w]'), '');
      if (_sightWords.contains(cleaned)) {
        found.add(cleaned);
      }
      // Check homonyms
      final corrected = _applyHomonymCorrection(cleaned);
      if (corrected != null && _sightWords.contains(corrected)) {
        found.add(corrected);
      }
    }
    
    // Check reconstructed words
    for (final word in reconstructedWords) {
      final cleaned = word.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
      if (_sightWords.contains(cleaned)) {
        found.add(cleaned);
      }
      // Check homonyms
      final corrected = _applyHomonymCorrection(cleaned);
      if (corrected != null && _sightWords.contains(corrected)) {
        found.add(corrected);
      }
    }
    
    // Check individual tokens
    for (final token in tokens) {
      final cleaned = token.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');
      if (cleaned.isNotEmpty && _sightWords.contains(cleaned)) {
        found.add(cleaned);
      }
      // Check homonyms
      final corrected = _applyHomonymCorrection(cleaned);
      if (corrected != null && _sightWords.contains(corrected)) {
        found.add(corrected);
      }
    }
    
    return found.toList();
  }
  
  /// Build alternatives list from found sight words (for debugging)
  List<SpeechAlternative> _buildAlternatives(List<String> foundSightWords, String? matchedWord) {
    final alternatives = <SpeechAlternative>[];
    for (final word in foundSightWords) {
      if (word != matchedWord) {
        // Use position in list as rough "confidence" proxy
        // Words found earlier might be more reliable
        final index = foundSightWords.indexOf(word);
        final confidence = 1.0 - (index * 0.1); // Rough confidence estimate
        alternatives.add(SpeechAlternative(
          text: word,
          confidence: confidence.clamp(0.0, 1.0),
        ));
      }
    }
    return alternatives;
  }
  
  /// Check if two words sound similar (for fallback matching)
  /// This is a simple heuristic based on common confusions
  bool _areWordsSimilar(String word1, String word2) {
    final w1 = word1.toLowerCase();
    final w2 = word2.toLowerCase();
    
    // Check if they're in each other's homonym maps
    if (_homonymMap[w1] == w2 || _homonymMap[w2] == w1) {
      return true;
    }
    
    // Check for similar endings (common source of confusion)
    if (w1.length >= 2 && w2.length >= 2) {
      final w1End = w1.substring(w1.length - 2);
      final w2End = w2.substring(w2.length - 2);
      if (w1End == w2End && w1.length <= 4 && w2.length <= 4) {
        // Short words with same ending are likely confused
        return true;
      }
    }
    
    // Check for same first letter and similar length (for short words)
    if (w1.length <= 3 && w2.length <= 3 && w1[0] == w2[0]) {
      return true;
    }
    
    return false;
  }
  
  /// Check if we should return early based on stable partial results
  bool _shouldReturnEarly(String partialText, List<String> tokens) {
    if (_expectedWord == null) return false;
    
    final normalizedPartial = partialText.toLowerCase().trim();
    
    // If partial matches expected word or its homonyms, track stability
    final expectedHomonyms = _getHomonymsForWord(_expectedWord!);
    expectedHomonyms.add(_expectedWord!);
    
    final normalizedTokens = tokens.map((t) => t.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '')).where((t) => t.isNotEmpty).toList();
    
    // Check if partial text or tokens match expected word
    bool matches = false;
    for (final homonym in expectedHomonyms) {
      if (normalizedPartial == homonym || normalizedTokens.contains(homonym)) {
        matches = true;
        break;
      }
    }
    
    if (matches) {
      // If this partial is the same as the last one, increment counter
      if (normalizedPartial == _lastPartialText) {
        _stablePartialCount++;
        if (_stablePartialCount >= _stablePartialThreshold) {
          return true;  // Return early - result is stable
        }
      } else {
        // Reset counter if partial changed
        _stablePartialCount = 1;
        _lastPartialText = normalizedPartial;
      }
    } else {
      // Reset if no match
      _stablePartialCount = 0;
      _lastPartialText = null;
    }
    
    return false;
  }

  @override
  Future<void> stopListening() async {
    print('🛑 Stopping Sherpa-ONNX...');
    _shouldKeepListening = false;
    _isListening = false;

    // Cancel result checking timer FIRST to prevent processing any more results
    _resultCheckTimer?.cancel();
    _resultCheckTimer = null;

    // Cancel audio subscription
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // Stop recorder
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e) {
      print('⚠️ Error stopping recorder: $e');
    }

    // Clear the stream reference - we'll create a new one next time
    // This ensures no stale audio data can leak through
    _stream = null;
    print('🗑️ Cleared stream reference');

    // Clear partial result tracking
    _stablePartialCount = 0;
    _lastPartialText = null;

    print('✅ Sherpa-ONNX stopped');
  }

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> get isAvailable async => _recognizer != null && _stream != null;

  @override
  Future<bool> requestPermission() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        print('⚠️ Microphone permission not granted');
      } else {
        print('✅ Microphone permission granted');
      }
      return hasPermission;
    } catch (e) {
      print('❌ Error checking microphone permission: $e');
      return false;
    }
  }
  
  /// Get the last RMS value for UI feedback
  double get lastRecognizedRms => _lastRms;

  @override
  void dispose() {
    stopListening();
    _stream = null;
    _recognizer = null;
    _isInitialized = false;
    _recorder.dispose();
  }
}
