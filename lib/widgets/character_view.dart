import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/game_controller.dart';

/// Widget for displaying and animating the character
/// TODO: Replace with 3D model once we resolve the rendering approach
class CharacterView extends StatefulWidget {
  final GameState gameState;

  const CharacterView({
    Key? key,
    required this.gameState,
  }) : super(key: key);

  @override
  State<CharacterView> createState() => _CharacterViewState();
}

class _CharacterViewState extends State<CharacterView> {
  GameState? _lastState;

  @override
  void didUpdateWidget(CharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gameState != _lastState) {
      _lastState = widget.gameState;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: _buildCharacterForState(),
      ),
    );
  }

  Widget _buildCharacterForState() {
    switch (widget.gameState) {
      case GameState.celebrating:
        return const Text(
          '🐰',
          style: TextStyle(fontSize: 80),
        )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .scale(
              duration: 500.ms,
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.3, 1.3),
            )
            .rotate(
              duration: 500.ms,
              begin: -0.05,
              end: 0.05,
            );

      case GameState.failing:
        return const Text(
          '🐰',
          style: TextStyle(fontSize: 80),
        )
            .animate()
            .shake(
              duration: 500.ms,
              hz: 10,
            )
            .tint(
              color: Colors.red,
              duration: 500.ms,
            );

      case GameState.playing:
        return const Text(
          '🐰',
          style: TextStyle(fontSize: 80),
        )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .moveY(
              duration: 2.seconds,
              begin: 0,
              end: -10,
              curve: Curves.easeInOut,
            );

      case GameState.completed:
        return const Text(
          '🐰',
          style: TextStyle(fontSize: 80),
        )
            .animate(onPlay: (controller) => controller.repeat())
            .rotate(duration: 2.seconds);

      default:
        return const Text(
          '🐰',
          style: TextStyle(fontSize: 80),
        );
    }
  }
}
