import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../controllers/game_controller.dart';
import '../models/child_profile.dart';
import '../services/director_tuner.dart';
import '../services/profile_service.dart';
import '../utils/app_logger.dart';
import 'word_display.dart';
import 'week_selector.dart';
import 'settings_page.dart';
import 'character_view.dart';
import 'fireworks_overlay.dart';
import 'progress_bar.dart';
import 'director_overlay.dart';
import 'parental_gate.dart';

/// Intent for toggling director overlay
class _ToggleDirectorIntent extends Intent {
  const _ToggleDirectorIntent();
}

/// Main game screen widget
class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool _isInitializing = false;
  bool _isStartingGame = false; // Track if game is starting to prevent multiple clicks
  AppLifecycleState? _previousLifecycleState; // Track previous state to avoid pausing on initial launch
  bool _gameHasStarted = false; // Track if game has actually started (prevents lifecycle interference during startup)
  final ProfileService _profileService = ProfileService();
  List<ChildProfile> _profiles = [];
  bool _profilesLoading = true;
  String? _activeProfileId;
  bool _isSwitchingProfile = false;
  
  // Director overlay state
  void _onDirectorValueChanged() {
    setState(() {
      // Trigger rebuild to reflect tuner changes
    });
  }
  
  @override
  void initState() {
    super.initState();
    // Don't initialize on startup - wait until user starts game
    // This keeps UI responsive
    
    // Listen to app lifecycle changes to pause/resume microphone
    WidgetsBinding.instance.addObserver(this);
    _previousLifecycleState = WidgetsBinding.instance.lifecycleState;
    _loadProfiles();
  }
  ChildProfile get _currentProfile {
    if (_activeProfileId == null || _activeProfileId == 'guest') {
      return ChildProfile.guest();
    }
    return _profiles.firstWhere(
      (profile) => profile.id == _activeProfileId,
      orElse: () => ChildProfile.guest(),
    );
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (!mounted) return;
    
    // Don't interfere with microphone until game has actually started
    // This prevents lifecycle observer from interfering during game startup
    if (!_gameHasStarted) {
      _previousLifecycleState = state;
      return;
    }
    
    final controller = context.read<GameController>();
    
    // Only pause if we were previously in foreground (resumed)
    // This prevents pausing during initial app launch
    final wasInForeground = _previousLifecycleState == AppLifecycleState.resumed;
    _previousLifecycleState = state;
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resume microphone if game is active
        if (controller.state == GameState.playing ||
            controller.state == GameState.celebrating ||
            controller.state == GameState.failing) {
          AppLogger.system.i('📱 App resumed - resuming microphone');
          controller.resumeMicrophone();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App went to background - pause microphone (only if we were in foreground)
        if (wasInForeground && controller.isMicrophoneEnabled) {
          AppLogger.system.i('📱 App backgrounded - pausing microphone');
          controller.pauseMicrophone();
        }
        break;
    }
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

  Future<void> _loadProfiles() async {
    setState(() {
      _profilesLoading = true;
    });
    try {
      final profiles = await _profileService.loadProfiles();
      final activeId = await _profileService.getActiveProfileId();
      final isGuest = await _profileService.isGuestMode();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _activeProfileId = isGuest
            ? 'guest'
            : activeId ??
                (profiles.isNotEmpty ? profiles.first.id : 'guest');
        _profilesLoading = false;
      });
    } catch (e) {
      AppLogger.ui.e('Failed to load profiles', error: e);
      if (!mounted) return;
      setState(() {
        _profiles = [];
        _profilesLoading = false;
        _activeProfileId = 'guest';
      });
    }
  }

  Future<void> _handleProfileTap(
    ChildProfile profile,
    GameController controller,
  ) async {
    if (_isSwitchingProfile || _activeProfileId == profile.id) return;
    setState(() => _isSwitchingProfile = true);
    try {
      if (profile.isGuest) {
        await _profileService.setGuestMode();
      } else {
        await _profileService.setActiveProfile(profile.id);
      }
      await controller.refreshSettings();
      if (mounted) {
        await _loadProfiles();
      }
    } catch (e) {
      AppLogger.ui.e('Failed to switch profile', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t switch profiles. Try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingProfile = false);
      }
    }
  }

  void _openParentDashboard(BuildContext context, GameController controller) async {
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
      await _loadProfiles();
    }
  }

  void _exitGame(BuildContext context, GameController controller) {
    // Stop the game and return to initial screen
    controller.resetGame();
    
    // Reset game started flag
    setState(() {
      _gameHasStarted = false;
      _isStartingGame = false;
    });
    
    AppLogger.game.i('🔙 Exited game, returning to menu');
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
              return Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.keyD): _ToggleDirectorIntent(),
                },
                child: Actions(
                  actions: {
                    _ToggleDirectorIntent: CallbackAction<_ToggleDirectorIntent>(
                      onInvoke: (_) {
                        AppLogger.ui.d('🎹 Director shortcut triggered');
                        DirectorTuner.instance.toggleOverlay();
                        return null;
                      },
                    ),
                  },
                  child: FocusScope(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                  // Full-screen character background (always visible except initial state)
                  if (controller.state != GameState.initial)
                    Positioned.fill(
                      child: CharacterView(gameState: controller.state),
                    ),
                  
                  // Main content overlays (word display, etc) - constrained to screen bounds
                  Positioned.fill(
                    child: _buildMainContent(controller),
                  ),
                  
                  // Parent dashboard button (protected by parental gate)
                  if (controller.state == GameState.initial)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: ParentalGatedIconButton(
                        icon: Icons.family_restroom,
                        tooltip: 'Parent Dashboard (Adult Only)',
                        gateTitle: 'Parent Dashboard - Adult Verification',
                        gateMessage: 'This prevents children from opening the parent dashboard. Please solve:',
                        onPassed: () => _openParentDashboard(context, controller),
                      ),
                    ),
                  
                  // Back button (shown during gameplay, not on initial screen)
                  if (controller.state != GameState.initial)
                    Positioned(
                      top: 20,
                      left: 20,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, size: 32),
                        color: Colors.white,
                        onPressed: () => _exitGame(context, controller),
                        tooltip: 'Back to Menu',
                      ),
                    ),
                  
                  // Fireworks overlay (always on top)
                  Positioned.fill(
                    child: FireworksOverlay(
                      controller: controller.fireworksController,
                    ),
                  ),
                  
                  // Director tuning overlay (always on top, keyboard controlled)
                  Positioned.fill(
                    child: DirectorOverlay(
                      onValueChanged: _onDirectorValueChanged,
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
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
        if (_isInitializing) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 20),
                Text(
                  'Initializing speech recognition...',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          );
        }
        if (controller.settings == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return _buildInitialMenu(controller);

      case GameState.playing:
      case GameState.celebrating:
      case GameState.failing:
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
            // Word is at top of screen now, so fireworks should originate from there
            // Approximate position: center horizontally, near top (accounting for word display height)
            final wordPosition = Offset(screenSize.width / 2, 120); // Top area where word display is
            
            // Update fireworks controller with actual screen size
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.fireworksController.updateScreenSize(screenSize, wordPosition);
            });
            
            // Layout with word board at top, progress bar at bottom, character fully visible in middle
            // Use SizedBox to constrain to available height and prevent overflow
            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Word display at top with enhanced visibility
                  WordDisplay(
                    word: controller.currentWord,
                    gameState: controller.state,
                    onTap: controller.playWordHint,
                    celebrationColor: controller.celebrationColor,
                  ),
                  // Spacer to push progress bar to bottom
                  const Spacer(),
                  // Progress bar at bottom (not taking prominent attention space)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: WordProgressBar(
                      currentWordIndex: controller.currentWordIndex,
                      totalWords: controller.totalWords,
                    ),
                  ),
                ],
              ),
            );
          },
        );

      case GameState.completed:
        // Hide celebration emoji and "Play Again" button during fireworks
        final showPlayAgain = controller.fireworksController.isDone;
        return LayoutBuilder(
          builder: (context, constraints) {
            // Responsive emoji size based on screen width
            final emojiFontSize = (constraints.maxWidth * 0.3).clamp(100.0, 150.0);
            
            return Column(
              children: [
                const SizedBox(height: 20),
                // Celebration emoji at top (only show after fireworks complete)
                // Bigger and translucent
                if (showPlayAgain)
                  Opacity(
                    opacity: 0.6, // Translucent
                    child: Text(
                      '🎉',
                      style: TextStyle(fontSize: emojiFontSize),
                    ),
                  ),
            // Play Again button below emoji (when fireworks are done)
            if (showPlayAgain) ...[
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Responsive sizing based on screen width
                  final screenWidth = constraints.maxWidth;
                  final buttonFontSize = (screenWidth * 0.085).clamp(24.0, 32.0);
                  final buttonHorizontalPadding = (screenWidth * 0.12).clamp(32.0, 64.0);
                  final buttonVerticalPadding = (screenWidth * 0.04).clamp(16.0, 24.0);
                  final containerHorizontalPadding = (screenWidth * 0.08).clamp(20.0, 40.0);
                  
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: containerHorizontalPadding),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        // Glow effect like word board
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: -5,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          await WakelockPlus.disable();
                          controller.resetGame();
                          // Reset all game state flags so UI is ready for next game
                          setState(() {
                            _gameHasStarted = false;
                            _isStartingGame = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: buttonHorizontalPadding,
                            vertical: buttonVerticalPadding,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0, // Remove default elevation, using custom glow instead
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Play Again',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: buttonFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
                // Spacer to fill remaining space
                const Spacer(),
              ],
            );
          },
        );
    }
  }

  Widget _buildInitialMenu(GameController controller) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProfileSwitcher(controller),
          const SizedBox(height: 24),
          WeekSelector(
            currentWeek: controller.currentWeek,
            settings: controller.settings!,
            isStarting: _isStartingGame,
            onWeekChanged: (week) async {
              await controller.setCurrentWeek(week);
            },
            onStartGame: () async {
              if (_isStartingGame) return;
              setState(() {
                _isStartingGame = true;
              });
              try {
                final initialized = await _initializeSpeech();
                if (mounted && initialized) {
                  setState(() {
                    _gameHasStarted = true;
                  });
                  await WakelockPlus.enable();
                  await controller.beginRound();
                } else if (mounted) {
                  setState(() {
                    _isStartingGame = false;
                  });
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isStartingGame = false;
                    _gameHasStarted = false;
                  });
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSwitcher(GameController controller) {
    if (_profilesLoading) {
      return const SizedBox(
        height: 110,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final current = _currentProfile;
    final isGuest = current.isGuest;
    final Color baseColor = isGuest ? Colors.grey.shade600 : current.color;

    return GestureDetector(
      onTap: _isSwitchingProfile
          ? null
          : () => _showProfilePicker(controller, highlightGuest: isGuest),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              baseColor.withOpacity(0.9),
              baseColor.withOpacity(0.5),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: baseColor.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  current.emoji,
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isGuest ? 'Guest mode' : 'Learning as ${current.name}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profiles.isEmpty
                        ? 'Add more profiles in the Parent Dashboard'
                        : 'Tap to switch profile',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_isSwitchingProfile)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.expand_more, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showProfilePicker(
    GameController controller, {
    required bool highlightGuest,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Text(
                  'Choose who\'s learning',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    _buildProfilePickerTile(
                      profile: ChildProfile.guest(),
                      controller: controller,
                      isActive:
                          _activeProfileId == 'guest' || _activeProfileId == null,
                    ),
                    for (final profile in _profiles)
                      _buildProfilePickerTile(
                        profile: profile,
                        controller: controller,
                        isActive: _activeProfileId == profile.id,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePickerTile({
    required ChildProfile profile,
    required GameController controller,
    required bool isActive,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            profile.isGuest ? Colors.grey.shade400 : profile.color,
        child: Text(profile.emoji, style: const TextStyle(fontSize: 24)),
      ),
      title: Text(profile.isGuest ? 'Guest' : profile.name),
      subtitle: Text(profile.isGuest ? 'Quick play' : 'Tap to switch'),
      trailing: isActive
          ? const Icon(Icons.check_circle, color: Colors.green)
          : null,
      onTap: () {
        Navigator.pop(context);
        _handleProfileTap(profile, controller);
      },
    );
  }
}

