import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import '../controllers/game_controller.dart';
import '../utils/glb_texture_replacer.dart';
import 'camera_config.dart';
import 'camera_director.dart';
import 'rug_loading_overlay.dart';

/// Widget for displaying and animating the 3D character using Thermion
/// Now supports dynamic sizing based on game state for more engaging presentation
class CharacterView extends StatefulWidget {
  final GameState gameState;

  const CharacterView({
    Key? key,
    required this.gameState,
  }) : super(key: key);

  @override
  State<CharacterView> createState() => _CharacterViewState();
}

class _CharacterViewState extends State<CharacterView> with TickerProviderStateMixin {
  ThermionViewer? _viewer;
  ThermionAsset? _asset;
  String? _currentAnimation;
  Camera? _camera;
  Vector3? _characterWorldPosition; // Track character's actual world position
  
  // Camera animation controllers
  late AnimationController _cameraAnimationController;
  late AnimationController _cameraSwayController; // For subtle idle sway
  Vector3? _targetCameraPosition;
  Vector3? _currentCameraPosition;
  bool _hasPerformedInitialZoom = false; // Track if we've done the cinematic start
  Vector3? _animationStart;
  Vector3? _animationEnd;
  
  // Random phase offsets for organic variation (set once, then drifts slowly)
  double _randomPhaseX = 0.0;
  double _randomPhaseY = 0.0;
  double _randomPhaseDrift = 0.0;
  
  // Idle animation cycling
  List<String> _idleAnimations = []; // Available idle animations
  int _currentIdleIndex = 0; // Current idle animation index
  Timer? _idleAnimationTimer; // Timer for cycling idle animations
  static const Duration _idleAnimationDuration = Duration(seconds: 8); // How long each idle plays
  
  // Failure animation selection
  List<String> _failureAnimations = []; // Available failure animations
  String? _selectedFailureAnimation; // Cached failure animation for current failing state
  
  // Celebration animation selection
  List<String> _celebrationAnimations = []; // Available celebration animations
  String? _selectedCelebrationAnimation; // Cached celebration animation for current celebrating state
  
  // Completion/dance animation selection
  List<String> _completionAnimations = []; // Available completion/dance animations
  String? _selectedCompletionAnimation; // Cached completion animation for current completed state
  
  final math.Random _random = math.Random(); // Random number generator for animations
  GameState? _previousGameState; // Track previous state to detect transitions

