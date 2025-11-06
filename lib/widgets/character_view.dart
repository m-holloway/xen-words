import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import '../controllers/game_controller.dart';
import 'camera_config.dart';

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
  
  // Camera animation controllers
  late AnimationController _cameraAnimationController;
  late AnimationController _cameraSwayController; // For subtle idle sway
  Vector3? _targetCameraPosition;
  Vector3? _currentCameraPosition;
  bool _hasPerformedInitialZoom = false; // Track if we've done the cinematic start
  Vector3? _animationStart;
  Vector3? _animationEnd;
  
  // Camera sway parameters (subtle breathing effect during idle)
  static const double _swayAmplitude = 0.02; // Very subtle movement
  static const double _swaySpeed = 1.5; // Slow, gentle oscillation
  
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
    
    // Initialize camera animation controller
    _cameraAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200), // Longer for cinematic feel
      vsync: this,
    );
    
    // Initialize camera sway controller (for subtle idle movement)
    final swayDurationMs = (1000 / _swaySpeed).round();
    _cameraSwayController = AnimationController(
      duration: Duration(milliseconds: swayDurationMs),
      vsync: this,
    )..repeat(); // Continuously loop
    _cameraSwayController.addListener(_updateCameraSway);
    
    // Start with a wide shot (will zoom in when game starts)
    _currentCameraPosition = CameraConfig.wideShot;
    _targetCameraPosition = _currentCameraPosition;
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
    if (_camera == null || _currentCameraPosition == null) return;
    
    _hasPerformedInitialZoom = true;
    
    // Start from wide shot, zoom to natural gameplay shot
    final startPosition = CameraConfig.wideShot;
    final endPosition = CameraConfig.playingShot;
    
    // Set starting position if not already there, looking at character's center
    if (_currentCameraPosition != startPosition) {
      final characterCenter = CameraConfig.characterPosition + Vector3(0, CameraConfig.characterCenterHeight, 0);
      await _camera!.lookAt(startPosition, focus: characterCenter);
      _currentCameraPosition = startPosition;
    }
    
    // Animate with a nice ease-in-out curve
    _cameraAnimationController.duration = const Duration(milliseconds: 1500);
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
    if (_camera == null || _animationStart == null || _animationEnd == null) return;
    
    final start = _animationStart!;
    final end = _animationEnd!;
    final t = _cameraAnimationController.value;
    
    // Use easeInOutCubic for smooth acceleration and deceleration
    final easedT = t < 0.5
        ? 4 * t * t * t
        : 1 - math.pow(-2 * t + 2, 3) / 2;
    
    final current = Vector3(
      start.x + (end.x - start.x) * easedT,
      start.y + (end.y - start.y) * easedT,
      start.z + (end.z - start.z) * easedT,
    );
    
    _currentCameraPosition = current;
    
    // Position camera and look at character's center
    _camera!.lookAt(current, focus: CameraConfig.characterPosition + Vector3(0, CameraConfig.characterCenterHeight, 0));
  }
  
  /// Camera animation status listener
  void _cameraAnimationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed && _targetCameraPosition != null) {
      _currentCameraPosition = _targetCameraPosition;
    }
  }
  
  /// Apply subtle camera sway for breathing/life effect (only during playing state)
  void _updateCameraSway() {
    if (_camera == null || _currentCameraPosition == null) return;
    
    // Only apply sway during playing state (not during reactions or transitions)
    if (widget.gameState != GameState.playing) return;
    
    // Don't apply sway during camera transitions
    if (_cameraAnimationController.isAnimating) return;
    
    // Calculate sway offset using sine wave
    final t = _cameraSwayController.value * 2 * math.pi;
    final swayX = math.sin(t) * _swayAmplitude;
    final swayY = math.cos(t * 0.7) * _swayAmplitude; // Different frequency for Y
    
    // Apply sway to current position
    final swayedPosition = Vector3(
      _currentCameraPosition!.x + swayX,
      _currentCameraPosition!.y + swayY,
      _currentCameraPosition!.z,
    );
    
    // Update camera with sway
    final characterCenter = CameraConfig.characterPosition + Vector3(0, CameraConfig.characterCenterHeight, 0);
    _camera!.lookAt(swayedPosition, focus: characterCenter);
  }
  
  /// Update camera position based on game state using director-friendly shot types
  Future<void> _updateCameraForState() async {
    if (_camera == null) return;
    
    Vector3 newPosition;
    switch (widget.gameState) {
      case GameState.celebrating:
        newPosition = CameraConfig.celebratingShot;
        break;
      case GameState.failing:
        newPosition = CameraConfig.failingShot;
        break;
      case GameState.completed:
        newPosition = CameraConfig.completedShot;
        break;
      case GameState.playing:
      default:
        newPosition = CameraConfig.playingShot;
    }
    
    if (_targetCameraPosition != newPosition) {
      _targetCameraPosition = newPosition;
      _animateCameraTo(newPosition);
    }
  }
  
  /// Animate camera to target position smoothly
  Future<void> _animateCameraTo(Vector3 target) async {
    if (_camera == null || _currentCameraPosition == null) return;
    
    final start = _currentCameraPosition!;
    final end = target;
    
    // Use shorter duration for state changes (not the initial zoom)
    _cameraAnimationController.duration = const Duration(milliseconds: 800);
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
      if (_currentCameraPosition != null) {
        final characterCenter = CameraConfig.characterPosition + Vector3(0, CameraConfig.characterCenterHeight, 0);
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
      
      // Create simple ground plane for spatial grounding
      await _createGroundPlane(viewer);
      
      // Note: Using gradient background instead of skybox for Phase 1
      // Skybox can be added later with KTX environment files
      
      // Ensure animation component is added
      await _asset!.addAnimationComponent();
      
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
  
  /// Create a simple ground plane for spatial grounding
  Future<void> _createGroundPlane(ThermionViewer viewer) async {
    try {
      // Create a simple plane using a basic mesh
      // Position ground plane below character (at y: -0.1, just below character's feet)
      // For now, we'll create a simple colored plane
      // Note: Thermion may require loading a plane model or using procedural geometry
      // This is a placeholder that will work if Thermion supports it
      
      // Try to create a simple plane mesh
      // If Thermion doesn't support this directly, we may need to load a plane.glb model
      print('📐 Creating ground plane...');
      
      // For now, we'll note that a ground plane would be positioned at y: -0.1
      // and would be a large flat surface (maybe 10x10 units) with a subtle color/texture
      // This will be implemented when we have a plane model or procedural geometry support
      
      print('📐 Ground plane: Would be positioned at y: -0.1 with subtle color/texture');
    } catch (e) {
      print('⚠️ Ground plane creation: $e');
      // Ground plane is optional, so we continue even if it fails
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always full-screen for maximum character presence
    return Container(
      decoration: const BoxDecoration(
        // Beautiful gradient background that complements the character
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A148C), // Deep purple at top
            Color(0xFF7B1FA2), // Medium purple
            Color(0xFF9C27B0), // Lighter purple at bottom
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
                  Color(0xFF4A148C),
                  Color(0xFF7B1FA2),
                  Color(0xFF9C27B0),
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
