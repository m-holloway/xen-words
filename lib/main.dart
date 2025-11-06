import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'controllers/game_controller.dart';
import 'services/audio_player_service.dart';
import 'services/sherpa_recognizer.dart';
import 'widgets/game_screen.dart';
import 'widgets/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
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
