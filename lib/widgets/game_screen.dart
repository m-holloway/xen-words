import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../controllers/game_controller.dart';
import 'word_display.dart';
import 'week_selector.dart';
import 'microphone_indicator.dart';
import 'character_view.dart';
import 'fireworks_overlay.dart';

/// Main game screen widget
class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    final controller = context.read<GameController>();
    final initialized = await controller.initializeSpeechRecognizer();
    if (!initialized && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initialize microphone. Please check permissions.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade300,
              Colors.purple.shade300,
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<GameController>(
            builder: (context, controller, child) {
              return Stack(
                children: [
                  // Main content
                  _buildMainContent(controller),
                  
                  // Character view
                  if (controller.state != GameState.initial)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: CharacterView(gameState: controller.state),
                    ),
                  
                  // Fireworks overlay
                  Positioned.fill(
                    child: FireworksOverlay(
                      controller: controller.fireworksController,
                    ),
                  ),
                  
                  // Microphone indicator
                  if (controller.state == GameState.playing ||
                      controller.state == GameState.celebrating ||
                      controller.state == GameState.failing)
                    Positioned(
                      top: 20,
                      left: 20,
                      child: MicrophoneIndicator(
                        isEnabled: controller.isMicrophoneEnabled,
                        rms: controller.microphoneRMS,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(GameController controller) {
    switch (controller.state) {
      case GameState.initial:
        return Center(
          child: WeekSelector(
            numWeeks: controller.numWeeks,
            onWeeksChanged: controller.setNumWeeks,
            onStartGame: () async {
              await WakelockPlus.enable();
              controller.beginRound();
            },
          ),
        );

      case GameState.playing:
      case GameState.celebrating:
      case GameState.failing:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WordDisplay(
                word: controller.currentWord,
                isShaking: controller.state == GameState.failing,
                onTap: controller.playWordHint,
              ),
              const SizedBox(height: 40),
              Text(
                'Word ${controller.currentWordIndex + 1} of ${controller.totalWords}',
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

      case GameState.completed:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎉',
                style: TextStyle(fontSize: 100),
              ),
              const SizedBox(height: 20),
              const Text(
                'Well Done!',
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black45,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () async {
                  await WakelockPlus.disable();
                  controller.resetGame();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 4,
                ),
                child: const Text(
                  'Play Again',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

