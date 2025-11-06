import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';
import 'camera_config.dart';
import 'dart:math' as math;
import 'dart:async';

/// Simplified character viewer for splash screen
/// Features continuous animation and smooth camera movement
class SplashCharacterView extends StatefulWidget {
  final double size;
  final Function()? onModelLoaded; // Called when model is fully loaded and ready
  
  const SplashCharacterView({
    Key? key,
    this.size = 200,
    this.onModelLoaded,
  }) : super(key: key);

  @override
  State<SplashCharacterView> createState() => _SplashCharacterViewState();
}

class _SplashCharacterViewState extends State<SplashCharacterView>
    with TickerProviderStateMixin {
  ThermionAsset? _asset;
  Camera? _camera;
  bool _hasError = false;
  String? _errorMessage;
  
  // Continuous camera orbit/zoom animation
  late AnimationController _cameraController;
  double _orbitAngle = 0.0; // Current orbit angle in radians
  double _zoomLevel = 0.0; // Current zoom level (0.0 to 1.0)
  
  // Orbit parameters
  static const double _orbitRadius = 3.5; // Base distance from character
  static const double _orbitSpeed = 0.3; // Radians per second
  static const double _zoomSpeed = 0.15; // Full zoom cycle per second
  static const double _zoomRange = 1.5; // Zoom range (distance variation)
  static const double _heightVariation = 0.4; // Vertical height variation

  @override
  void initState() {
    super.initState();
    
    // Initialize continuous camera animation controller
    // Very long duration for smooth continuous motion
    _cameraController = AnimationController(
      duration: const Duration(seconds: 100), // Long duration for continuous motion
      vsync: this,
    )..repeat(); // Repeat forever
    
    _cameraController.addListener(_updateCameraPosition);
  }
  
  @override
  void dispose() {
    // Cancel camera animation
    _cameraController.removeListener(_updateCameraPosition);
    _cameraController.stop();
    _cameraController.dispose();
    super.dispose();
  }
  
  /// Update camera position for continuous orbit/zoom
  /// This is called on every animation frame to ensure smooth motion
  void _updateCameraPosition() {
    if (!mounted || _camera == null) return;
    
    try {
      // Update orbit angle (continuous rotation)
      _orbitAngle = _cameraController.value * 2 * math.pi * _orbitSpeed;
      
      // Update zoom level (continuous zoom in/out)
      _zoomLevel = (math.sin(_cameraController.value * 2 * math.pi * _zoomSpeed) + 1.0) / 2.0;
      
      // Calculate distance with zoom variation
      final distance = _orbitRadius + (_zoomLevel - 0.5) * _zoomRange;
      
      // Calculate height with variation
      final height = CameraConfig.characterCenterHeight + 
          math.sin(_cameraController.value * 2 * math.pi * _zoomSpeed * 0.7) * _heightVariation;
      
      // Calculate camera position in orbit
      final cameraX = math.cos(_orbitAngle) * distance;
      final cameraZ = math.sin(_orbitAngle) * distance;
      final cameraY = height;
      
      final cameraPosition = Vector3(cameraX, cameraY, cameraZ);
      
      // Look at character center
      final characterCenter = CameraConfig.characterPosition + 
          Vector3(0, CameraConfig.characterCenterHeight, 0);
      _camera!.lookAt(cameraPosition, focus: characterCenter);
    } catch (e) {
      // Silently handle errors during camera updates to avoid spam
      // This can happen if camera is disposed or not ready
    }
  }

  /// Called when the Thermion viewer is ready
  Future<void> _onViewerAvailable(ThermionViewer viewer) async {
    if (!mounted) return;
    
    try {
      print('🎬 Splash: Viewer available, starting initialization...');
      
      // Get camera for animation control FIRST
      _camera = await viewer.getActiveCamera();
      print('📷 Splash: Camera obtained');
      
      if (!mounted) return;
      
      // Load the GLB model - remove timeout, let it load naturally
      // Large GLB files can take 15-30 seconds on slower devices
      print('📦 Splash: Loading GLB model from assets/models/Rabbit.glb...');
      print('⏳ Splash: This may take 15-30 seconds for large models...');
      try {
        _asset = await viewer.loadGltf(
          'assets/models/Rabbit.glb',
          addToScene: true,
        );
        print('✅ Splash: Model loaded and added to scene');
      } catch (e) {
        print('❌ Splash: Error loading model: $e');
        print('❌ Splash: Stack trace: ${StackTrace.current}');
        rethrow;
      }
      
      if (!mounted || _asset == null) {
        print('⚠️ Splash: Widget disposed or asset null after loading');
        return;
      }
      
      // Small delay to let model settle in scene
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Set initial camera position (orbit animation will take over)
      final characterCenter = CameraConfig.characterPosition + 
          Vector3(0, CameraConfig.characterCenterHeight, 0);
      final initialPosition = Vector3(_orbitRadius, CameraConfig.characterCenterHeight, 0);
      await _camera!.lookAt(initialPosition, focus: characterCenter);
      print('📷 Splash: Camera initialized, starting continuous orbit/zoom');
      
      // Set up lighting (same as game character view) - CRITICAL for visibility
      print('💡 Splash: Setting up lighting...');
      final keyLight = DirectLight.sun(
        color: 5500.0,
        intensity: 120000.0,
        castShadows: false,
        direction: Vector3(0.4, -0.9, 0.2).normalized(),
      );
      await viewer.addDirectLight(keyLight);
      
      final fillLight = DirectLight.sun(
        color: 6500.0,
        intensity: 40000.0,
        castShadows: false,
        direction: Vector3(-0.3, -0.5, -0.8).normalized(),
      );
      await viewer.addDirectLight(fillLight);
      
      final rimLight = DirectLight.sun(
        color: 7000.0,
        intensity: 30000.0,
        castShadows: false,
        direction: Vector3(-0.2, 0.3, 0.9).normalized(),
      );
      await viewer.addDirectLight(rimLight);
      print('✅ Splash: Lighting configured');
      
      // Enable animations - CRITICAL: Must add animation component before playing
      print('🎬 Splash: Adding animation component...');
      await _asset!.addAnimationComponent();
      
      // Longer delay to ensure animation system is fully initialized
      // The crash happens in getAnimator(), so we need to wait for the native side to be ready
      print('⏳ Splash: Waiting for animation system to initialize...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted || _asset == null) return;
      
      // Play a continuous idle animation
      print('🎬 Splash: Getting available animations...');
      final availableAnimations = await _asset!.getGltfAnimationNames();
      print('🎬 Splash: Found ${availableAnimations.length} animations: ${availableAnimations.take(5).join(", ")}...');
      
      if (availableAnimations.isEmpty) {
        print('⚠️ Splash: No animations available!');
        return;
      }
      
      // Try to find a good idle animation
      String? idleAnimation;
      for (final name in availableAnimations) {
        if (name.toLowerCase().contains('idle') || 
            name.toLowerCase().contains('happy') ||
            name.toLowerCase().contains('box')) {
          idleAnimation = name;
          break;
        }
      }
      
      // Play animation - simpler to avoid crashes
      final animationToPlay = idleAnimation ?? availableAnimations.first;
      
      print('🎬 Splash: Playing animation "$animationToPlay"');
      try {
        // Wait a bit more before playing to ensure everything is ready
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (!mounted || _asset == null) return;
        
        // Play animation once - don't try to restart it (that might cause the crash)
        await _asset!.playGltfAnimationByName(
          animationToPlay,
          loop: true,
          crossfade: 0.0, // No crossfade for initial play
        );
        
        print('✅ Splash: Animation "$animationToPlay" started');
      } catch (e, stackTrace) {
        print('❌ Splash: Error playing animation: $e');
        print('❌ Splash: Stack trace: $stackTrace');
        // Don't retry - might cause another crash
      }
      
      print('✅ Splash: Character loaded and animated');
      
      // Notify that model is fully loaded - this allows speech recognition to start
      if (mounted && widget.onModelLoaded != null) {
        widget.onModelLoaded!();
        print('📢 Splash: Notified that model is ready');
      }
      
      // Camera animation is already running (started in initState with repeat())
      // Just ensure it's active
      if (mounted) {
        if (!_cameraController.isAnimating) {
          _cameraController.repeat();
        }
        setState(() {});
      }
    } catch (e, stackTrace) {
      if (mounted) {
        print('❌ Error loading 3D model in splash: $e');
        print('❌ Stack trace: $stackTrace');
        // Show error state
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _hasError
            ? Container(
                color: Colors.red.withOpacity(0.2),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        '3D Error',
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: 12,
                        ),
                      ),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            _errorMessage!.length > 30
                                ? '${_errorMessage!.substring(0, 30)}...'
                                : _errorMessage!,
                            style: TextStyle(
                              color: Colors.red.shade200,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : ViewerWidget(
                assetPath: null, // Loaded programmatically
                initialCameraPosition: CameraConfig.splashIntroShot,
                manipulatorType: ManipulatorType.NONE,
                background: Colors.black.withOpacity(0.3), // Slight background to see if viewer is rendering
                transformToUnitCube: false,
                postProcessing: true,
                onViewerAvailable: _onViewerAvailable,
                initial: Container(
                  color: Colors.black.withOpacity(0.2),
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

