import 'package:audioplayers/audioplayers.dart';
import '../utils/app_logger.dart';

/// Service for managing audio playback in the app
class AudioPlayerService {
  final AudioPlayer _soundEffectsPlayer = AudioPlayer();
  final AudioPlayer _wordPlayer = AudioPlayer();

  // Sound effect paths
  static const String gameStartSound = 'audio/sound/game-start-clean-final-1.wav';
  static const String wordSuccessSound = 'audio/sound/serum-success8.wav';
  static const String wordMissSound = 'audio/sound/miss-word_mixdown5.wav';
  static const String gameCompleteSound = 'audio/sound/fireworks-finale_mixdown.wav';

  /// Play a sound effect and optionally wait for completion
  Future<void> playSoundEffect(String assetPath, {Function? onComplete}) async {
    try {
      await _soundEffectsPlayer.stop();
      await _soundEffectsPlayer.play(AssetSource(assetPath));
      
      if (onComplete != null) {
        _soundEffectsPlayer.onPlayerComplete.first.then((_) {
          onComplete();
        });
      }
    } catch (e) {
      AppLogger.audio.e('Error playing sound effect: $e', error: e);
      onComplete?.call();
    }
  }

  /// Play game start sound
  Future<void> playGameStart({Function? onComplete}) async {
    await playSoundEffect(gameStartSound, onComplete: onComplete);
  }

  /// Play word success sound
  Future<void> playWordSuccess({Function? onComplete}) async {
    await playSoundEffect(wordSuccessSound, onComplete: onComplete);
  }

  /// Play word miss sound
  Future<void> playWordMiss({Function? onComplete}) async {
    await playSoundEffect(wordMissSound, onComplete: onComplete);
  }

  /// Play game complete sound
  Future<void> playGameComplete({Function? onComplete}) async {
    await playSoundEffect(gameCompleteSound, onComplete: onComplete);
  }

  /// Play a word pronunciation
  Future<void> playWordPronunciation(String word, {Function? onComplete}) async {
    try {
      final wordPath = 'audio/words/${word.toLowerCase()}.mp3';
      await _wordPlayer.stop();
      await _wordPlayer.play(AssetSource(wordPath));
      
      if (onComplete != null) {
        _wordPlayer.onPlayerComplete.first.then((_) {
          onComplete();
        });
      }
    } catch (e) {
      AppLogger.audio.e('Error playing word pronunciation for "$word": $e', error: e);
      onComplete?.call();
    }
  }

  /// Stop all audio playback
  Future<void> stopAll() async {
    await _soundEffectsPlayer.stop();
    await _wordPlayer.stop();
  }

  /// Dispose of audio players
  void dispose() {
    _soundEffectsPlayer.dispose();
    _wordPlayer.dispose();
  }

  /// Check if a sound effect is currently playing
  bool get isSoundEffectPlaying {
    return _soundEffectsPlayer.state == PlayerState.playing;
  }

  /// Check if a word pronunciation is currently playing
  bool get isWordPlaying {
    return _wordPlayer.state == PlayerState.playing;
  }

  /// Check if any audio is playing
  bool get isAnyAudioPlaying {
    return isSoundEffectPlaying || isWordPlaying;
  }
}