  @override
  void initState() {
    super.initState();
    _currentAnimation = _getAnimationForState();
    
    // Initialize character position (default, will be updated when asset loads)
    _characterWorldPosition = CameraConfig.characterPosition;
    
    // Initialize camera animation controller
    _cameraAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200), // Longer for cinematic feel
      vsync: this,
    );
    
    // Initialize camera sway controller (for subtle idle movement)
    // Use primary breathing frequency for controller speed
    final swayDurationMs = (1000 / CameraDirector.primaryBreathing.frequency).round();
    _cameraSwayController = AnimationController(
      duration: Duration(milliseconds: swayDurationMs),
      vsync: this,
    )..repeat(); // Continuously loop
    _cameraSwayController.addListener(_updateCameraSway);
    
    // Start with a wide shot (will zoom in when game starts)
    _currentCameraPosition = _getRelativeCameraPosition(CameraConfig.wideShot);
    _targetCameraPosition = _currentCameraPosition;
    
    // Initialize random phase offsets for organic movement
    _randomPhaseX = _random.nextDouble() * 2 * math.pi;
    _randomPhaseY = _random.nextDouble() * 2 * math.pi;
    _randomPhaseDrift = _random.nextDouble() * 2 * math.pi;
  }
  
  @override
  void dispose() {
    _cameraAnimationController.dispose();
    _cameraSwayController.dispose();
    _idleAnimationTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gameState != oldWidget.gameState) {
      // Track state transitions for animation selection
      final wasFailing = oldWidget.gameState == GameState.failing;
      final isNowFailing = widget.gameState == GameState.failing;
      final wasCelebrating = oldWidget.gameState == GameState.celebrating;
      final isNowCelebrating = widget.gameState == GameState.celebrating;
      
      // When entering failing state, clear cached selection to force new random pick
      if (isNowFailing && !wasFailing) {
        _selectedFailureAnimation = null;
        _currentAnimation = null;
      }
      // When leaving failing state, clear the cache
      else if (wasFailing && !isNowFailing) {
        _selectedFailureAnimation = null;
      }
      
      // When entering celebrating state, clear cached selection to force new random pick
      if (isNowCelebrating && !wasCelebrating) {
        _selectedCelebrationAnimation = null;
        _currentAnimation = null;
      }
      // When leaving celebrating state, clear the cache
      else if (wasCelebrating && !isNowCelebrating) {
        _selectedCelebrationAnimation = null;
      }
      
      // Track completion state transitions
      final wasCompleted = oldWidget.gameState == GameState.completed;
      final isNowCompleted = widget.gameState == GameState.completed;
      
      // When entering completed state, clear cached selection to force new random pick
      if (isNowCompleted && !wasCompleted) {
        _selectedCompletionAnimation = null;
        _currentAnimation = null;
      }
      // When leaving completed state, clear the cache
      else if (wasCompleted && !isNowCompleted) {
        _selectedCompletionAnimation = null;
      }
      
      // Update previous state for next comparison
      _previousGameState = oldWidget.gameState;
      
      _updateAnimation();
      
      // Manage idle animation cycling based on state
      if (widget.gameState == GameState.playing && oldWidget.gameState != GameState.playing) {
        // Entering playing state - start cycling idle animations
        _startIdleAnimationCycling();
      } else if (widget.gameState != GameState.playing && oldWidget.gameState == GameState.playing) {
        // Leaving playing state - stop cycling
        _stopIdleAnimationCycling();
      }
      
      // Special handling for initial -> playing transition (cinematic zoom-in)
      if (oldWidget.gameState == GameState.initial && 
          widget.gameState == GameState.playing && 
          !_hasPerformedInitialZoom) {
        _performCinematicZoomIn();
      } else {
        _updateCameraForState();
      }
    }
  }
  
  /// Perform a cinematic zoom-in when the game starts
  Future<void> _performCinematicZoomIn() async {
    if (_camera == null || _currentCameraPosition == null || _characterWorldPosition == null) return;
    
    _hasPerformedInitialZoom = true;
    
    // Start from wide shot, zoom to natural gameplay shot (relative to character)
    final startPosition = _getRelativeCameraPosition(CameraConfig.wideShot);
    final endPosition = _getRelativeCameraPosition(CameraConfig.playingShot);
    
    // Set starting position if not already there, looking at character's center
    if (_currentCameraPosition != startPosition) {
      final characterCenter = CameraDirector.getCharacterCenter(_characterWorldPosition!);
      await _camera!.lookAt(startPosition, focus: characterCenter);
      _currentCameraPosition = startPosition;
    }
    
    // Animate with a nice ease-in-out curve (use cinematic zoom speed)
    _cameraAnimationController.duration = CameraDirector.cinematicZoomSpeed;
    _cameraAnimationController.reset();
    
    // Store animation parameters
    _animationStart = startPosition;
    _animationEnd = endPosition;
    _targetCameraPosition = endPosition;
    
    // Remove old listeners to avoid duplicates
    _cameraAnimationController.removeListener(_updateCameraPosition);
    _cameraAnimationController.removeStatusListener(_cameraAnimationStatusListener);
    
    // Add new listener for this animation
    _cameraAnimationController.addListener(_updateCameraPosition);
    _cameraAnimationController.addStatusListener(_cameraAnimationStatusListener);
    
    _cameraAnimationController.forward();
  }
  
  /// Camera animation listener callback (called during animation)
  void _updateCameraPosition() {
    if (_camera == null || _animationStart == null || _animationEnd == null || _characterWorldPosition == null) return;
    
    final start = _animationStart!;
    final end = _animationEnd!;
    final t = _cameraAnimationController.value;
    
    // Use easeInOutSine for gentler, smoother transitions
    final easedT = -(math.cos(math.pi * t) - 1) / 2;
    
    final current = Vector3(
      start.x + (end.x - start.x) * easedT,
      start.y + (end.y - start.y) * easedT,
      start.z + (end.z - start.z) * easedT,
    );
    
    _currentCameraPosition = current;
    
    // Position camera and look at character's current center
    // For celebration, look higher to track jumping animations
    final verticalOffset = widget.gameState == GameState.celebrating 
        ? CameraDirector.celebrationLookAtOffset 
        : 0.0;
    final characterCenter = CameraDirector.getCharacterCenter(_characterWorldPosition!, verticalOffset: verticalOffset);
    _camera!.lookAt(current, focus: characterCenter);
  }
  
  /// Camera animation status listener
  void _cameraAnimationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed && _targetCameraPosition != null) {
      _currentCameraPosition = _targetCameraPosition;
    }
  }
  
  /// Apply enhanced organic camera movement with multi-frequency layering
  /// Creates a living, breathing feel instead of mechanical sine waves
  /// All parameters controlled via CameraDirector
  void _updateCameraSway() {
    if (_camera == null || _currentCameraPosition == null || _characterWorldPosition == null) return;
    
    // Only apply sway during playing state (not during reactions or transitions)
    if (widget.gameState != GameState.playing) return;
    
    // Don't apply sway during camera transitions
    if (_cameraAnimationController.isAnimating) return;
    
    // Get normalized time (0.0 to 1.0)
    final t = _cameraSwayController.value;
    
    // Get breathing parameters from CameraDirector
    final primaryBreath = CameraDirector.primaryBreathing;
    final drift = CameraDirector.slowDrift;
    final shake = CameraDirector.microShake;
    final intensity = CameraDirector.breathingIntensityMultiplier;
    
    // Layer 1: Primary breathing cycle (slow, rhythmic)
    final breathingPhase = (t * 2 * math.pi * primaryBreath.frequency) + _randomPhaseX;
    final breathingX = math.sin(breathingPhase) * primaryBreath.amplitude * intensity;
    final breathingY = math.cos(breathingPhase * 0.7 + _randomPhaseY) * primaryBreath.amplitude * intensity;
    
    // Layer 2: Very slow drift (gives organic wandering feel)
    final driftPhase = (t * 2 * math.pi * drift.frequency) + _randomPhaseDrift;
    final driftX = math.sin(driftPhase * 1.3) * drift.amplitude * intensity;
    final driftY = math.cos(driftPhase * 0.9) * drift.amplitude * intensity;
    
    // Layer 3: Micro-shake (tiny high-frequency tremor, like human hand-held)
    final shakePhase = t * 2 * math.pi * shake.frequency;
    final shakeX = math.sin(shakePhase * 3.7) * shake.amplitude * intensity;
    final shakeY = math.cos(shakePhase * 4.3) * shake.amplitude * intensity;
    
    // Combine all layers
    final totalSwayX = breathingX + driftX + shakeX;
    final totalSwayY = breathingY + driftY + shakeY;
    
    // Apply combined movement to current position
    final swayedPosition = Vector3(
      _currentCameraPosition!.x + totalSwayX,
      _currentCameraPosition!.y + totalSwayY,
      _currentCameraPosition!.z,
    );
    
    // Update camera with organic movement, looking at character's current position
    final characterCenter = CameraDirector.getCharacterCenter(_characterWorldPosition!);
    _camera!.lookAt(swayedPosition, focus: characterCenter);
    
    // Slowly drift the random phase offsets over time for continuous organic variation
    // This prevents the pattern from repeating exactly
    _randomPhaseDrift += 0.0001; // Very slow drift
  }
  
  /// Update camera position based on game state using director-friendly shot types
  /// All parameters controlled via CameraDirector
  Future<void> _updateCameraForState() async {
    if (_camera == null || _characterWorldPosition == null) return;
    
    Vector3 relativePosition;
    Duration transitionDuration;
    
    switch (widget.gameState) {
      case GameState.celebrating:
        // Get shot with optional random variation
        relativePosition = CameraDirector.getVariedShot(CameraDirector.celebratingShot);
        transitionDuration = CameraDirector.successTransitionSpeed;
        break;
      case GameState.failing:
        // Get shot with optional random variation
        relativePosition = CameraDirector.getVariedShot(CameraDirector.failingShot);
        transitionDuration = CameraDirector.failureTransitionSpeed;
        break;
      case GameState.completed:
        relativePosition = CameraDirector.getVariedShot(CameraDirector.completedShot);
        transitionDuration = CameraDirector.normalTransitionSpeed;
        break;
      case GameState.playing:
      default:
        relativePosition = CameraDirector.getVariedShot(CameraDirector.playingShot);
        transitionDuration = CameraDirector.normalTransitionSpeed;
    }
    
    // Convert relative position to world position based on character's current location
    final worldPosition = _getRelativeCameraPosition(relativePosition);
    
    if (_targetCameraPosition != worldPosition) {
      _targetCameraPosition = worldPosition;
      _animateCameraTo(worldPosition, duration: transitionDuration);
    }
  }
  
  /// Animate camera to target position smoothly
  Future<void> _animateCameraTo(Vector3 target, {Duration? duration}) async {
    if (_camera == null || _currentCameraPosition == null) return;
    
    final start = _currentCameraPosition!;
    final end = target;
    
    // Use custom duration if provided, otherwise default
    _cameraAnimationController.duration = duration ?? const Duration(milliseconds: 800);
    _cameraAnimationController.reset();
    
    // Store animation parameters
    _animationStart = start;
    _animationEnd = end;
    
    // Remove old listeners to avoid duplicates
    _cameraAnimationController.removeListener(_updateCameraPosition);
    _cameraAnimationController.removeStatusListener(_cameraAnimationStatusListener);
    
    // Add new listener for this animation
    _cameraAnimationController.addListener(_updateCameraPosition);
    _cameraAnimationController.addStatusListener(_cameraAnimationStatusListener);
    
    _cameraAnimationController.forward();
  }

  /// Get animation name based on game state
  /// Maps Unity animator triggers to actual GLB animation names
  /// GLB animations use format: "combined_[Animation Name]-rabbit"
  String _getAnimationForState() {
    String animationName;
    switch (widget.gameState) {
      case GameState.celebrating:
        // Celebration animation - randomly select from available celebration animations
        // Only pick a new random animation when transitioning INTO celebrating state
        // (not on every rebuild while already in celebrating state)
        if (_celebrationAnimations.isNotEmpty) {
          // Use cached selection if we're already in celebrating state
          // Only pick a new one if we just transitioned into celebrating state
          if (_selectedCelebrationAnimation != null && _previousGameState == GameState.celebrating) {
            animationName = _selectedCelebrationAnimation!;
          } else {
            // Transitioning into celebrating state - pick a new random animation
            // Ensure it's different from the last one if we have multiple options
            String candidate;
            int attempts = 0;
            do {
              final randomIndex = _random.nextInt(_celebrationAnimations.length);
              candidate = _celebrationAnimations[randomIndex];
              attempts++;
            } while (attempts < 10 && 
                     _celebrationAnimations.length > 1 && 
                     candidate == _selectedCelebrationAnimation);
            
            _selectedCelebrationAnimation = candidate;
            animationName = candidate;
            print('🎉 Random celebration animation selected: name="$animationName" (from ${_celebrationAnimations.length} options)');
          }
        } else {
          // Fallback until celebration animations are loaded
          animationName = "combined_Cheering (4)-rabbit";
          _selectedCelebrationAnimation = animationName;
          print('⚠️ No celebration animations discovered, using fallback: "$animationName"');
        }
        break;
        
      case GameState.failing:
        // Failure animation - randomly select from available failure animations
        // Only pick a new random animation when transitioning INTO failing state
        // (not on every rebuild while already in failing state)
        if (_failureAnimations.isNotEmpty) {
          // Use cached selection if we're already in failing state
          // Only pick a new one if we just transitioned into failing state
          if (_selectedFailureAnimation != null && _previousGameState == GameState.failing) {
            animationName = _selectedFailureAnimation!;
          } else {
            // Transitioning into failing state - pick a new random animation
            // Ensure it's different from the last one if we have multiple options
            String candidate;
            int attempts = 0;
            do {
              final randomIndex = _random.nextInt(_failureAnimations.length);
              candidate = _failureAnimations[randomIndex];
              attempts++;
            } while (attempts < 10 && 
                     _failureAnimations.length > 1 && 
                     candidate == _selectedFailureAnimation);
            
            _selectedFailureAnimation = candidate;
            animationName = candidate;
            print('🎲 Random failure animation selected: name="$animationName" (from ${_failureAnimations.length} options)');
          }
        } else {
          // Fallback until failure animations are loaded
          animationName = "combined_Defeat-rabbit";
          _selectedFailureAnimation = animationName;
          print('⚠️ No failure animations discovered, using fallback: "$animationName"');
        }
        break;
        
      case GameState.playing:
        // Idle state during gameplay - cycle through available idle animations
        // Will use first available idle if cycling hasn't been set up yet
        if (_idleAnimations.isNotEmpty) {
          animationName = _idleAnimations[_currentIdleIndex % _idleAnimations.length];
        } else {
          // Fallback until idle animations are loaded
          animationName = "combined_Happy Idle-rabbit";
        }
        break;
        
      case GameState.completed:
        // Game complete - randomly select from available completion/dance animations
        // Only pick a new random animation when transitioning INTO completed state
        // (not on every rebuild while already in completed state)
        if (_completionAnimations.isNotEmpty) {
          // Use cached selection if we're already in completed state
          // Only pick a new one if we just transitioned into completed state
          if (_selectedCompletionAnimation != null && _previousGameState == GameState.completed) {
            animationName = _selectedCompletionAnimation!;
          } else {
            // Transitioning into completed state - pick a new random animation
            // Ensure it's different from the last one if we have multiple options
            String candidate;
            int attempts = 0;
            do {
              final randomIndex = _random.nextInt(_completionAnimations.length);
              candidate = _completionAnimations[randomIndex];
              attempts++;
            } while (attempts < 10 && 
                     _completionAnimations.length > 1 && 
                     candidate == _selectedCompletionAnimation);
            
            _selectedCompletionAnimation = candidate;
            animationName = candidate;
            print('🎊 Random completion animation selected: name="$animationName" (from ${_completionAnimations.length} options)');
          }
        } else {
          // Fallback until completion animations are loaded
          animationName = "combined_Dancing-rabbit";
          _selectedCompletionAnimation = animationName;
          print('⚠️ No completion animations discovered, using fallback: "$animationName"');
        }
        break;
        
      default:
        // Default to first idle animation found
        animationName = "combined_Box Idle-rabbit";
    }
    
    // Debug: Log animation name for troubleshooting
    if (animationName != _currentAnimation) {
      print('🎬 Character animation: ${widget.gameState} → "$animationName"');
    }
    
    return animationName;
  }

  /// Update animation when game state changes
  Future<void> _updateAnimation() async {
    if (_asset == null || _viewer == null) return;
    
    final newAnimation = _getAnimationForState();
    
    // Skip if it's the same animation (unless we're transitioning into failing state)
    if (newAnimation == _currentAnimation) {
      return;
    }
    
    _currentAnimation = newAnimation;
    
    try {
      // Get available animations to verify the name exists
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      if (availableAnimations.contains(_currentAnimation)) {
        // Play the animation - loop for idle/playing and completion (keep celebrating/dancing)
        // Don't loop for one-time reactions (celebration, failure)
        final shouldLoop = widget.gameState == GameState.playing || 
                          widget.gameState == GameState.completed;
        await _asset!.playGltfAnimationByName(
          _currentAnimation!,
          loop: shouldLoop,
          crossfade: 0.3, // Smooth transition
        );
      } else {
        print('⚠️ Animation "$_currentAnimation" not found in GLB. Available: ${availableAnimations.take(10).join(", ")}...');
        // Fallback: Find appropriate animation based on game state
        String fallback = '';
        if (widget.gameState == GameState.celebrating) {
          // Try to find any celebration animation
          fallback = availableAnimations.firstWhere(
            (name) => name.toLowerCase().contains('cheering') || 
                     name.toLowerCase().contains('victory') ||
                     name.toLowerCase().contains('agreeing'),
            orElse: () => '',
          );
        } else if (widget.gameState == GameState.failing) {
          // Try to find any failure animation
          fallback = availableAnimations.firstWhere(
            (name) => name.toLowerCase().contains('defeat') || 
                     name.toLowerCase().contains('annoyed'),
            orElse: () => '',
          );
        } else if (widget.gameState == GameState.completed) {
          // Try to find any dance animation
          fallback = availableAnimations.firstWhere(
            (name) => name.toLowerCase().contains('dancing') || 
                     name.toLowerCase().contains('dance'),
            orElse: () => '',
          );
        }
        
        // If no specific fallback found, try any idle
        if (fallback.isEmpty) {
          fallback = availableAnimations.firstWhere(
            (name) => name.toLowerCase().contains('idle'),
            orElse: () => '',
          );
        }
        
        // Last resort: use first available
        if (fallback.isEmpty && availableAnimations.isNotEmpty) {
          fallback = availableAnimations.first;
        }
        
        if (fallback.isNotEmpty) {
          print('🔄 Using fallback animation: "$fallback"');
          await _asset!.playGltfAnimationByName(fallback, loop: true, crossfade: 0.3);
        }
      }
    } catch (e) {
        print('❌ Error playing animation "$_currentAnimation": $e');
    }
  }

  /// Called when the Thermion viewer is ready
  Future<void> _onViewerAvailable(ThermionViewer viewer) async {
    _viewer = viewer;
    
    try {
      // Get camera for animation control
      _camera = await viewer.getActiveCamera();
      
      // Set initial camera position, looking at character's center
      if (_currentCameraPosition != null && _characterWorldPosition != null) {
        final characterCenter = CameraDirector.getCharacterCenter(_characterWorldPosition!);
        await _camera!.lookAt(_currentCameraPosition!, focus: characterCenter);
      }
      
      // Load the GLB model (ViewerWidget doesn't load it since we didn't provide assetPath)
      // Make sure addToScene is true so it's visible
      _asset = await viewer.loadGltf(
        'assets/models/Rabbit.glb',
        addToScene: true,
      );
      
      // Enhanced three-point lighting setup with proper front-lighting
      // IMPORTANT: In Filament/Thermion, direction vector is the direction light travels FROM
      // Camera is at positive Z (3.0) looking at origin, so light from front needs NEGATIVE Z
      // Key light: Front-top (main illumination from camera's perspective)
      final keyLight = DirectLight.sun(
        color: 4500.0, // Warmer daylight
        intensity: 150000.0, // Slightly reduced for more natural look
        castShadows: false,
        direction: Vector3(0.2, -0.7, -0.7).normalized(), // Front-top (negative Z = from camera direction)
      );
      await viewer.addDirectLight(keyLight);
      
      // Fill light: Front-top, opposite side (softer, reduces shadows from key light)
      final fillLight = DirectLight.sun(
        color: 5000.0, // Warmer fill
        intensity: 65000.0, // Slightly reduced fill light
        castShadows: false,
        direction: Vector3(-0.2, -0.6, -0.75).normalized(), // Front-top-left (negative Z = from camera)
      );
      await viewer.addDirectLight(fillLight);
      
      // Rim light: Back-top (adds depth and separation, creates edge highlight)
      // State-responsive color - warm gold during celebration, cool during failure
      final rimLight = DirectLight.sun(
        color: _getRimLightColor(),
        intensity: 45000.0,
        castShadows: false,
        direction: Vector3(0.0, -0.3, 0.95).normalized(), // Back-top (positive Z = from behind character)
      );
      await viewer.addDirectLight(rimLight);
      
      // Load the complete game scene (includes ground, backdrop, rug, books, plants)
      print('🔄 About to load game scene...');
      await _loadGameScene(viewer);
      print('✓ Game scene load complete');
      
      // Create personalized rug texture and apply it
      print('🔄 About to load personalized rug...');
      await _createPersonalizedRug(viewer);
      print('✓ Rug load attempt complete');
      
      // Note: Using gradient background instead of skybox for Phase 1
      // Skybox can be added later with KTX environment files
      
      // Ensure animation component is added
      await _asset!.addAnimationComponent();
      
      // Update character's world position for camera tracking
      await _updateCharacterPosition();
      
      // Validate character dimensions (for camera positioning accuracy)
      await _validateCharacterDimensions();
      
      // Discover and set up idle animations for cycling
      await _discoverIdleAnimations();
      
      // Discover and set up failure animations for random selection
      await _discoverFailureAnimations();
      
      // Discover and set up celebration animations for random selection
      await _discoverCelebrationAnimations();
      
      // Discover and set up completion/dance animations for random selection
      await _discoverCompletionAnimations();
      
      // Play initial animation
      await _updateAnimation();
      
      // Start idle animation cycling if in playing state
      if (widget.gameState == GameState.playing) {
        _startIdleAnimationCycling();
      }
      
      // Set initial camera position for current state
      // If we're in playing state and haven't done the zoom yet, do it now
      if (widget.gameState == GameState.playing && !_hasPerformedInitialZoom) {
        await _performCinematicZoomIn();
      } else {
        await _updateCameraForState();
      }
      
      setState(() {});
    } catch (e) {
      print('❌ Error loading 3D model: $e');
    }
  }

  /// Get rim light color based on game state for emotional tone
  double _getRimLightColor() {
    switch (widget.gameState) {
      case GameState.celebrating:
        return 3500.0; // Warm gold/amber for celebration
      case GameState.failing:
        return 7500.0; // Cool blue for failure
      case GameState.completed:
        return 3000.0; // Very warm for completion
      case GameState.playing:
      default:
        return 5500.0; // Neutral daylight
    }
  }
  
  /// Discover available failure animations from the GLB model
  /// Selects appropriate failure animations (falling, defeat, etc.)
  /// 
  /// Available animations in GLB (from documentation):
  /// - Idle
  /// - Happy Idle
  /// - Dwarf Idle
  /// - Defeat
  /// - Dodging
  /// - Dying Backwards
  /// - Fall Flat
  /// - Falling Back Death
  /// - Fast Run
  /// - Inside Crescent Kick
  /// - Jump
  /// - Jumping
  /// - Kicking
  /// - Locking Hip Hop Dance
  /// - One Hand Club Combo
  /// - Punching
  /// - Running
  /// - Shoulder Hit And Fall
  /// - Side Kick
  /// - Slow Run
  /// - Standing Idle 04
  /// - Standing W_Briefcase Idle
  /// - Sword And Shield Power Up
  /// - Victory Idle
  /// - Walking
  /// - Wave Hip Hop Dance
  Future<void> _discoverFailureAnimations() async {
    if (_asset == null) return;
    
    try {
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      // Debug: Print all available animations to see what we're working with
      print('🔍 All available animations in GLB (${availableAnimations.length} total):');
      for (final anim in availableAnimations) {
        print('   - $anim');
      }
      
      // Whitelist of failure animations based on documentation and what's actually in GLB
      // From the logs, we know these exist. Search for all failure-related animations.
      final failureAnimationCandidates = [
        // Confirmed to exist (from logs):
        'combined_Defeat Idle-rabbit',
        'combined_Defeat Idle2-rabbit',
        'combined_Fall Flat-rabbit',
        // From documentation (check if they exist):
        'combined_Defeat-rabbit', // Standalone "Defeat" (not "Defeat Idle")
        'combined_Shoulder Hit And Fall-rabbit',
        'combined_Falling Back Death-rabbit',
        'combined_Dying Backwards-rabbit',
      ];
      
      // First, try exact matches
      _failureAnimations = failureAnimationCandidates.where((name) {
        return availableAnimations.contains(name);
      }).toList();
      
      // Also search for any animation containing failure keywords (as fallback)
      final failureKeywords = ['defeat', 'fall flat', 'falling back death', 'dying backwards', 'shoulder hit'];
      final keywordMatches = availableAnimations.where((name) {
        final lowerName = name.toLowerCase();
        final hasFailureKeyword = failureKeywords.any((keyword) => lowerName.contains(keyword));
        final isNotVictory = !lowerName.contains('victory') && !lowerName.contains('cheering');
        // Allow "Defeat" and "Defeat Idle" but exclude other idle animations
        final isDefeatRelated = lowerName.contains('defeat');
        final isNotOtherIdle = !lowerName.contains('idle') || isDefeatRelated;
        return hasFailureKeyword && isNotVictory && isNotOtherIdle;
      }).toList();
      
      // Combine and remove duplicates
      _failureAnimations.addAll(keywordMatches);
      _failureAnimations = _failureAnimations.toSet().toList();
      
      // Shuffle for variety
      _failureAnimations.shuffle();
      
      print('🎬 Found ${_failureAnimations.length} failure animations: ${_failureAnimations.join(", ")}');
    } catch (e) {
      print('⚠️ Error discovering failure animations: $e');
      _failureAnimations = [];
    }
  }
  
  /// Discover available celebration animations from the GLB model
  /// Selects appropriate celebration animations (jumping, victory, cheering, etc.)
  Future<void> _discoverCelebrationAnimations() async {
    if (_asset == null) return;
    
    try {
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      // Whitelist of celebration animations based on documentation and what's actually in GLB
      final celebrationAnimationCandidates = [
        // Jumping animations (user specifically mentioned "Jumping")
        'combined_Jump-rabbit',
        'combined_Jumping-rabbit',
        // Victory animations
        'combined_Victory Idle-rabbit',
        // Cheering (currently used)
        'combined_Cheering (4)-rabbit',
        // Other potential celebration animations
        'combined_Agreeing-rabbit',
        'combined_Fist Pump-rabbit',
        'combined_Joyful Jump-rabbit',
        'combined_Head Nod Yes-rabbit',
      ];
      
      // First, try exact matches
      _celebrationAnimations = celebrationAnimationCandidates.where((name) {
        return availableAnimations.contains(name);
      }).toList();
      
      // Also search for any animation containing celebration keywords (as fallback)
      final celebrationKeywords = ['jump', 'jumping', 'victory', 'cheering', 'agreeing', 'fist pump', 'joyful'];
      final keywordMatches = availableAnimations.where((name) {
        final lowerName = name.toLowerCase();
        final hasCelebrationKeyword = celebrationKeywords.any((keyword) => lowerName.contains(keyword));
        // Exclude failure/defeat animations
        final isNotFailure = !lowerName.contains('defeat') && !lowerName.contains('fall') && !lowerName.contains('dying');
        // Exclude dance animations (those are for completion, not celebration)
        final isNotDance = !lowerName.contains('dance') && !lowerName.contains('dancing');
        return hasCelebrationKeyword && isNotFailure && isNotDance;
      }).toList();
      
      // Combine and remove duplicates
      _celebrationAnimations.addAll(keywordMatches);
      _celebrationAnimations = _celebrationAnimations.toSet().toList();
      
      // Shuffle for variety
      _celebrationAnimations.shuffle();
      
      print('🎉 Found ${_celebrationAnimations.length} celebration animations: ${_celebrationAnimations.join(", ")}');
    } catch (e) {
      print('⚠️ Error discovering celebration animations: $e');
      _celebrationAnimations = [];
    }
  }
  
  /// Discover available completion/dance animations from the GLB model
  /// Selects appropriate dance animations for game completion
  Future<void> _discoverCompletionAnimations() async {
    if (_asset == null) return;
    
    try {
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      // Whitelist of completion/dance animations based on documentation and what's actually in GLB
      final completionAnimationCandidates = [
        // Dance animations (primary completion animations)
        'combined_Dancing-rabbit',
        'combined_Dancing2-rabbit',
        'combined_Locking Hip Hop Dance-rabbit',
        'combined_Wave Hip Hop Dance-rabbit',
        'combined_Chicken Dance-rabbit',
        'combined_Gangnam Style-rabbit',
        'combined_Macarena Dance-rabbit',
        'combined_Robot Hip Hop Dance-rabbit',
        'combined_Slide Hip Hop Dance-rabbit',
        'combined_Swing Dancing-rabbit',
        'combined_Tut Hip Hop Dance-rabbit',
        'combined_Northern Soul Spin-rabbit',
        'combined_Hip Hop Dancing-rabbit',
        // Victory animations (also good for completion)
        'combined_Victory Idle-rabbit',
        'combined_Victory Idle2-rabbit',
      ];
      
      // First, try exact matches
      _completionAnimations = completionAnimationCandidates.where((name) {
        return availableAnimations.contains(name);
      }).toList();
      
      // Also search for any animation containing dance/completion keywords (as fallback)
      final completionKeywords = ['dance', 'dancing', 'victory idle', 'victory idle2'];
      final keywordMatches = availableAnimations.where((name) {
        final lowerName = name.toLowerCase();
        final hasCompletionKeyword = completionKeywords.any((keyword) => lowerName.contains(keyword));
        // Exclude failure/defeat animations
        final isNotFailure = !lowerName.contains('defeat') && !lowerName.contains('fall') && !lowerName.contains('dying');
        // Exclude jump animations (those are for celebration, not completion)
        final isNotJump = !lowerName.contains('jump') || lowerName.contains('victory');
        return hasCompletionKeyword && isNotFailure && isNotJump;
      }).toList();
      
      // Combine and remove duplicates
      _completionAnimations.addAll(keywordMatches);
      _completionAnimations = _completionAnimations.toSet().toList();
      
      // Shuffle for variety
      _completionAnimations.shuffle();
      
      print('🎊 Found ${_completionAnimations.length} completion animations: ${_completionAnimations.join(", ")}');
    } catch (e) {
      print('⚠️ Error discovering completion animations: $e');
      _completionAnimations = [];
    }
  }
  
  /// Discover available idle animations from the GLB model
  /// Uses strict whitelist to only include actual idle animations
  Future<void> _discoverIdleAnimations() async {
    if (_asset == null) return;
    
    try {
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      // Strict whitelist of actual idle animations (excludes Victory Idle and static poses)
      final idleAnimationNames = [
        'combined_Idle-rabbit',
        'combined_Happy Idle-rabbit',
        // Excluded: 'combined_Dwarf Idle-rabbit' - too static/fixed pose
        'combined_Standing Idle 04-rabbit',
        'combined_Standing W_Briefcase Idle-rabbit',
      ];
      
      // Only add animations that exist in the GLB and are in our whitelist
      _idleAnimations = idleAnimationNames.where((name) {
        return availableAnimations.contains(name);
      }).toList();
      
      // Shuffle for variety
      _idleAnimations.shuffle();
      _currentIdleIndex = 0;
      
      print('🎬 Found ${_idleAnimations.length} idle animations: ${_idleAnimations.join(", ")}');
    } catch (e) {
      print('⚠️ Error discovering idle animations: $e');
      _idleAnimations = [];
    }
  }
  
  /// Start cycling through idle animations during playing state
  void _startIdleAnimationCycling() {
    _stopIdleAnimationCycling(); // Stop any existing timer
    
    if (_idleAnimations.length <= 1) return; // Need at least 2 to cycle
    
    _idleAnimationTimer = Timer.periodic(_idleAnimationDuration, (timer) {
      if (widget.gameState != GameState.playing) {
        timer.cancel();
        return;
      }
      
      // Move to next idle animation
      _currentIdleIndex = (_currentIdleIndex + 1) % _idleAnimations.length;
      
      // Update animation
      _updateAnimation();
    });
  }
  
  /// Stop cycling through idle animations
  void _stopIdleAnimationCycling() {
    _idleAnimationTimer?.cancel();
    _idleAnimationTimer = null;
  }
  
  /// Update character's world position by querying the asset
  /// Call this periodically or when animations change to keep camera tracking accurate
  Future<void> _updateCharacterPosition() async {
    if (_asset == null) return;
    
    try {
      // In this implementation, the character model doesn't move in world space
      // (animations are skeletal, not positional), so we use the base position
      _characterWorldPosition = CameraDirector.characterBasePosition;
      
      // Future enhancement: If we need to track actual movement (e.g., for positional animations),
      // we would call await _asset!.getWorldTransform() and extract position from the transform matrix
      // Transform is a 4x4 matrix where the last column contains position (x, y, z, 1)
    } catch (e) {
      // If we can't get transform, fall back to default position
      _characterWorldPosition = CameraDirector.characterBasePosition;
    }
  }
  
  /// Validate character dimensions by querying the actual model bounding box
  /// This helps ensure camera positioning is accurate for the actual character size
  Future<void> _validateCharacterDimensions() async {
    if (_asset == null || _viewer == null) return;
    
    try {
      // Get the bounding box of the character model
      final boundingBox = await _asset!.getBoundingBox();
      
      // Aabb3 has min and max properties (Vector3)
      // Y-axis is vertical in this coordinate system
      final minY = boundingBox.min.y; // Bottom of model
      final maxY = boundingBox.max.y; // Top of model
      
      final actualHeight = maxY - minY;
      final actualCenter = minY + (actualHeight / 2);
      
      // Estimate eye level (typically 75-80% up from bottom for humanoid characters)
      final estimatedEyeLevel = minY + (actualHeight * 0.75);
      
      print('');
      print('📏 CHARACTER DIMENSION VALIDATION:');
      print('════════════════════════════════════════════════════════');
      print('🎯 Units: Likely meters (Thermion/Filament default)');
      print('');
      print('📦 Bounding Box (raw data):');
      print('   Min: (${boundingBox.min.x.toStringAsFixed(2)}, ${boundingBox.min.y.toStringAsFixed(2)}, ${boundingBox.min.z.toStringAsFixed(2)})');
      print('   Max: (${boundingBox.max.x.toStringAsFixed(2)}, ${boundingBox.max.y.toStringAsFixed(2)}, ${boundingBox.max.z.toStringAsFixed(2)})');
      print('');
      print('📏 ACTUAL Model Measurements:');
      print('   Total Height (Y-axis): ${actualHeight.toStringAsFixed(3)} units');
      print('   Bottom (minY):          ${minY.toStringAsFixed(3)} units');
      print('   Top (maxY):             ${maxY.toStringAsFixed(3)} units');
      print('   Center Y:               ${actualCenter.toStringAsFixed(3)} units');
      print('   Estimated Eye Level:    ${estimatedEyeLevel.toStringAsFixed(3)} units (75% up)');
      print('');
      print('🎬 CURRENT Camera Config Values:');
      print('   characterHeight:       ${CameraDirector.characterHeight.toStringAsFixed(3)} units');
      print('   characterCenterHeight: ${CameraDirector.characterCenterHeight.toStringAsFixed(3)} units');
      print('   characterEyeLevel:     ${CameraDirector.characterEyeLevel.toStringAsFixed(3)} units');
      print('');
      
      // Calculate differences
      final heightDiff = (actualHeight - CameraDirector.characterHeight).abs();
      final centerDiff = (actualCenter - CameraDirector.characterCenterHeight).abs();
      final eyeDiff = (estimatedEyeLevel - CameraDirector.characterEyeLevel).abs();
      
      print('⚖️  COMPARISON (absolute difference):');
      print('   Height difference:  ${heightDiff.toStringAsFixed(3)} units');
      print('   Center difference:  ${centerDiff.toStringAsFixed(3)} units');
      print('   Eye level difference: ${eyeDiff.toStringAsFixed(3)} units');
      print('');
      
      // Provide recommendations
      if (heightDiff > 0.1 || centerDiff > 0.1 || eyeDiff > 0.1) {
        print('💡 RECOMMENDATION: Update camera_director.dart with actual values:');
        print('');
        print('   static const double characterHeight = ${actualHeight.toStringAsFixed(2)};');
        print('   static const double characterCenterHeight = ${actualCenter.toStringAsFixed(2)};');
        print('   static const double characterEyeLevel = ${estimatedEyeLevel.toStringAsFixed(2)};');
        print('');
        print('   This will improve camera framing accuracy!');
      } else {
        print('✅ Current values are close enough! Camera framing should be accurate.');
      }
      
      print('════════════════════════════════════════════════════════');
      print('');
      
    } catch (e) {
      print('⚠️ Could not validate character dimensions: $e');
      print('   Current camera config values are guesses and may need adjustment.');
    }
  }
  
  /// Convert a relative camera position (from CameraConfig) to a world position
  /// based on the character's current world position
  Vector3 _getRelativeCameraPosition(Vector3 relativePosition) {
    if (_characterWorldPosition == null) {
      return relativePosition; // Fallback if character position not yet known
    }
    
    // CameraConfig positions are already defined as offsets from character position (0, 0, 0)
    // So we add the character's world position to get the actual camera world position
    return Vector3(
      _characterWorldPosition!.x + relativePosition.x,
      _characterWorldPosition!.y + relativePosition.y,
      _characterWorldPosition!.z + relativePosition.z,
    );
  }
  
  /// Load the complete game scene (ground, backdrop, rug, books, plants)
  Future<void> _loadGameScene(ThermionViewer viewer) async {
    try {
      print('📐 Loading game scene...');
      
      // Load GameScene GLB which includes all assets
      // Note: Blender uses Z-up, Thermion uses Y-up
      // Positions are converted during export, but we may need to adjust
      await viewer.loadGltf(
        'assets/models/exports/GameScene.glb',
        addToScene: true,
      );
      
      print('✅ Game scene loaded (includes ground, backdrop, rug, books, plants)');
    } catch (e) {
      print('⚠️ Game scene loading failed: $e');
      // Fallback to just ground plane if GameScene fails
      try {
        print('📐 Falling back to ground plane...');
        await viewer.loadGltf(
          'assets/models/GroundPlane.glb',
          addToScene: true,
        );
        print('✅ Ground plane loaded (fallback)');
      } catch (e2) {
        print('⚠️ Ground plane fallback also failed: $e2');
      }
    }
  }
  
  /// Create personalized rug with dynamic texture generation
  /// Generates texture at runtime and modifies GLB before loading
  Future<void> _createPersonalizedRug(ThermionViewer viewer) async {
    print('═══════════════════════════════════════');
    print('🎨 GENERATING PERSONALIZED RUG');
    print('═══════════════════════════════════════');
    
    // Show loading overlay
    OverlayEntry? loadingOverlay;
    String? errorMessage;
    
    try {
      // Get name and font from game controller settings
      final controller = context.read<GameController>();
      final name = controller.settings?.childName ?? '';
      final fontFamily = controller.settings?.rugFontFamily ?? 'Quicksand';
      
      if (name.isEmpty) {
        print('⚠️ No child name set, using default');
        return; // Skip rug generation if no name
      }
      
      print('👤 Generating rug for: $name (font: $fontFamily)');
      
      // Generate texture PNG using dart:ui Canvas
      final texturePng = await _generateRugTexture(name, fontFamily);
      print('✅ Generated texture: ${texturePng.length} bytes');
      
      // Show loading overlay
      if (mounted) {
        loadingOverlay = OverlayEntry(
          builder: (context) => RugLoadingOverlay(
            childName: name,
            errorMessage: errorMessage,
          ),
        );
        Overlay.of(context).insert(loadingOverlay);
      }
      
      // Get cache directory for modified GLB
      final cacheDir = await getTemporaryDirectory();
      final modifiedRugPath = '${cacheDir.path}/PersonalizedRug_$name.glb';
      
      print('📝 Modifying GLB with personalized texture...');
      
      // Replace texture in template GLB
      final success = await GlbTextureReplacer.replaceTexture(
        templateAssetPath: 'assets/models/library/Rug.glb',
        newTexturePng: texturePng,
        outputPath: modifiedRugPath,
      );
      
      if (!success) {
        errorMessage = 'Failed to modify GLB template';
        print('❌ $errorMessage');
        throw Exception(errorMessage);
      }
      
      print('✅ Modified GLB created: $modifiedRugPath');
      print('🔄 Loading personalized rug into scene...');
      
      // Load the modified GLB with personalized texture
      await viewer.loadGltf(
        'file://$modifiedRugPath',
        addToScene: true,
      );
      
      print('═══════════════════════════════════════');
      print('✅ PERSONALIZED RUG LOADED SUCCESSFULLY!');
      print('   Name: "$name"');
      print('   GLB: $modifiedRugPath');
      print('═══════════════════════════════════════');
      
      // Remove loading overlay on success
      loadingOverlay?.remove();
      loadingOverlay = null;
      
    } catch (e, stackTrace) {
      print('═══════════════════════════════════════');
      print('❌ RUG GENERATION/LOADING FAILED!');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('═══════════════════════════════════════');
      
      // Update overlay with error
      if (loadingOverlay != null && mounted) {
        errorMessage = e.toString();
        loadingOverlay.markNeedsBuild();
        
        // Auto-dismiss after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          loadingOverlay?.remove();
        });
      }
      
      // Rug is optional, so we continue even if it fails
    }
  }
  
  /// Generate rug texture PNG with personalized name
  /// Returns PNG bytes
  Future<Uint8List> _generateRugTexture(String name, String fontFamily) async {
    const size = 1024;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    
    // Draw circular rug base (warm beige)
    paint.color = const Color(0xFFD2B48C); // Tan
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2 - 20,
      paint,
    );
    
    // Add subtle texture circles for fabric feel
    paint.color = const Color(0xFFBE9878); // Slightly darker
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.0;
    for (int i = 0; i < 5; i++) {
      final radius = (size / 2 - 20) - (i * size / 16);
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        radius,
        paint,
      );
    }
    
    // Get font style based on selected font family
    final welcomeStyle = _getRugFontStyle(fontFamily, 80, FontWeight.w600);
    final nameStyle = _getRugFontStyle(fontFamily, 120, FontWeight.w700);
    
    // Draw "Welcome" (first line - warm greeting)
    final welcomeTextPainter = TextPainter(
      text: TextSpan(
        text: 'Welcome',
        style: welcomeStyle.copyWith(
          color: const Color(0xFF3C2814), // Dark brown
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    welcomeTextPainter.layout();
    welcomeTextPainter.paint(
      canvas,
      Offset(size / 2 - welcomeTextPainter.width / 2, size / 2 - 140),
    );
    
    // Draw child's name (second line - THE STAR!)
    final nameTextPainter = TextPainter(
      text: TextSpan(
        text: '$name!',
        style: nameStyle.copyWith(
          color: const Color(0xFF5D3A1A), // Rich brown (slightly lighter for contrast)
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    nameTextPainter.layout();
    nameTextPainter.paint(
      canvas,
      Offset(size / 2 - nameTextPainter.width / 2, size / 2 + 60),
    );
    
    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  /// Get the appropriate Google Font style for the rug
  TextStyle _getRugFontStyle(String fontFamily, double fontSize, FontWeight weight) {
    switch (fontFamily) {
      case 'Quicksand':
        return GoogleFonts.quicksand(fontSize: fontSize, fontWeight: weight);
      case 'Nunito':
        return GoogleFonts.nunito(fontSize: fontSize, fontWeight: weight);
      case 'Fredoka':
        return GoogleFonts.fredoka(fontSize: fontSize, fontWeight: weight);
      case 'Chewy':
        return GoogleFonts.chewy(fontSize: fontSize);
      case 'Rubik Bubbles':
        return GoogleFonts.rubikBubbles(fontSize: fontSize);
      case 'Righteous':
        return GoogleFonts.righteous(fontSize: fontSize);
      case 'Galindo':
        return GoogleFonts.galindo(fontSize: fontSize);
      case 'Pacifico':
        return GoogleFonts.pacifico(fontSize: fontSize);
      case 'Lavishly Yours':
        return GoogleFonts.lavishlyYours(fontSize: fontSize);
      case 'Ballet':
        return GoogleFonts.ballet(fontSize: fontSize);
      default:
        return GoogleFonts.quicksand(fontSize: fontSize, fontWeight: weight);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always full-screen for maximum character presence
    return Container(
      decoration: const BoxDecoration(
        // Natural sky gradient that complements the wood floor
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A90E2), // Deeper blue at top
            Color(0xFF6BB6FF), // Medium blue in middle
            Color(0xFFA8D5FF), // Lighter blue at bottom (horizon)
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: ViewerWidget(
          // Don't provide assetPath - we'll load it ourselves in onViewerAvailable to avoid double loading
          assetPath: null,
          initialCameraPosition: CameraConfig.wideShot,
          manipulatorType: ManipulatorType.NONE, // Disable user interaction
          background: Colors.transparent, // Use gradient instead
          transformToUnitCube: false, // Keep original scale
          postProcessing: true, // Enable tone mapping and anti-aliasing
          // Lights are added programmatically in onViewerAvailable for better control
          onViewerAvailable: _onViewerAvailable,
          initial: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF4A90E2), // Deeper blue
                  Color(0xFF6BB6FF), // Medium blue
                  Color(0xFFA8D5FF), // Lighter blue
                ],
              ),
            ),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ),
        ),
    );
  }
}
