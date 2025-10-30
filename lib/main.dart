import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// 🔹 Importera rätt modulväg (den ligger i lib/screens/)
import 'screens/camera_screen.dart';

/// Startpunkt för hela Knb Capture-appen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initiera Firebase innan kamerorna laddas
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Initiera kameror innan appen startas.
  final List<CameraDescription> cameras = await availableCameras();

  // ✅ Kör appen och injicera kamerorna i huvudwidgeten.
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Knb Capture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      // Skicka kameradata till din huvudskärm
      home: CameraScreen(cameras: cameras),
    );
  }
}
