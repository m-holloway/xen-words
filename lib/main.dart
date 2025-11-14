import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'controllers/game_controller.dart';
import 'services/audio_player_service.dart';
import 'services/director_tuner.dart';
import 'services/sherpa_recognizer.dart';
import 'services/preferences_service.dart';
import 'services/profile_service.dart';
import 'utils/app_logger.dart';
import 'widgets/game_screen.dart';
import 'widgets/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_selector_screen.dart';
import 'widgets/lighting_director.dart';
import 'widgets/camera_director.dart';
import 'widgets/render_quality_director.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure logging based on build mode
  // In release mode: Minimal logging (info level and above)
  // In debug mode: Verbose logging (debug level and above)
  // In profile mode: Moderate logging (info level and above)
  AppLogger.configureForEnvironment(
    isProduction: kReleaseMode,
    level: kReleaseMode ? Level.info : (kProfileMode ? Level.info : Level.debug),
  );
  
  AppLogger.system.i('🚀 App starting in ${kReleaseMode ? 'RELEASE' : (kProfileMode ? 'PROFILE' : 'DEBUG')} mode');
  
  // Layout debugging can be enabled for troubleshooting layout issues
  // See LAYOUT.md for details on using layout debugging
  // AppLogger.enableLayoutDebug = true;
  
  // Initialize DirectorTuner and register parameters
  LightingDirector.registerParameters();
  CameraDirector.registerParameters();
  RenderQualityDirector.registerParameters();
  
  // Load saved defaults from previous sessions
  await DirectorTuner.instance.loadDefaults();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  runApp(const XenWordsApp());
}

class XenWordsApp extends StatefulWidget {
  const XenWordsApp({Key? key}) : super(key: key);

  @override
  State<XenWordsApp> createState() => _XenWordsAppState();
}

class _XenWordsAppState extends State<XenWordsApp> {
  Key _appKey = UniqueKey();
  
  void _restartApp() {
    AppLogger.system.emoji('🔄', '_restartApp: Restarting app with new key...');
    setState(() {
      _appKey = UniqueKey();
    });
    AppLogger.system.emoji('✅', '_restartApp: App restart triggered');
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.system.d('XenWordsApp.build: ENTRY - Building app widget tree (key: $_appKey)');
    return ChangeNotifierProvider(
      key: _appKey,
      create: (context) {
        AppLogger.system.d('ChangeNotifierProvider.create: Creating GameController...');
        final controller = GameController(
          audioService: AudioPlayerService(),
          speechRecognizer: SherpaRecognizer(),  // Using Sherpa-ONNX with vocabulary restriction
        );
        AppLogger.system.emoji('✅', 'ChangeNotifierProvider.create: GameController created');
        return controller;
      },
      // REMOVED Consumer wrapper - MaterialApp no longer rebuilds on notifyListeners()!
      child: _AppRouter(
        appKey: _appKey,
        onRestart: _restartApp,
      ),
    );
  }
}

/// Separate widget for routing logic to prevent rebuilds
class _AppRouter extends StatelessWidget {
  final Key appKey;
  final VoidCallback onRestart;
  
  const _AppRouter({
    required this.appKey,
    required this.onRestart,
  });

  Future<Map<String, dynamic>> _checkAppState() async {
    AppLogger.system.d('_checkAppState: ENTRY - Checking app state...');
    
    AppLogger.system.d('_checkAppState: Checking onboarding status...');
    final onboardingComplete = await PreferencesService().isOnboardingComplete();
    AppLogger.system.d('_checkAppState: Onboarding complete = $onboardingComplete');
    
    AppLogger.system.d('_checkAppState: Getting active profile ID...');
    final activeProfileId = await ProfileService().getActiveProfileId();
    AppLogger.system.d('_checkAppState: Active profile ID = $activeProfileId');
    
    AppLogger.system.d('_checkAppState: Checking guest mode...');
    final isGuest = await ProfileService().isGuestMode();
    AppLogger.system.d('_checkAppState: Is guest = $isGuest');
    
    final hasActiveProfile = activeProfileId != null || isGuest;
    AppLogger.system.d('_checkAppState: Has active profile = $hasActiveProfile');
    
    AppLogger.system.emoji('✅', '_checkAppState: EXIT - State checked successfully');
    return {
      'onboardingComplete': onboardingComplete,
      'hasActiveProfile': hasActiveProfile,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Get controller WITHOUT listening (no Consumer/listen:true)
    final controller = Provider.of<GameController>(context, listen: false);
    
    return MaterialApp(
      title: 'Xen Words',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(appKey),
        future: _checkAppState(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          final state = snapshot.data ?? {};
          final onboardingComplete = state['onboardingComplete'] ?? false;
          final hasActiveProfile = state['hasActiveProfile'] ?? false;
          
          if (!onboardingComplete) {
            AppLogger.system.d('MaterialApp.home: Showing OnboardingScreen');
            return OnboardingScreen(
              onComplete: () {
                AppLogger.system.emoji('🎓', 'OnboardingScreen complete, restarting...');
                onRestart();
              },
            );
          }
          
          if (!hasActiveProfile) {
            AppLogger.system.d('MaterialApp.home: Showing ProfileSelectorScreen');
            return ProfileSelectorScreen(
              onProfileSelected: () {
                AppLogger.system.emoji('👤', 'Profile selected, restarting...');
                onRestart();
              },
            );
          }
          
          // Has active profile - show game
          AppLogger.system.emoji('🎮', 'MaterialApp.home: Showing GameScreen (NO CONSUMER REBUILD!)');
          return SplashScreen(
            initializationFuture: controller.initializationComplete,
            onModelLoaded: controller.onSplashModelLoaded,
            child: const GameScreen(),
          );
        },
      ),
    );
  }
}
