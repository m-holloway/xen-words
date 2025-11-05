import 'package:flutter/material.dart';
import '../models/word_list.dart';
import '../services/audio_player_service.dart';
import '../services/speech_recognizer_interface.dart';
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

  // Game state
  GameState _state = GameState.initial;
  int _numWeeks = 7;
  int _currentWordIndex = -1;
  List<int> _shuffledIndices = [];
  bool _isMicrophoneEnabled = false;
  double _microphoneRMS = 0.0;

  GameController({
    required this.audioService,
    required this.speechRecognizer,
  });

  // Getters
  GameState get state => _state;
  int get numWeeks => _numWeeks;
  int get currentWordIndex => _currentWordIndex;
  String get currentWord {
    if (_currentWordIndex >= 0 && _currentWordIndex < _shuffledIndices.length) {
      return WordList.getWord(_shuffledIndices[_currentWordIndex]);
    }
    return '';
  }
  bool get isGameComplete => _currentWordIndex >= (_numWeeks * WordList.wordsPerWeek - 1);
  bool get isMicrophoneEnabled => _isMicrophoneEnabled;
  double get microphoneRMS => _microphoneRMS;
  int get totalWords => _numWeeks * WordList.wordsPerWeek;
  int get wordsRemaining => totalWords - _currentWordIndex - 1;

  /// Set the number of weeks for the game
  void setNumWeeks(int weeks) {
    if (weeks >= 1 && weeks <= WordList.maxWeeks) {
      _numWeeks = weeks;
      notifyListeners();
    }
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
    _state = GameState.initial;
    _currentWordIndex = -1;
    _shuffledIndices = WordList.generateShuffledIndices(_numWeeks);
    
    print('Shuffled indices: $_shuffledIndices');

    notifyListeners();

    // Play game start sound and then enable microphone
    await audioService.playGameStart(onComplete: () {
      _enableMicrophone();
      _displayNextWord();
    });
  }

  /// Display the next word in the sequence
  void _displayNextWord() {
    if (_currentWordIndex < _numWeeks * WordList.wordsPerWeek - 1) {
      _currentWordIndex++;
      _state = GameState.playing;
      print('Displaying word $_currentWordIndex: $currentWord');
      notifyListeners();
    } else {
      _completeGame();
    }
  }

  /// Enable microphone listening
  void _enableMicrophone() {
    if (!_isMicrophoneEnabled) {
      _isMicrophoneEnabled = true;
      _startListening();
      notifyListeners();
    }
  }

  /// Disable microphone listening
  void _disableMicrophone() {
    if (_isMicrophoneEnabled) {
      _isMicrophoneEnabled = false;
      speechRecognizer.stopListening();
      notifyListeners();
    }
  }

  /// Start listening for speech
  void _startListening() {
    speechRecognizer.startListening(
      onResult: _handleSpeechResult,
      onPartial: _handlePartialResult,
      onError: (error) {
        print('Speech recognition error: $error');
      },
    );
  }

  /// Handle partial speech recognition results
  void _handlePartialResult(PartialSpeechResult result) {
    print('Partial result: ${result.partial}');
  }

  /// Handle final speech recognition results
  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (_state != GameState.playing) return;

    final expectedWord = currentWord.toLowerCase();
    print('Result: ${result.text}, Expected: $expectedWord');

    bool gotExpected = false;
    bool gotNonEmpty = false;

    // Check main result
    if (result.text.isNotEmpty) {
      gotNonEmpty = true;
      if (WordList.phraseContainsWord(result.text, expectedWord)) {
        gotExpected = true;
      }
    }

    // Check alternatives if not found in main result
    if (!gotExpected && result.alternatives.isNotEmpty) {
      for (final alt in result.alternatives) {
        if (alt.text.isNotEmpty && alt.confidence < 0.8) {
          gotNonEmpty = true;
          if (WordList.phraseContainsWord(alt.text, expectedWord)) {
            gotExpected = true;
            break;
          }
        }
      }
    }

    // Handle result
    if (gotNonEmpty) {
      if (gotExpected) {
        _playCelebration();
      } else {
        _playFailure();
      }
    }

    // Restart listening after processing
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_state == GameState.playing && _isMicrophoneEnabled) {
        _startListening();
      }
    });
  }

  /// Play celebration for correct word
  void _playCelebration() {
    _disableMicrophone();
    _state = GameState.celebrating;
    notifyListeners();

    // Launch a single firework
    // Note: Size will be provided by the UI when calling this
    // For now, using a default size
    fireworksController.launchSingle(const Size(800, 600));

    audioService.playWordSuccess(onComplete: () {
      _enableMicrophone();
      _displayNextWord();
    });
  }

  /// Play failure for incorrect word
  void _playFailure() {
    _disableMicrophone();
    _state = GameState.failing;
    notifyListeners();

    audioService.playWordMiss(onComplete: () {
      _enableMicrophone();
      _state = GameState.playing;
      notifyListeners();
    });
  }

  /// Complete the game
  void _completeGame() {
    _disableMicrophone();
    _state = GameState.completed;
    notifyListeners();

    // Launch multiple fireworks for finale
    fireworksController.launchMultiple(const Size(800, 600), count: 5);

    audioService.playGameComplete();
  }

  /// Play word pronunciation hint
  Future<void> playWordHint() async {
    if (currentWord.isNotEmpty && _state == GameState.playing) {
      _disableMicrophone();
      await audioService.playWordPronunciation(
        currentWord,
        onComplete: () {
          _enableMicrophone();
        },
      );
    }
  }

  /// Reset game to initial state
  void resetGame() {
    _disableMicrophone();
    _state = GameState.initial;
    _currentWordIndex = -1;
    _shuffledIndices = [];
    notifyListeners();
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

