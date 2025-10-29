import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

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

  bool _captureRequested = false;
  List<Color> _lastCapturedColors = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      debugPrint("❌ Kamera stöds ej på denna plattform.");
      return;
    }

    try {
      final camera = widget.cameras.first;

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await Future.delayed(const Duration(milliseconds: 200));
      await _controller!.startImageStream(_processFrame);

      setState(() => _isInitialized = true);
      debugPrint("✅ Kamera initierad och aktiv.");

      _colorTimer =
          Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  void _processFrame(CameraImage image) {
    // Endast BGRA8888 (iOS) hanteras här
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      final stepX = max(1, width ~/ 10);
      final stepY = max(1, height ~/ 10);

      final random = Random();
      final List<Color> extracted = [];

      for (int i = 0; i < 5; i++) {
        final x = random.nextInt(width ~/ stepX) * stepX;
        final y = random.nextInt(height ~/ stepY) * stepY;
        final pixelIndex = (y * width + x) * 4;
        if (pixelIndex + 3 < bytes.length) {
          final b = bytes[pixelIndex];
          final g = bytes[pixelIndex + 1];
          final r = bytes[pixelIndex + 2];
          extracted.add(Color.fromARGB(255, r, g, b));
        }
      }

      _colors = extracted;
      if (_captureRequested) {
        _lastCapturedColors = List.from(extracted);
        _captureRequested = false;
        debugPrint("📸 Sparade färger: $_lastCapturedColors");
      }
    }
  }

  @override
  void dispose() {
    _colorTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _captureColors() {
    _captureRequested = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Captured colors!"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (_isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

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

          Positioned(
            bottom: 20,
            child: ElevatedButton(
              onPressed: _captureColors,
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
