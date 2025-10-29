import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("⚠️ Kunde inte hitta kameror: $e");
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Knb Capture",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CameraScreen(cameras: cameras),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  Timer? _colorTimer;
  List<Color> _colors = List.generate(5, (_) => Colors.transparent);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    // Endast iOS eller Android stöds
    if (!(Platform.isIOS || Platform.isAndroid)) {
      debugPrint("❌ Kamera stöds ej på denna plattform.");
      return;
    }

    try {
      final camera = widget.cameras.first;

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888 // iOS kräver BGRA8888
            : ImageFormatGroup.yuv420, // Android-standard
      );

      await _controller!.initialize();
      // iOS fix: kort delay efter init
      await Future.delayed(const Duration(milliseconds: 200));

      await _controller!.startImageStream(_processFrame);

      setState(() => _isInitialized = true);
      debugPrint("✅ Kamera initierad och aktiv.");

      // uppdatera UI var 0.25 sek
      _colorTimer =
          Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  void _processFrame(CameraImage image) {
    // Enkel simulering av färg-analys (Adobe-Capture-stil)
    final rand = Random();
    _colors = List.generate(
      5,
      (_) => Color.fromRGBO(
        rand.nextInt(255),
        rand.nextInt(255),
        rand.nextInt(255),
        1.0,
      ),
    );
  }

  @override
  void dispose() {
    _colorTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Kamera-preview
          if (_isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Färg-bubblor (overlay)
          Positioned(
            bottom: 90,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _colors
                  .map(
                    (c) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Capture-knapp
          Positioned(
            bottom: 20,
            child: ElevatedButton(
              onPressed: () {
                debugPrint("📸 Färger fångade (logik läggs till senare).");
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                "Capture Colors",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
