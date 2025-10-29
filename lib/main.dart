import 'dart:async';
import 'dart:io';
import 'dart:math';
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
  bool _isFrozen = false;
  Timer? _updateTimer;

  List<Color> _colors = [];
  List<Color> _capturedColors = [];
  List<Offset> _positions = []; // Bildpositioner för varje färg
  List<Offset> _capturedPositions = []; // Sparade positioner efter capture

  final int _sampleCount = 5; // Antal färgprover

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

      _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && !_isFrozen) setState(() {});
      });
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  void _processFrame(CameraImage image) {
    if (_isFrozen) return;
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;
      final rand = Random();

      List<Color> extractedColors = [];
      List<Offset> extractedPositions = [];

      for (int i = 0; i < _sampleCount; i++) {
        // Slumpa punkt i bildens koordinater
        int x = rand.nextInt(width);
        int y = rand.nextInt(height);
        int pixelIndex = (y * width + x) * 4;

        if (pixelIndex + 3 < bytes.length) {
          final b = bytes[pixelIndex];
          final g = bytes[pixelIndex + 1];
          final r = bytes[pixelIndex + 2];
          extractedColors.add(Color.fromARGB(255, r, g, b));

          // Spara relativ position (0–1)
          extractedPositions.add(Offset(x / width, y / height));
        }
      }

      _colors = extractedColors;
      _positions = extractedPositions;
    }
  }

  Future<void> _captureColors() async {
    if (!_isInitialized) return;

    setState(() {
      _capturedColors = List.from(_colors);
      _capturedPositions = List.from(_positions);
      _isFrozen = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("📸 Färger fångade!"),
        duration: Duration(seconds: 1),
      ),
    );

    debugPrint("🎨 Captured colors: $_capturedColors");
  }

  void _resetCapture() {
    setState(() {
      _isFrozen = false;
      _capturedColors.clear();
      _capturedPositions.clear();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorsToShow = _isFrozen ? _capturedColors : _colors;
    final positionsToShow = _isFrozen ? _capturedPositions : _positions;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Dynamiska färgikoner
          if (_isInitialized)
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: List.generate(colorsToShow.length, (i) {
                    final pos = positionsToShow[i];
                    final dx = pos.dx * constraints.maxWidth;
                    final dy = pos.dy * constraints.maxHeight;

                    return Positioned(
                      left: dx - 25,
                      top: dy - 25,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: colorsToShow[i],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),

          // Capture & Reset
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isFrozen ? null : _captureColors,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "Capture Colors",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 20),
                if (_isFrozen)
                  ElevatedButton(
                    onPressed: _resetCapture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text("Reset"),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
