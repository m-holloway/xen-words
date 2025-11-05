import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'controllers/game_controller.dart';
import 'services/audio_player_service.dart';
import 'services/speech_to_text_recognizer.dart';
import 'widgets/game_screen.dart';

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
      create: (context) => GameController(
        audioService: AudioPlayerService(),
        speechRecognizer: SpeechToTextRecognizer(),
      ),
      child: MaterialApp(
        title: 'Xen Words',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          fontFamily: 'sans-serif',
        ),
        home: const GameScreen(),
      ),
    );
  }
}
