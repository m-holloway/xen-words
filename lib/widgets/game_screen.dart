import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../controllers/game_controller.dart';
import 'word_display.dart';
import 'week_selector.dart';
import 'settings_page.dart';
import 'character_view.dart';
import 'fireworks_overlay.dart';
import 'progress_bar.dart';

/// Main game screen widget
class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _isInitializing = false;
  bool _isStartingGame = false; // Track if game is starting to prevent multiple clicks
  
  @override
  void initState() {
    super.initState();
    // Don't initialize on startup - wait until user starts game
    // This keeps UI responsive
  }

  Future<bool> _initializeSpeech() async {
    if (_isInitializing) return false;
    setState(() {
      _isInitializing = true;
    });
    
    try {
      final controller = context.read<GameController>();
      final initialized = await controller.initializeSpeechRecognizer();
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        
        if (!initialized) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize microphone. Please check permissions.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        
        return initialized;
      }
      
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
      return false;
    }
  }

  void _openSettings(BuildContext context, GameController controller) async {
    if (controller.settings == null) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          initialSettings: controller.settings!,
          onSettingsChanged: (settings) {
            // Settings are saved immediately when changed
            controller.updateSettings(settings);
          },
        ),
      ),
    );
    
    // Refresh settings after returning from settings page
    if (mounted) {
      await controller.refreshSettings();
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
              Colors.black, // Black at top
              Colors.black, // Keep black through top third
              const Color(0xFF1A0033), // Very dark purple (almost black)
              const Color(0xFF2D0047), // Dark purple
            ],
            stops: const [0.0, 0.33, 0.6, 1.0], // Black in top third, quick transition to very dark purple
          ),
        ),
        child: SafeArea(
          child: Consumer<GameController>(
            builder: (context, controller, child) {
              return Stack(
                children: [
                  // Main content
                  _buildMainContent(controller),
                  
                  // Settings button (only shown in initial state)
                  if (controller.state == GameState.initial)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: IconButton(
                        icon: const Icon(Icons.settings, size: 32),
                        color: Colors.white,
                        onPressed: () => _openSettings(context, controller),
                        tooltip: 'Settings',
                      ),
                    ),
                  
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
          child: _isInitializing
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Initializing speech recognition...',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                )
              : controller.settings != null
                  ? WeekSelector(
                      currentWeek: controller.currentWeek,
                      settings: controller.settings!,
                      isStarting: _isStartingGame,
                      onWeekChanged: (week) async {
                        await controller.setCurrentWeek(week);
                      },
                      onStartGame: () async {
                        // Prevent multiple clicks
                        if (_isStartingGame) return;
                        
                        setState(() {
                          _isStartingGame = true;
                        });
                        
                        try {
                          // Initialize speech recognition when user starts game
                          final initialized = await _initializeSpeech();
                          if (mounted && initialized) {
                            // Only start game if initialization succeeded
                            // Don't show week selector again - go straight to game
                            await WakelockPlus.enable();
                            controller.beginRound();
                          } else if (mounted) {
                            // Reset if initialization failed
                            setState(() {
                              _isStartingGame = false;
                            });
                          }
                        } catch (e) {
                          // Reset on error
                          if (mounted) {
                            setState(() {
                              _isStartingGame = false;
                            });
                          }
                        }
                      },
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
        );

      case GameState.playing:
      case GameState.celebrating:
      case GameState.failing:
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
            // Store screen size and word position for fireworks
            final wordY = constraints.maxHeight * 0.4; // Word is centered, typically at ~40% from top
            final wordX = constraints.maxWidth / 2;
            final wordPosition = Offset(wordX, wordY);
            
            // Update fireworks controller with actual screen size
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.fireworksController.updateScreenSize(screenSize, wordPosition);
            });
            
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WordDisplay(
                    word: controller.currentWord,
                    gameState: controller.state,
                    onTap: controller.playWordHint,
                    celebrationColor: controller.celebrationColor,
                  ),
                  const SizedBox(height: 50),
                  WordProgressBar(
                    currentWordIndex: controller.currentWordIndex,
                    totalWords: controller.totalWords,
                  ),
                ],
              ),
            );
          },
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

