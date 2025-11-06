import 'dart:async';
import 'package:flutter/material.dart';
import '../models/word_list.dart';
import '../models/app_settings.dart';
import '../services/audio_player_service.dart';
import '../services/speech_recognizer_interface.dart';
import '../services/preferences_service.dart';
import '../widgets/fireworks_overlay.dart';

enum GameState {
  initial,      // Before game starts
  playing,      // During active gameplay
  celebrating,  // After correct word
  failing,      // After incorrect word
  completed,    // Game finished
}

/// Main game controller managing game state and logic
class GameController extends ChangeNotifier {
  final AudioPlayerService audioService;
  final ISpeechRecognizer speechRecognizer;
  final FireworksController fireworksController = FireworksController();
  final PreferencesService preferencesService = PreferencesService();

  // Game state
  GameState _state = GameState.initial;
  int _currentWeek = 1; // Current week number (1-31)
  int _currentWordIndex = -1;
  List<int> _shuffledIndices = [];
  bool _isMicrophoneEnabled = false;
  double _microphoneRMS = 0.0;
  AppSettings? _settings;
  
  // Initialization tracking
  final Completer<void> _initializationCompleter = Completer<void>();
  bool _isInitializing = false;

  GameController({
    required this.audioService,
    required this.speechRecognizer,
  }) {
    // Initialize with default settings, then load from preferences
    _settings = const AppSettings();
    _currentWeek = 1;
    _loadSettings(); // Fire and forget - will update when loaded
    
    // Pre-initialize speech recognizer in the background
    // This prevents the 16-second delay when user clicks "Start Game"
    _preInitializeSpeechRecognizer();
  }

  /// Future that completes when app initialization is done
  Future<void> get initializationComplete => _initializationCompleter.future;

