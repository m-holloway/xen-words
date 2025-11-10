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
import '../services/director_tuner.dart';
import 'camera_config.dart';
import 'camera_director.dart';
import 'lighting_director.dart';
import 'render_quality_director.dart';
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
  
  // Light references for live updates
  DirectLight? _primaryLight;
  DirectLight? _fillLight;
  DirectLight? _rimLight;
  
  // Rug asset reference for position updates
  ThermionAsset? _rugAsset;
  
  // Track last values to detect changes
  LightDirection? _lastPrimaryDirection;
  double? _lastPrimaryColorTemp;
  double? _lastPrimaryIntensity;
  bool? _lastPrimaryCastsShadows;
  LightDirection? _lastFillDirection;
  double? _lastFillColorTemp;
  double? _lastFillIntensity;
  bool? _lastFillCastsShadows;
  LightDirection? _lastRimDirection;
  double? _lastRimColorTemp;
  double? _lastRimIntensity;
  bool? _lastRimCastsShadows;
  double? _lastMasterBrightness;
  bool? _lastShadowsEnabled;
  int? _lastShadowType;
  
  // Track last render quality settings to detect changes
  bool? _lastPostProcessingEnabled;
  double? _lastShadowPenumbraScale;
  double? _lastShadowPenumbraRatioScale;
  bool? _lastMsaaEnabled;
  bool? _lastFxaaEnabled;
  bool? _lastTaaEnabled;
  bool? _lastBloomEnabled;
  double? _lastBloomStrength;
  int? _lastToneMapperType;
  bool? _lastFrustumCullingEnabled;
  bool? _lastFogEnabled;
  double? _lastFogDistance;
  double? _lastFogCutoffDistance;
  double? _lastFogMaximumOpacity;
  double? _lastFogDensity;
  double? _lastFogHeight;
  double? _lastFogHeightFalloff;
  double? _lastFogInScatteringStart;
  double? _lastFogInScatteringSize;
  bool? _lastFogColorFromIbl;
  double? _lastFogColorR;
  double? _lastFogColorG;
  double? _lastFogColorB;
  
  // Camera exposure tracking
  double? _lastCameraAperture;
  double? _lastCameraShutterSpeed;
  double? _lastCameraISO;
  
  // Debounce timer for lighting updates to prevent accumulation
  Timer? _lightingUpdateTimer;
  DateTime? _lastLightingUpdate;
  static const Duration _minLightingUpdateInterval = Duration(milliseconds: 200);
  
  // Director tuner listener
  // (no subscription needed - using ChangeNotifier listener)
  
  // Camera animation controllers
  late AnimationController _cameraAnimationController;
  late AnimationController _cameraSwayController; // For subtle idle sway
  Vector3? _targetCameraPosition;
  Vector3? _currentCameraPosition;
  bool _hasPerformedInitialZoom = false; // Track if we've done the cinematic start
  Vector3? _animationStart;
  Vector3? _animationEnd;
  
  // Accumulated phases for continuous animation (no boundary snapping)
  double _accumulatedBreathingPhase = 0.0;
  double _accumulatedDriftPhase = 0.0;
  double _accumulatedShakePhase = 0.0;
  double _lastSwayUpdateTime = 0.0;
  
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
    
    // Listen to director tuner changes for live updates
    DirectorTuner.instance.addListener(_onTunerChanged);
    
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
    
    // Initialize accumulated phases with random offsets for organic variation
    _accumulatedBreathingPhase = _random.nextDouble() * 2 * math.pi;
    _accumulatedDriftPhase = _random.nextDouble() * 2 * math.pi;
    _accumulatedShakePhase = _random.nextDouble() * 2 * math.pi;
    _lastSwayUpdateTime = 0.0;
  }
  
  @override
  void dispose() {
    _cameraAnimationController.dispose();
    _cameraSwayController.dispose();
    _idleAnimationTimer?.cancel();
    _lightingUpdateTimer?.cancel();
    DirectorTuner.instance.removeListener(_onTunerChanged);
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
  
  /// Perform initial game start transition when the game first begins
  /// Zooms from wide shot to the playing shot
  Future<void> _performCinematicZoomIn() async {
    if (_camera == null || _currentCameraPosition == null || _characterWorldPosition == null) return;
    
    _hasPerformedInitialZoom = true;
    
    // Start from wide shot, zoom to director's playing shot (using current tuner values)
    final startPosition = _getRelativeCameraPosition(CameraConfig.wideShot);
    final endPosition = _getRelativeCameraPosition(CameraDirector.getVariedShot(CameraDirector.playingShot));
    
    // Set starting position if not already there, looking at character's center
    if (_currentCameraPosition != startPosition) {
      final characterCenter = CameraDirector.getCharacterCenter(_characterWorldPosition!);
      await _camera!.lookAt(startPosition, focus: characterCenter);
      _currentCameraPosition = startPosition;
    }
    
    // Animate with initial game transition time
    _cameraAnimationController.duration = CameraDirector.initialGameTransitionTime;
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
  
  /// Called when DirectorTuner parameters change
  void _onTunerChanged() {
    if (_viewer == null) return;
    
    // Throttle updates: don't update more than once every 200ms
    final now = DateTime.now();
    if (_lastLightingUpdate != null && 
        now.difference(_lastLightingUpdate!) < _minLightingUpdateInterval) {
      // Too soon since last update, debounce it
      _lightingUpdateTimer?.cancel();
      _lightingUpdateTimer = Timer(_minLightingUpdateInterval, () {
      _lastLightingUpdate = DateTime.now();
      _updateLighting();
      _updateCameraForTuner();
      _updateRugPosition();
      _updateCameraExposure();
    });
      return;
    }
    
    // Debounce lighting updates to prevent light accumulation
    // When user is rapidly adjusting, wait for a pause before updating
    _lightingUpdateTimer?.cancel();
    _lightingUpdateTimer = Timer(const Duration(milliseconds: 100), () {
      _lastLightingUpdate = DateTime.now();
      // Update lighting if lighting parameters changed
      _updateLighting();
      
      // Update camera if camera parameters changed
      _updateCameraForTuner();
      
      // Update rug position if rug offset changed
      _updateRugPosition();
      
      // Update camera exposure if exposure parameters changed
      _updateCameraExposure();
    });
  }
  
  /// Update lighting based on current tuner values
  /// Uses debouncing to prevent light accumulation when rapidly adjusting
  /// IMPORTANT: Thermion accumulates lights when addDirectLight() is called.
  /// We must track if lights have changed and avoid unnecessary additions.
  Future<void> _updateLighting() async {
    if (_viewer == null || !LightingDirector.useCustomLighting) return;
    
    try {
      // Get current values
      final currentPrimaryDirection = LightingDirector.primaryDirection;
      final currentPrimaryColorTemp = LightingDirector.primaryColorTemp;
      final currentPrimaryIntensity = LightingDirector.primaryIntensity;
      final currentPrimaryCastsShadows = LightingDirector.primaryCastsShadows;
      
      final currentFillDirection = LightingDirector.fillDirection;
      final currentFillColorTemp = LightingDirector.fillColorTemp;
      final currentFillIntensity = LightingDirector.fillIntensity;
      final currentFillCastsShadows = LightingDirector.fillCastsShadows;
      
      final currentRimDirection = LightingDirector.rimDirection;
      final currentRimColorTemp = LightingDirector.rimColorTemp;
      final currentRimIntensity = LightingDirector.rimIntensity;
      final currentRimCastsShadows = LightingDirector.rimCastsShadows;
      
      final currentMasterBrightness = LightingDirector.masterBrightness;
      final currentShadowsEnabled = LightingDirector.shadowsEnabled;
      final currentShadowType = LightingDirector.shadowType;
      
      // Get current render quality settings
      final currentPostProcessing = RenderQualityDirector.postProcessingEnabled;
      final currentPenumbraScale = RenderQualityDirector.shadowPenumbraScale;
      final currentPenumbraRatio = RenderQualityDirector.shadowPenumbraRatioScale;
      final currentMsaa = RenderQualityDirector.msaaEnabled;
      final currentFxaa = RenderQualityDirector.fxaaEnabled;
      final currentTaa = RenderQualityDirector.taaEnabled;
      final currentBloomEnabled = RenderQualityDirector.bloomEnabled;
      final currentBloomStrength = RenderQualityDirector.bloomStrength;
      final currentToneMapper = RenderQualityDirector.toneMapperType;
      final currentFrustumCulling = RenderQualityDirector.frustumCullingEnabled;
      final currentFogEnabled = RenderQualityDirector.fogEnabled;
      final currentFogDistance = RenderQualityDirector.fogDistance;
      final currentFogCutoffDistance = RenderQualityDirector.fogCutoffDistance;
      final currentFogMaximumOpacity = RenderQualityDirector.fogMaximumOpacity;
      final currentFogDensity = RenderQualityDirector.fogDensity;
      final currentFogHeight = RenderQualityDirector.fogHeight;
      final currentFogHeightFalloff = RenderQualityDirector.fogHeightFalloff;
      final currentFogInScatteringStart = RenderQualityDirector.fogInScatteringStart;
      final currentFogInScatteringSize = RenderQualityDirector.fogInScatteringSize;
      final currentFogColorFromIbl = RenderQualityDirector.fogColorFromIbl;
      final currentFogColorR = RenderQualityDirector.fogColorR;
      final currentFogColorG = RenderQualityDirector.fogColorG;
      final currentFogColorB = RenderQualityDirector.fogColorB;
      
      // Check which lights changed (with thresholds for numeric values)
      final shadowsChanged = currentShadowsEnabled != _lastShadowsEnabled || currentShadowType != _lastShadowType;
      
      // Check if render quality settings changed
      final renderQualityChanged = currentPostProcessing != _lastPostProcessingEnabled ||
          (currentPenumbraScale - (_lastShadowPenumbraScale ?? currentPenumbraScale)).abs() > 0.01 ||
          (currentPenumbraRatio - (_lastShadowPenumbraRatioScale ?? currentPenumbraRatio)).abs() > 0.01 ||
          currentMsaa != _lastMsaaEnabled ||
          currentFxaa != _lastFxaaEnabled ||
          currentTaa != _lastTaaEnabled ||
          currentBloomEnabled != _lastBloomEnabled ||
          (currentBloomStrength - (_lastBloomStrength ?? currentBloomStrength)).abs() > 0.01 ||
          currentToneMapper != _lastToneMapperType ||
          currentFrustumCulling != _lastFrustumCullingEnabled ||
          currentFogEnabled != _lastFogEnabled ||
          (currentFogDistance - (_lastFogDistance ?? currentFogDistance)).abs() > 0.1 ||
          (currentFogCutoffDistance - (_lastFogCutoffDistance ?? currentFogCutoffDistance)).abs() > 1.0 ||
          (currentFogMaximumOpacity - (_lastFogMaximumOpacity ?? currentFogMaximumOpacity)).abs() > 0.01 ||
          (currentFogDensity - (_lastFogDensity ?? currentFogDensity)).abs() > 0.01 ||
          (currentFogHeight - (_lastFogHeight ?? currentFogHeight)).abs() > 0.1 ||
          (currentFogHeightFalloff - (_lastFogHeightFalloff ?? currentFogHeightFalloff)).abs() > 0.01 ||
          (currentFogInScatteringStart - (_lastFogInScatteringStart ?? currentFogInScatteringStart)).abs() > 0.1 ||
          (currentFogInScatteringSize - (_lastFogInScatteringSize ?? currentFogInScatteringSize)).abs() > 0.01 ||
          currentFogColorFromIbl != _lastFogColorFromIbl ||
          (currentFogColorR - (_lastFogColorR ?? currentFogColorR)).abs() > 0.01 ||
          (currentFogColorG - (_lastFogColorG ?? currentFogColorG)).abs() > 0.01 ||
          (currentFogColorB - (_lastFogColorB ?? currentFogColorB)).abs() > 0.01;
      
      if (renderQualityChanged) {
        print('🔍 Render quality change detected!');
        print('   Post: $_lastPostProcessingEnabled -> $currentPostProcessing');
        print('   Penumbra: $_lastShadowPenumbraScale -> $currentPenumbraScale');
        print('   MSAA: $_lastMsaaEnabled -> $currentMsaa');
        print('   FXAA: $_lastFxaaEnabled -> $currentFxaa');
        print('   TAA: $_lastTaaEnabled -> $currentTaa');
        print('   Bloom: $_lastBloomEnabled -> $currentBloomEnabled (${_lastBloomStrength} -> $currentBloomStrength)');
        print('   ToneMapper: $_lastToneMapperType -> $currentToneMapper');
        print('   Frustum: $_lastFrustumCullingEnabled -> $currentFrustumCulling');
        print('   Fog: $_lastFogEnabled -> $currentFogEnabled');
      }
      
      final masterBrightnessChanged = _lastMasterBrightness == null || 
          (_lastMasterBrightness! - currentMasterBrightness).abs() > 0.01;
      
      final primaryChanged = _lastPrimaryDirection?.x != currentPrimaryDirection.x ||
          _lastPrimaryDirection?.y != currentPrimaryDirection.y ||
          _lastPrimaryDirection?.z != currentPrimaryDirection.z ||
          (_lastPrimaryColorTemp == null || (_lastPrimaryColorTemp! - currentPrimaryColorTemp).abs() > 0.1) ||
          (_lastPrimaryIntensity == null || (_lastPrimaryIntensity! - currentPrimaryIntensity).abs() > 100) ||
          _lastPrimaryCastsShadows != currentPrimaryCastsShadows ||
          masterBrightnessChanged;
      
      final fillChanged = _lastFillDirection?.x != currentFillDirection.x ||
          _lastFillDirection?.y != currentFillDirection.y ||
          _lastFillDirection?.z != currentFillDirection.z ||
          (_lastFillColorTemp == null || (_lastFillColorTemp! - currentFillColorTemp).abs() > 0.1) ||
          (_lastFillIntensity == null || (_lastFillIntensity! - currentFillIntensity).abs() > 100) ||
          _lastFillCastsShadows != currentFillCastsShadows ||
          masterBrightnessChanged;
      
      final rimChanged = _lastRimDirection?.x != currentRimDirection.x ||
          _lastRimDirection?.y != currentRimDirection.y ||
          _lastRimDirection?.z != currentRimDirection.z ||
          (_lastRimColorTemp == null || (_lastRimColorTemp! - currentRimColorTemp).abs() > 0.1) ||
          (_lastRimIntensity == null || (_lastRimIntensity! - currentRimIntensity).abs() > 100) ||
          _lastRimCastsShadows != currentRimCastsShadows ||
          masterBrightnessChanged;
      
      // If nothing changed, skip the update entirely
      if (!shadowsChanged && !renderQualityChanged && !primaryChanged && !fillChanged && !rimChanged && _primaryLight != null) {
        return;
      }
      
      // Update shadow settings
      if (shadowsChanged) {
        if (currentShadowsEnabled) {
          await _viewer!.setShadowsEnabled(true);
          final shadowType = LightingDirector.getShadowTypeEnum();
          await _viewer!.setShadowType(shadowType);
        } else {
          await _viewer!.setShadowsEnabled(false);
        }
        _lastShadowsEnabled = currentShadowsEnabled;
        _lastShadowType = currentShadowType;
        print('🔄 Shadow settings updated: enabled=$currentShadowsEnabled, type=${LightingDirector.getShadowTypeEnum()}');
      }
      
      // Update render quality settings
      if (renderQualityChanged) {
        await _viewer!.setPostProcessing(currentPostProcessing);
        print('   ✅ Post-processing: $currentPostProcessing');
        
        await _viewer!.setSoftShadowOptions(currentPenumbraScale, currentPenumbraRatio);
        print('   ✅ Soft shadows: penumbra=$currentPenumbraScale, ratio=$currentPenumbraRatio');
        
        await _viewer!.setAntiAliasing(currentMsaa, currentFxaa, currentTaa);
        print('   ✅ Anti-aliasing: MSAA=$currentMsaa, FXAA=$currentFxaa, TAA=$currentTaa');
        
        await _viewer!.setBloom(currentBloomEnabled, currentBloomStrength);
        print('   ✅ Bloom: enabled=$currentBloomEnabled, strength=$currentBloomStrength');
        if (currentBloomEnabled && !currentPostProcessing) {
          print('   ⚠️  WARNING: Bloom requires post-processing to be enabled!');
        }
        if (currentBloomEnabled && currentBloomStrength < 0.3) {
          print('   ℹ️  Note: Bloom strength <0.3 may be too subtle to see');
        }
        if (currentBloomEnabled && currentBloomStrength > 3.0) {
          print('   🔥 Extreme bloom: strength=${currentBloomStrength.toStringAsFixed(1)} (may be overwhelming!)');
        }
        
        await _viewer!.setToneMapping(RenderQualityDirector.getToneMapperEnum());
        print('   ✅ Tone mapping: ${RenderQualityDirector.getToneMapperEnum()}');
        
        await _viewer!.setViewFrustumCulling(currentFrustumCulling);
        print('   ✅ Frustum culling: $currentFrustumCulling');
        
        // Fog (accessed via viewer.view)
        if (currentFogEnabled) {
          final fogOptions = FogOptions(
            enabled: true,
            distance: currentFogDistance,
            cutOffDistance: currentFogCutoffDistance,
            maximumOpacity: currentFogMaximumOpacity,
            density: currentFogDensity,
            height: currentFogHeight,
            heightFalloff: currentFogHeightFalloff,
            inScatteringStart: currentFogInScatteringStart,
            inScatteringSize: currentFogInScatteringSize,
            fogColorFromIbl: currentFogColorFromIbl,
            linearColor: Vector3(currentFogColorR, currentFogColorG, currentFogColorB),
          );
          await _viewer!.view.setFogOptions(fogOptions);
          print('   ✅ Fog: ENABLED');
          print('      Distance: $currentFogDistance → ${currentFogCutoffDistance == 1000.0 ? "∞" : currentFogCutoffDistance}');
          print('      Opacity: $currentFogMaximumOpacity, Density: $currentFogDensity');
          print('      Height: $currentFogHeight, Falloff: $currentFogHeightFalloff');
        } else if (_lastFogEnabled == true && !currentFogEnabled) {
          // Only disable if it was previously enabled
          await _viewer!.view.setFogOptions(FogOptions(enabled: false));
          print('   ✅ Fog: DISABLED');
        }
        
        _lastPostProcessingEnabled = currentPostProcessing;
        _lastShadowPenumbraScale = currentPenumbraScale;
        _lastShadowPenumbraRatioScale = currentPenumbraRatio;
        _lastMsaaEnabled = currentMsaa;
        _lastFxaaEnabled = currentFxaa;
        _lastTaaEnabled = currentTaa;
        _lastBloomEnabled = currentBloomEnabled;
        _lastBloomStrength = currentBloomStrength;
        _lastToneMapperType = currentToneMapper;
        _lastFrustumCullingEnabled = currentFrustumCulling;
        _lastFogEnabled = currentFogEnabled;
        _lastFogDistance = currentFogDistance;
        _lastFogCutoffDistance = currentFogCutoffDistance;
        _lastFogMaximumOpacity = currentFogMaximumOpacity;
        _lastFogDensity = currentFogDensity;
        _lastFogHeight = currentFogHeight;
        _lastFogHeightFalloff = currentFogHeightFalloff;
        _lastFogInScatteringStart = currentFogInScatteringStart;
        _lastFogInScatteringSize = currentFogInScatteringSize;
        _lastFogColorFromIbl = currentFogColorFromIbl;
        _lastFogColorR = currentFogColorR;
        _lastFogColorG = currentFogColorG;
        _lastFogColorB = currentFogColorB;
        
        print('🔄 Render quality update complete!');
      }
      
      // CRITICAL BUG FIX: Only recreate lights that actually changed!
      // Previously we were recreating ALL THREE lights whenever ANY light changed,
      // causing massive accumulation. Now we only recreate what changed.
      
      final List<String> updatedLights = [];
      
      if (primaryChanged || _primaryLight == null) {
        _primaryLight = LightingDirector.createPrimaryLight();
        await _viewer!.addDirectLight(_primaryLight!);
        _lastPrimaryDirection = currentPrimaryDirection;
        _lastPrimaryColorTemp = currentPrimaryColorTemp;
        _lastPrimaryIntensity = currentPrimaryIntensity;
        _lastPrimaryCastsShadows = currentPrimaryCastsShadows;
        updatedLights.add('primary[$currentPrimaryColorTemp K, ${currentPrimaryIntensity.toInt()} lux]');
      }
      
      if (fillChanged || _fillLight == null) {
        _fillLight = LightingDirector.createFillLight();
        await _viewer!.addDirectLight(_fillLight!);
        _lastFillDirection = currentFillDirection;
        _lastFillColorTemp = currentFillColorTemp;
        _lastFillIntensity = currentFillIntensity;
        _lastFillCastsShadows = currentFillCastsShadows;
        updatedLights.add('fill[$currentFillColorTemp K, ${currentFillIntensity.toInt()} lux]');
      }
      
      if (rimChanged || _rimLight == null) {
        _rimLight = LightingDirector.createRimLight();
        await _viewer!.addDirectLight(_rimLight!);
        _lastRimDirection = currentRimDirection;
        _lastRimColorTemp = currentRimColorTemp;
        _lastRimIntensity = currentRimIntensity;
        _lastRimCastsShadows = currentRimCastsShadows;
        updatedLights.add('rim[$currentRimColorTemp K, ${currentRimIntensity.toInt()} lux]');
      }
      
      _lastMasterBrightness = currentMasterBrightness;
      
      if (updatedLights.isNotEmpty) {
        print('🔄 Lights updated: ${updatedLights.join(", ")}');
      }
      
      // Note: Thermion still accumulates lights over time, but this fix dramatically reduces it
      // by only adding lights that actually changed, not all three every time.
    } catch (e) {
      print('⚠️ Error updating lighting: $e');
    }
  }
  
  /// Update camera based on current tuner values
  void _updateCameraForTuner() {
    if (_camera == null || _characterWorldPosition == null) return;
    
    // Update camera sway controller duration if breathing frequency changed
    // This ensures breathing frequency changes take immediate effect
    final newSwayDurationMs = (1000 / CameraDirector.primaryBreathing.frequency).round();
    final currentDuration = _cameraSwayController.duration;
    final currentDurationMs = currentDuration?.inMilliseconds ?? 0;
    if (currentDurationMs != newSwayDurationMs) {
      _cameraSwayController.duration = Duration(milliseconds: newSwayDurationMs);
      // Restart the controller to apply new duration
      if (!_cameraSwayController.isAnimating) {
        _cameraSwayController.reset();
        _cameraSwayController.repeat();
      }
    }
    
    // Camera position updates will happen naturally through existing camera update methods
    // since they already use CameraDirector getters which now read from tuner
    // Just trigger a camera update to apply any shot parameter changes
    _updateCameraForState();
    
    // Also update camera animation controller durations if transition speeds changed
    // These will be applied on the next transition
    // (Current transition will continue with its original duration)
  }
  
  /// Update camera exposure based on current tuner values
  /// Adjusts scene brightness by controlling aperture, shutter speed, and ISO
  Future<void> _updateCameraExposure() async {
    if (_viewer == null) return;
    
    try {
      final currentAperture = RenderQualityDirector.cameraAperture;
      final currentShutterSpeed = RenderQualityDirector.cameraShutterSpeed;
      final currentISO = RenderQualityDirector.cameraISO;
      
      // Check if exposure parameters changed (use small thresholds for floating point comparison)
      final apertureChanged = _lastCameraAperture == null || 
          (currentAperture - _lastCameraAperture!).abs() > 0.01;
      final shutterSpeedChanged = _lastCameraShutterSpeed == null ||
          (currentShutterSpeed - _lastCameraShutterSpeed!).abs() > 0.0001;  // ~1/10000 difference
      final isoChanged = _lastCameraISO == null ||
          (currentISO - _lastCameraISO!).abs() > 1.0;
      
      if (apertureChanged || shutterSpeedChanged || isoChanged) {
        final camera = await _viewer!.view.getCamera();
        await camera.setExposure(currentAperture, currentShutterSpeed, currentISO);
        
        _lastCameraAperture = currentAperture;
        _lastCameraShutterSpeed = currentShutterSpeed;
        _lastCameraISO = currentISO;
        
        print('📷 Camera exposure updated: f/${currentAperture.toStringAsFixed(1)}, 1/${(1.0/currentShutterSpeed).toStringAsFixed(0)}s, ISO ${currentISO.toStringAsFixed(0)}');
      }
    } catch (e) {
      print('⚠️ Error updating camera exposure: $e');
    }
  }
  
  /// Update rug position based on current rugYOffset value
  /// Also updates character position to stay slightly above the rug
  void _updateRugPosition() {
    if (_rugAsset == null) return;
    
    try {
      // Update the rug's Y position to match the current rugYOffset setting
      _rugAsset!.setTransform(Matrix4.identity()..translate(0.0, LightingDirector.rugYOffset, 0.0));
      
      // Also update character position to stand slightly above the rug (prevents clipping)
      // Character Y = rugYOffset (floor level) + characterHeightAboveRug (small offset)
      if (_asset != null) {
        final characterY = LightingDirector.rugYOffset + LightingDirector.characterHeightAboveRug;
        _asset!.setTransform(Matrix4.identity()..translate(0.0, characterY, 0.0));
      }
      
      print('🔄 Floor updated: Rug Y=${LightingDirector.rugYOffset}, Character Y=${LightingDirector.rugYOffset + LightingDirector.characterHeightAboveRug}');
    } catch (e) {
      print('⚠️ Could not update floor level: $e');
    }
  }
  
  /// Apply enhanced organic camera movement with multi-frequency layering
  /// Creates a living, breathing feel instead of mechanical sine waves
  /// All parameters controlled via CameraDirector
  /// FIXED: Uses accumulated phase to prevent boundary snapping
  void _updateCameraSway() {
    if (_camera == null || _currentCameraPosition == null || _characterWorldPosition == null) return;
    
    // Only apply sway during playing state (not during reactions or transitions)
    if (widget.gameState != GameState.playing) return;
    
    // Don't apply sway during camera transitions
    if (_cameraAnimationController.isAnimating) return;
    
    // Calculate delta time since last update to accumulate phases continuously
    final currentTime = _cameraSwayController.value;
    final deltaTime = currentTime - _lastSwayUpdateTime;
    
    // Handle controller wrap-around (when it repeats from 1.0 to 0.0)
    final adjustedDelta = deltaTime < 0 ? (1.0 - _lastSwayUpdateTime) + currentTime : deltaTime;
    _lastSwayUpdateTime = currentTime;
    
    // Get breathing parameters from CameraDirector
    final primaryBreath = CameraDirector.primaryBreathing;
    final drift = CameraDirector.slowDrift;
    final shake = CameraDirector.microShake;
    final intensity = CameraDirector.breathingIntensityMultiplier;
    
    // Accumulate phases continuously (no snapping at boundaries)
    // Scale by 2π to convert from normalized time to radians
    _accumulatedBreathingPhase += adjustedDelta * 2 * math.pi * primaryBreath.frequency;
    _accumulatedDriftPhase += adjustedDelta * 2 * math.pi * drift.frequency;
    _accumulatedShakePhase += adjustedDelta * 2 * math.pi * shake.frequency;
    
    // Layer 1: Primary breathing cycle (slow, rhythmic)
    final breathingX = math.sin(_accumulatedBreathingPhase) * primaryBreath.amplitude * intensity;
    final breathingY = math.cos(_accumulatedBreathingPhase * 0.7) * primaryBreath.amplitude * intensity;
    
    // Layer 2: Very slow drift (gives organic wandering feel)
    final driftX = math.sin(_accumulatedDriftPhase * 1.3) * drift.amplitude * intensity;
    final driftY = math.cos(_accumulatedDriftPhase * 0.9) * drift.amplitude * intensity;
    
    // Layer 3: Micro-shake (tiny high-frequency tremor, like human hand-held)
    final shakeX = math.sin(_accumulatedShakePhase * 3.7) * shake.amplitude * intensity;
    final shakeY = math.cos(_accumulatedShakePhase * 4.3) * shake.amplitude * intensity;
    
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
    
    // No need for manual phase drift - accumulated phases handle continuous variation naturally
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
        transitionDuration = CameraDirector.successTransitionTime;
        break;
      case GameState.failing:
        // Get shot with optional random variation
        relativePosition = CameraDirector.getVariedShot(CameraDirector.failingShot);
        transitionDuration = CameraDirector.failureTransitionTime;
        break;
      case GameState.completed:
        relativePosition = CameraDirector.getVariedShot(CameraDirector.completedShot);
        transitionDuration = CameraDirector.normalTransitionTime;
        break;
      case GameState.playing:
      default:
        relativePosition = CameraDirector.getVariedShot(CameraDirector.playingShot);
        transitionDuration = CameraDirector.normalTransitionTime;
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
      
      // Position character slightly above the rug to prevent clipping
      // Character Y = rugYOffset (floor level) + characterHeightAboveRug (small offset)
      final characterY = LightingDirector.rugYOffset + LightingDirector.characterHeightAboveRug;
      await _asset!.setTransform(Matrix4.identity()..translate(0.0, characterY, 0.0));
      print('📍 Character positioned at Y=$characterY (rug: ${LightingDirector.rugYOffset}, height above: ${LightingDirector.characterHeightAboveRug})');
      
      // ========================================================================
      // 🎨 SCENE LIGHTING SETUP (Controlled by LightingDirector)
      // ========================================================================
      // All lighting parameters are in lighting_director.dart for easy tuning
      // Edit values there and hot reload to see changes instantly!
      
      if (LightingDirector.useCustomLighting) {
        print('');
        print('═══════════════════════════════════════');
        print('🎨 LIGHTING SETUP');
        print('═══════════════════════════════════════');
        
        // APPLY RENDER QUALITY SETTINGS
        // This includes post-processing, anti-aliasing, bloom, tone mapping, shadows, etc.
        await RenderQualityDirector.applyToViewer(viewer);
        
        // LOAD SKYBOX if enabled
        if (RenderQualityDirector.skyboxEnabled) {
          try {
            await viewer.loadSkybox(RenderQualityDirector.skyboxPath);
            print('🌅 Skybox loaded: ${RenderQualityDirector.skyboxPath}');
            
            // Rotate skybox if needed
            if (RenderQualityDirector.skyboxRotation != 0.0) {
              final rotationRadians = RenderQualityDirector.skyboxRotation * (3.14159265 / 180.0);
              await viewer.rotateIbl(Matrix3.rotationY(rotationRadians));
              print('   Rotated: ${RenderQualityDirector.skyboxRotation}°');
            }
            
            // Set camera exposure for proper skybox brightness
            // Thermion default (f/16, 1/125s, ISO 100) is for bright outdoor sun
            // Our default (f/2.8, 1/125s, ISO 100) provides better skybox visibility
            // Tunable via director overlay: render.cameraAperture, render.cameraShutterSpeed, render.cameraISO
            final camera = await viewer.view.getCamera();
            await camera.setExposure(
              RenderQualityDirector.cameraAperture,      // f-stop (lower = brighter)
              RenderQualityDirector.cameraShutterSpeed,  // seconds
              RenderQualityDirector.cameraISO            // ISO (higher = brighter)
            );
            print('📷 Camera exposure set: f/${RenderQualityDirector.cameraAperture.toStringAsFixed(1)}, 1/${(1.0/RenderQualityDirector.cameraShutterSpeed).toStringAsFixed(0)}s, ISO ${RenderQualityDirector.cameraISO.toStringAsFixed(0)}');
          
          } catch (e) {
            print('⚠️  Failed to load skybox: $e');
          }
        }
        
        // LOAD IBL (Image-Based Lighting) if enabled
        if (RenderQualityDirector.iblEnabled) {
          try {
            await viewer.loadIbl(RenderQualityDirector.iblPath, intensity: RenderQualityDirector.iblIntensity);
            print('💡 IBL loaded: ${RenderQualityDirector.iblPath}');
            print('   Intensity: ${RenderQualityDirector.iblIntensity}');
          } catch (e) {
            print('⚠️  Failed to load IBL: $e');
          }
        }
        
        // ENABLE SHADOWS ON THE VIEWER (Master switch!)
        // Shadows are DISABLED by default in Thermion - must explicitly enable
        if (LightingDirector.shadowsEnabled) {
          await viewer.setShadowsEnabled(true);
          final shadowType = LightingDirector.getShadowTypeEnum();
          await viewer.setShadowType(shadowType);
          print('🌑 SHADOWS: GLOBALLY ENABLED');
          print('   Shadow Type: $shadowType');
        }
        
        // PRIMARY LIGHT: Main illumination (sun/window light from backdrop)
        _primaryLight = LightingDirector.createPrimaryLight();
        await viewer.addDirectLight(_primaryLight!);
        print('');
        print('☀️  PRIMARY LIGHT:');
        print('   Intensity: ${LightingDirector.primaryIntensity}');
        print('   Color Temp: ${LightingDirector.primaryColorTemp}K');
        print('   Direction: (${LightingDirector.primaryDirection.x.toStringAsFixed(2)}, ${LightingDirector.primaryDirection.y.toStringAsFixed(2)}, ${LightingDirector.primaryDirection.z.toStringAsFixed(2)})');
        print('   Cast Shadows: ${LightingDirector.primaryCastsShadows}');
        
        // FILL LIGHT: Softens shadows, adds detail in dark areas
        _fillLight = LightingDirector.createFillLight();
        await viewer.addDirectLight(_fillLight!);
        print('');
        print('💡 FILL LIGHT:');
        print('   Intensity: ${LightingDirector.fillIntensity}');
        print('   Color Temp: ${LightingDirector.fillColorTemp}K');
        
        // RIM LIGHT: Edge highlights for depth and separation
        _rimLight = LightingDirector.createRimLight();
        await viewer.addDirectLight(_rimLight!);
        print('');
        print('✨ RIM LIGHT:');
        print('   Intensity: ${LightingDirector.rimIntensity}');
        print('   Color Temp: ${LightingDirector.rimColorTemp}K');
        
        print('═══════════════════════════════════════');
        print('');
      }
      
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
      _rugAsset = await viewer.loadGltf(
        'file://$modifiedRugPath',
        addToScene: true,
      );
      
      // ADJUST RUG POSITION - Lower it to be nearly flush with the ground
      // The rug should be very thin, almost directly on the floor
      // Controlled by LightingDirector.rugYOffset for easy tuning
      print('📍 Adjusting rug position (Y offset: ${LightingDirector.rugYOffset})...');
      
      try {
        // Set the rug's vertical position to be nearly on the ground
        await _rugAsset!.setTransform(Matrix4.identity()..translate(0.0, LightingDirector.rugYOffset, 0.0));
        print('✅ Rug position adjusted');
      } catch (e) {
        print('⚠️ Could not adjust rug position: $e');
        print('   Rug may appear elevated - this is a known limitation');
      }
      
      print('═══════════════════════════════════════');
      print('✅ PERSONALIZED RUG LOADED SUCCESSFULLY!');
      print('   Name: "$name"');
      print('   GLB: $modifiedRugPath');
      print('   Position: (0, ${LightingDirector.rugYOffset}, 0)');
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
      decoration: RenderQualityDirector.skyboxEnabled 
        ? null  // No gradient when skybox is enabled - let the skybox show through!
        : const BoxDecoration(
            // Natural sky gradient that complements the wood floor (fallback when no skybox)
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
            decoration: RenderQualityDirector.skyboxEnabled
              ? const BoxDecoration(color: Colors.black)  // Black background while skybox loads
              : const BoxDecoration(
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
            child: const Center(
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
