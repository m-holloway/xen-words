import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import '../controllers/game_controller.dart';
import 'camera_config.dart';
import 'dart:math' as math;

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
    super.dispose();
  }

  @override
  void didUpdateWidget(CharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gameState != oldWidget.gameState) {
      _updateAnimation();
      
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
        // Celebration animation - using Cheering from GLB
        animationName = "combined_Cheering (4)-rabbit";
        break;
        
      case GameState.failing:
        // Failure animation - using Defeat Idle from GLB
        animationName = "combined_Defeat Idle-rabbit";
        break;
        
      case GameState.playing:
        // Idle state during gameplay - look for any idle animation
        // Will fallback to first available if not found
        animationName = "combined_Box Idle-rabbit"; // Try Box Idle first
        break;
        
      case GameState.completed:
        // Game complete - using Dancing for celebration
        animationName = "combined_Dancing-rabbit";
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
    if (newAnimation == _currentAnimation) return;
    
    _currentAnimation = newAnimation;
    
    try {
      // Get available animations to verify the name exists
      final availableAnimations = await _asset!.getGltfAnimationNames();
      
      if (availableAnimations.contains(newAnimation)) {
        // Play the animation with looping enabled
        await _asset!.playGltfAnimationByName(
          newAnimation,
          loop: true,
          crossfade: 0.3, // Smooth transition
        );
      } else {
        print('⚠️ Animation "$newAnimation" not found in GLB. Available: ${availableAnimations.take(10).join(", ")}...');
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
      print('❌ Error playing animation "$newAnimation": $e');
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
      
      // Play initial animation
      await _updateAnimation();
      
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
  
  /// Create a simple ground plane for spatial grounding
  Future<void> _createGroundPlane(ThermionViewer viewer) async {
    try {
      // Create a simple plane mesh programmatically
      // For now, we'll use a basic colored plane
      // In Phase 2, we can add texture if desired
      
      // Note: Thermion doesn't have a built-in createPlane yet
      // We'll add this in a future update if needed
      // For now, the character floating on gradient background works well
      // Ground plane would be positioned at y: -0.1 (just below character's feet)
      
      print('📐 Ground plane placeholder - will add in future iteration');
    } catch (e) {
      print('⚠️ Ground plane creation skipped: $e');
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
