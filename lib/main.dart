import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ladda kameror innan appen startar
  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Kunde inte hitta kameror: $e");
  }

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
  Timer? _uiTimer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    // Kör endast på iOS/Android
    if (!(Platform.isIOS || Platform.isAndroid)) {
      debugPrint("Kamera stöds ej på denna plattform");
      return;
    }

    try {
      final camera = widget.cameras.first;

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      // Liten delay hjälper iOS att stabilisera sessionen
      await Future.delayed(const Duration(milliseconds: 200));

      await _controller!.startImageStream(_processFrame);

      if (!mounted) return;
      setState(() => _isInitialized = true);

      // Håll UI levande (om vi vill visa något overlay senare)
      _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });

      debugPrint("Kamera initierad och streaming startad");
    } catch (e) {
      debugPrint("Fel vid initiering av kamera: $e");
    }
  }

  void _processFrame(CameraImage image) {
    // Här lägger vi färglogik i nästa steg
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onCapturePressed() async {
    // Nästa steg: frysa nuvarande frame, extrahera färger, spara txt, etc.
    debugPrint("Capture Colors pressed");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Kamera-preview
          if (_isInitialized && _controller != null)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Capture-knapp som overlay längst ner
          Positioned(
            bottom: 24,
            child: ElevatedButton(
              onPressed: _onCapturePressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                "Capture Colors",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
