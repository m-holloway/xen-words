import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'controllers/game_controller.dart';
import 'services/audio_player_service.dart';
import 'services/director_tuner.dart';
import 'services/sherpa_recognizer.dart';
import 'utils/app_logger.dart';
import 'widgets/game_screen.dart';
import 'widgets/splash_screen.dart';
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

class XenWordsApp extends StatelessWidget {
  const XenWordsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final controller = GameController(
          audioService: AudioPlayerService(),
          speechRecognizer: SherpaRecognizer(),  // Using Sherpa-ONNX with vocabulary restriction
        );
        return controller;
      },
      child: Consumer<GameController>(
        builder: (context, controller, child) {
          return MaterialApp(
            title: 'Xen Words',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primarySwatch: Colors.blue,
              useMaterial3: true,
              fontFamily: 'sans-serif',
            ),
            home: SplashScreen(
              initializationFuture: controller.initializationComplete,
              onModelLoaded: controller.onSplashModelLoaded,
              child: const GameScreen(),
            ),
          );
        },
      ),
    );
  }
}
