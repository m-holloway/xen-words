import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/game_controller.dart';

/// Widget for displaying and animating the character
/// 
/// FUTURE TODO: Convert rabbit_rig.fbx to glTF/GLB format for 3D rendering
/// with flutter_scene. For now, using animated emoji as placeholder.
/// 
/// Steps for 3D integration:
/// 1. Convert FBX to GLB using Blender or online converter
/// 2. Import the model using flutter_scene package
/// 3. Implement animation playback for idle, celebrate, and fail states
/// 4. Set up proper camera positioning and lighting
class CharacterView extends StatefulWidget {
  final GameState gameState;

  const CharacterView({
    Key? key,
    required this.gameState,
  }) : super(key: key);

  @override
  State<CharacterView> createState() => _CharacterViewState();
}

class _CharacterViewState extends State<CharacterView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _playIdleAnimation();
  }

  @override
  void didUpdateWidget(CharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameState != widget.gameState) {
      _playAnimationForState(widget.gameState);
    }
  }

  void _playAnimationForState(GameState state) {
    switch (state) {
      case GameState.celebrating:
        _playCelebrationAnimation();
        break;
      case GameState.failing:
        _playFailAnimation();
        break;
      case GameState.playing:
        _playIdleAnimation();
        break;
      default:
        break;
    }
  }

  void _playCelebrationAnimation() {
    _animationController.forward(from: 0);
  }

  void _playFailAnimation() {
    _animationController.forward(from: 0);
  }

  void _playIdleAnimation() {
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getCharacterEmoji() {
    switch (widget.gameState) {
      case GameState.celebrating:
        return '🎉';
      case GameState.failing:
        return '😔';
      case GameState.completed:
        return '⭐';
      default:
        return '🐰';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Center(
        child: Text(
          _getCharacterEmoji(),
          style: const TextStyle(fontSize: 100),
        )
            .animate(
              target: widget.gameState == GameState.celebrating ? 1 : 0,
            )
            .scale(
              duration: const Duration(milliseconds: 500),
              begin: const Offset(1, 1),
              end: const Offset(1.3, 1.3),
            )
            .rotate(
              duration: const Duration(milliseconds: 500),
              begin: 0,
              end: 0.1,
            )
            .animate(
              target: widget.gameState == GameState.failing ? 1 : 0,
            )
            .shake(
              duration: const Duration(milliseconds: 500),
              hz: 8,
            )
            .animate(
              target: widget.gameState == GameState.playing ? 1 : 0,
            )
            .shimmer(
              duration: const Duration(seconds: 2),
            ),
      ),
    );
  }
}

