import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Försök ladda kameror innan appen startar
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
      home: CameraScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
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
  Timer? _updateTimer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    // ✅ Kör bara på iOS och Android
    if (!(Platform.isIOS || Platform.isAndroid)) {
      debugPrint("❌ Kamera stöds ej på denna plattform");
      return;
    }

    try {
      final camera = widget.cameras.first;

      // ⚙️ Viktigt: använd BGRA för iOS (Android använder YUV)
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processFrame);

      setState(() => _isInitialized = true);

      // Uppdatera UI-färger var 0.2 sekunder
      _updateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });

      debugPrint("✅ Kamera initierad och streaming startad");
    } catch (e) {
      debugPrint("❌ Fel vid initiering av kamera: $e");
    }
  }

  void _processFrame(CameraImage image) {
    // Här kan du lägga till din färglogik
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: !_isInitialized
            ? const CircularProgressIndicator(color: Colors.white)
            : CameraPreview(_controller!),
      ),
    );
  }
}
