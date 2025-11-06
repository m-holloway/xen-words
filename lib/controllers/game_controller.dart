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

  GameController({
    required this.audioService,
    required this.speechRecognizer,
  }) {
    // Initialize with default settings, then load from preferences
    _settings = const AppSettings();
    _currentWeek = 1;
    _loadSettings(); // Fire and forget - will update when loaded
    
    // DON'T pre-initialize speech recognizer here - wait for 3D model to load first
    // This prevents blocking the 3D model loading on the splash screen
    // Speech recognition will be initialized in onSplashModelLoaded() callback
    
    // Listen to fireworks controller so UI rebuilds when fireworks finish
    // This allows us to show/hide bunny and "Play Again" button based on fireworks state
    fireworksController.addListener(() {
      notifyListeners();
    });
  }

  /// Future that completes when app initialization is done
  Future<void> get initializationComplete => _initializationCompleter.future;

  // REMOVED: _preInitializeSpeechRecognizer()
  // Speech recognition now initializes when user clicks "Start Game" in game_screen.dart
  // This prevents blocking the main thread during splash screen
  
  /// Called when 3D model is fully loaded on splash screen
  /// Completes initialization immediately - speech recognition will initialize when user starts game
  /// This keeps the splash screen responsive
  void onSplashModelLoaded() {
    print('🎉 3D model loaded on splash screen - completing initialization');
    
    // Complete initialization future immediately - splash screen can transition
    // Speech recognition will initialize when user clicks "Start Game" (handled in game_screen.dart)
    // This prevents blocking the main thread during splash screen
    if (!_initializationCompleter.isCompleted) {
      _initializationCompleter.complete();
      print('✅ Splash screen can transition - speech recognition will initialize on Start Game');
    }
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

    // Transition UI immediately to playing state (but word not shown yet)
    // This makes the start screen disappear immediately
    _state = GameState.playing;
    notifyListeners();
    
    // Play game start sound and WAIT for it to complete
    // This prevents the user from speaking over the audio
    final audioComplete = Completer<void>();
    await audioService.playGameStart(onComplete: () {
      print('🎵 Game start audio complete');
      audioComplete.complete();
    });
    await audioComplete.future;
    
    // NOW display the first word and enable microphone
    // _displayNextWord() will increment from -1 to 0 and set up the word
    _displayNextWord();
    
    // Enable microphone with the correct expected word (now that word is set up)
    await _enableMicrophone();
    
    // Give microphone a moment to start processing audio
    await Future.delayed(const Duration(milliseconds: 200));
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

  /// Pause microphone when app goes to background
  /// This is different from _disableMicrophone - it's temporary and can be resumed
  Future<void> pauseMicrophone() async {
    if (_isMicrophoneEnabled) {
      print('⏸️ Pausing microphone (app backgrounded)');
      await _disableMicrophone();
    }
  }

  /// Resume microphone when app comes back to foreground
  Future<void> resumeMicrophone() async {
    // Only resume if we're in a playing state
    if (_state == GameState.playing ||
        _state == GameState.celebrating ||
        _state == GameState.failing) {
      if (!_isMicrophoneEnabled) {
        print('▶️ Resuming microphone (app resumed)');
        await _enableMicrophone();
      }
    }
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