  /// Pre-initialize speech recognizer in the background
  /// This starts loading the model as soon as the app starts,
  /// so it's ready when the user clicks "Start Game"
  void _preInitializeSpeechRecognizer() {
    if (_isInitializing) return;
    _isInitializing = true;
    
    // Start initialization after a short delay to not block app startup
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        print('🚀 Pre-initializing speech recognizer in background...');
        final hasPermission = await speechRecognizer.requestPermission();
        if (hasPermission) {
          await speechRecognizer.initialize();
          print('✅ Speech recognizer pre-initialized successfully');
        } else {
          print('⚠️ Microphone permission not granted, will request on Start Game');
        }
        
        // Mark initialization as complete
        if (!_initializationCompleter.isCompleted) {
          _initializationCompleter.complete();
        }
      } catch (e) {
        print('⚠️ Pre-initialization failed (will retry on Start Game): $e');
        // Still mark as complete - we'll retry when user clicks Start Game
        if (!_initializationCompleter.isCompleted) {
          _initializationCompleter.complete();
        }
      }
    });
  }

  /// Load settings from preferences
  Future<void> _loadSettings() async {
    try {
      _settings = await preferencesService.loadSettings();
      _currentWeek = _settings!.currentWeek;
      notifyListeners();
    } catch (e) {
      print('Error loading settings: $e');
      // Keep default settings if loading fails
    }
  }

  // Getters
  GameState get state => _state;
  int get currentWeek => _currentWeek;
  AppSettings? get settings => _settings;
  
  // Legacy getter for backwards compatibility
  @Deprecated('Use currentWeek instead')
  int get numWeeks => _currentWeek;
  
  int get currentWordIndex => _currentWordIndex;
  String get currentWord {
    if (_currentWordIndex >= 0 && _currentWordIndex < _shuffledIndices.length) {
      return WordList.getWord(_shuffledIndices[_currentWordIndex]);
    }
    return '';
  }
  bool get isGameComplete {
    // Game is complete when we've shown all unique words
    if (_shuffledIndices.isEmpty) return false;
    return _currentWordIndex >= (_shuffledIndices.length - 1);
  }
  bool get isMicrophoneEnabled => _isMicrophoneEnabled;
  double get microphoneRMS => _microphoneRMS;
  Color? get celebrationColor => fireworksController.lastFireworkColor;
  int get totalWords {
    // Return the actual number of unique words (may be less than currentWeek * wordsPerWeek if there are duplicates)
    if (_shuffledIndices.isNotEmpty) {
      return _shuffledIndices.length;
    }
    // Fallback: calculate unique words for the current week
    final int wordCount = _currentWeek * WordList.wordsPerWeek;
    final Set<String> uniqueWords = {};
    for (int i = 0; i < wordCount && i < WordList.allWords.length; i++) {
      uniqueWords.add(WordList.allWords[i]);
    }
    return uniqueWords.length;
  }
  int get wordsRemaining {
    if (_shuffledIndices.isEmpty) return 0;
    return _shuffledIndices.length - _currentWordIndex - 1;
  }

  /// Set the current week number
  Future<void> setCurrentWeek(int week) async {
    if (week >= 1 && week <= WordList.maxWeeks) {
      _currentWeek = week;
      await preferencesService.updateCurrentWeek(week);
      notifyListeners();
    }
  }

  /// Update settings
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    _currentWeek = newSettings.currentWeek;
    await preferencesService.saveSettings(newSettings);
    notifyListeners();
  }

  /// Refresh settings from preferences (useful after settings page changes)
  Future<void> refreshSettings() async {
    await _loadSettings();
  }

  /// Legacy method for backwards compatibility
  @Deprecated('Use setCurrentWeek instead')
  void setNumWeeks(int weeks) {
    setCurrentWeek(weeks);
  }

  /// Initialize the speech recognizer
  Future<bool> initializeSpeechRecognizer() async {
    try {
      final hasPermission = await speechRecognizer.requestPermission();
      if (!hasPermission) {
        print('Microphone permission denied');
        return false;
      }

      final initialized = await speechRecognizer.initialize();
      if (!initialized) {
        print('Failed to initialize speech recognizer');
        return false;
      }

      return true;
    } catch (e) {
      print('Error initializing speech recognizer: $e');
      return false;
    }
  }

  /// Start a new game round
  Future<void> beginRound() async {
    // Refresh settings in case they changed
    await _loadSettings();
    
    _state = GameState.initial;
    _currentWordIndex = -1;
    _shuffledIndices = WordList.generateShuffledIndicesForWeek(_currentWeek);
    
    print('🎮 Starting game for week $_currentWeek');
    print('🎮 Shuffled indices: $_shuffledIndices');

    // Immediately transition to playing state and show first word for responsive UI
    _displayNextWord();
    
    // Play game start sound in the background (non-blocking)
    // This makes the UI feel responsive while audio plays
    audioService.playGameStart(onComplete: () async {
      print('🎵 Game start audio complete');
      // Microphone is already enabled, audio just finished
    });
    
    // Enable microphone immediately (don't wait for audio)
    await _enableMicrophone();
  }

  /// Display the next word in the sequence
  void _displayNextWord() {
    // Check against actual shuffled indices length (which may be less due to duplicates)
    if (_currentWordIndex < _shuffledIndices.length - 1) {
      _currentWordIndex++;
      _state = GameState.playing;
      print('📖 Displaying word $_currentWordIndex: $currentWord');
      notifyListeners();
    } else {
      _completeGame();
    }
  }

  /// Enable microphone listening
  Future<void> _enableMicrophone() async {
    print('🎤 Enabling microphone...');
    _isMicrophoneEnabled = true;
    notifyListeners();
    
    // Small delay to ensure previous session is fully stopped
    await Future.delayed(const Duration(milliseconds: 100));
    await _startListening();
  }

  /// Disable microphone listening
  Future<void> _disableMicrophone() async {
    print('🎤 Disabling microphone...');
    _isMicrophoneEnabled = false;
    notifyListeners();
    await speechRecognizer.stopListening();
  }

  /// Start listening for speech
  Future<void> _startListening() async {
    print('🎤 Starting continuous listening...');
    try {
      // Pass expected word for context-aware matching
      await speechRecognizer.startListening(
        onResult: _handleSpeechResult,
        onPartial: _handlePartialResult,
        onError: (error) {
          print('❌ Speech recognition error: $error');
        },
        expectedWord: currentWord,  // Pass expected word for better matching
      );
      print('✅ Continuous listening started (will auto-restart)');
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
    }
  }

  /// Handle partial speech recognition results
  void _handlePartialResult(PartialSpeechResult result) {
    print('Partial result: ${result.partial}');
  }

  /// Handle final speech recognition results
  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (_state != GameState.playing) {
      print('⚠️  Ignoring result, not in playing state: $_state');
      return;
    }

    // Only process non-empty results (empty ones are handled by auto-restart in speech recognizer)
    if (result.text.isEmpty) {
      print('⚠️  Empty result ignored (auto-restart will handle)');
      return;
    }

    final expectedWord = currentWord.toLowerCase();
    print('📝 Result: ${result.text}, Expected: $expectedWord');

    bool gotExpected = false;

    // Check main result
    if (WordList.phraseContainsWord(result.text, expectedWord)) {
      gotExpected = true;
    }

    // Check alternatives if not found in main result
    if (!gotExpected && result.alternatives.isNotEmpty) {
      for (final alt in result.alternatives) {
        if (alt.text.isNotEmpty && alt.confidence < 0.8) {
          if (WordList.phraseContainsWord(alt.text, expectedWord)) {
            gotExpected = true;
            break;
          }
        }
      }
    }

    // Handle result
    if (gotExpected) {
      print('✅ Correct word!');
      _playCelebration();
    } else {
      print('❌ Wrong word');
      _playFailure();
    }
    // Speech recognizer will auto-restart listening after this
  }

  /// Play celebration for correct word
  void _playCelebration() async {
    await _disableMicrophone();
    _state = GameState.celebrating;
    notifyListeners();

    // Launch a single firework above the word
    // The screen size and word position will be set by the game screen via updateScreenSize
    fireworksController.launchSingle(null);

    audioService.playWordSuccess(onComplete: () async {
      print('🎵 Success audio complete, moving to next word...');
      _displayNextWord();
      await _enableMicrophone();
    });
  }

  /// Play failure for incorrect word
  void _playFailure() async {
    // Disable microphone first (quick operation)
    await _disableMicrophone();
    
    // Immediately trigger animation and audio together
    _state = GameState.failing;
    notifyListeners();
    
    // Start audio playback right after (minimal delay from state change)
    audioService.playWordMiss(onComplete: () async {
      print('🎵 Miss audio complete, continuing...');
      _state = GameState.playing;
      notifyListeners();
      // Re-enable microphone after audio completes
      await _enableMicrophone();
    });
  }

  /// Complete the game
  void _completeGame() async {
    await _disableMicrophone();
    _state = GameState.completed;
    notifyListeners();

    // Launch multiple fireworks for finale
    fireworksController.launchMultiple(null, count: 7);

    audioService.playGameComplete();
    print('🎉 Game completed!');
  }

  /// Play word pronunciation hint
  Future<void> playWordHint() async {
    if (currentWord.isNotEmpty && _state == GameState.playing) {
      print('💡 Playing hint for: $currentWord');
      await _disableMicrophone();
      await audioService.playWordPronunciation(
        currentWord,
        onComplete: () async {
          print('💡 Hint complete, re-enabling microphone');
          await _enableMicrophone();
        },
      );
    }
  }

  /// Reset game to initial state
  void resetGame() async {
    await _disableMicrophone();
    _state = GameState.initial;
    _currentWordIndex = -1;
    _shuffledIndices = [];
    notifyListeners();
    print('🔄 Game reset');
  }

  @override
  void dispose() {
    _disableMicrophone();
    audioService.dispose();
    speechRecognizer.dispose();
    fireworksController.dispose();
    super.dispose();
  }
}

