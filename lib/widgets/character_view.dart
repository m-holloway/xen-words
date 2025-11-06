import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import '../controllers/game_controller.dart';
import 'camera_config.dart';
import 'dart:math' as math;

/// Widget for displaying and animating the 3D character using Thermion
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
  Vector3? _targetCameraPosition;
  Vector3? _currentCameraPosition;
  bool _hasPerformedInitialZoom = false; // Track if we've done the cinematic start
  Vector3? _animationStart;
  Vector3? _animationEnd;

  @override
  void initState() {
    super.initState();
    _currentAnimation = _getAnimationForState();
    
    // Initialize camera animation controller
    _cameraAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200), // Longer for cinematic feel
      vsync: this,
    );
    
    // Start with a wide shot (will zoom in when game starts)
    _currentCameraPosition = CameraConfig.wideShot;
    _targetCameraPosition = _currentCameraPosition;
  }
  
  @override
  void dispose() {
    _cameraAnimationController.dispose();
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
      
      // Improved lighting setup for better PBR material visibility
      // Main key light from top-right (simulates natural sunlight)
      final keyLight = DirectLight.sun(
        color: 5500.0, // Slightly warmer daylight
        intensity: 120000.0, // Bright key light
        castShadows: false,
        direction: Vector3(0.4, -0.9, 0.2).normalized(),
      );
      await viewer.addDirectLight(keyLight);
      
      // Fill light from front-left (reduces harsh shadows)
      final fillLight = DirectLight.sun(
        color: 6500.0, // Cooler fill light
        intensity: 40000.0, // Softer fill
        castShadows: false,
        direction: Vector3(-0.3, -0.5, -0.8).normalized(),
      );
      await viewer.addDirectLight(fillLight);
      
      // Rim light from back (adds depth and separation from background)
      final rimLight = DirectLight.sun(
        color: 7000.0,
        intensity: 30000.0,
        castShadows: false,
        direction: Vector3(-0.2, 0.3, 0.9).normalized(),
      );
      await viewer.addDirectLight(rimLight);
      
      // Note: IBL (Image-Based Lighting) would provide even better results
      // but requires a KTX environment file. For now, three-point lighting works well.
      
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ViewerWidget(
          // Don't provide assetPath - we'll load it ourselves in onViewerAvailable to avoid double loading
          assetPath: null,
          initialCameraPosition: CameraConfig.wideShot,
          manipulatorType: ManipulatorType.NONE, // Disable user interaction
          background: Colors.transparent,
          transformToUnitCube: false, // Keep original scale
          postProcessing: true, // Enable tone mapping and anti-aliasing
          // Lights are added programmatically in onViewerAvailable for better control
          onViewerAvailable: _onViewerAvailable,
          initial: Container(
            color: Colors.transparent,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
