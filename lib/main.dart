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
  List<Offset> _positions = [];
  List<Offset> _capturedPositions = [];

  final int _sampleCount = 5;
  final Random _rand = Random();

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

      _updateTimer =
          Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (mounted && !_isFrozen) setState(() {});
      });
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  // Hjälpfunktion för att mäta färgavvikelse (snabb luminansbaserad skillnad)
  double _colorDiff(int r1, int g1, int b1, int r2, int g2, int b2) {
    return ((r1 - r2).abs() + (g1 - g2).abs() + (b1 - b2).abs()) / 3.0;
  }

  void _processFrame(CameraImage image) {
    if (_isFrozen) return;
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      // initiera zoner första gången
      if (_positions.isEmpty) {
        _positions = [
          const Offset(0.3, 0.4),
          const Offset(0.5, 0.4),
          const Offset(0.7, 0.4),
          const Offset(0.4, 0.6),
          const Offset(0.6, 0.6),
        ];
      }

      List<Color> newColors = [];
      List<Offset> newPositions = [];

      for (var pos in _positions) {
        int cx = (pos.dx * width).toInt();
        int cy = (pos.dy * height).toInt();
        int bestX = cx, bestY = cy;
        double bestContrast = 0;
        Color centerColor = Colors.transparent;

        // ta centrumfärgen
        int idx = (cy * width + cx) * 4;
        if (idx + 3 < bytes.length) {
          final b = bytes[idx];
          final g = bytes[idx + 1];
          final r = bytes[idx + 2];
          centerColor = Color.fromARGB(255, r, g, b);
        }

        // sök runt i liten cirkel efter stark kontrast
        for (int dx = -5; dx <= 5; dx++) {
          for (int dy = -5; dy <= 5; dy++) {
            int nx = cx + dx;
            int ny = cy + dy;
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            int nidx = (ny * width + nx) * 4;
            if (nidx + 3 >= bytes.length) continue;
            final nb = bytes[nidx];
            final ng = bytes[nidx + 1];
            final nr = bytes[nidx + 2];
            double diff = _colorDiff(
                centerColor.red, centerColor.green, centerColor.blue,
                nr, ng, nb);
            if (diff > bestContrast) {
              bestContrast = diff;
              bestX = nx;
              bestY = ny;
            }
          }
        }

        // använd bästa punkten
        int fidx = (bestY * width + bestX) * 4;
        final fb = bytes[fidx];
        final fg = bytes[fidx + 1];
        final fr = bytes[fidx + 2];
        newColors.add(Color.fromARGB(255, fr, fg, fb));

        // flytta smidigt (lerp)
        Offset target = Offset(bestX / width, bestY / height);
        Offset smooth = Offset(
          pos.dx + (target.dx - pos.dx) * 0.2,
          pos.dy + (target.dy - pos.dy) * 0.2,
        );
        newPositions.add(smooth);
      }

      _colors = newColors;
      _positions = newPositions;
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
      const SnackBar(content: Text("📸 Färger fångade!")),
    );
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

          // Dynamiska färgikoner med smooth rörelse
          if (_isInitialized)
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: List.generate(colorsToShow.length, (i) {
                    if (i >= positionsToShow.length) return const SizedBox();
                    final pos = positionsToShow[i];
                    final dx = pos.dx * constraints.maxWidth;
                    final dy = pos.dy * constraints.maxHeight;
                    return Positioned(
                      left: dx - 25,
                      top: dy - 25,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
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

          // Capture/Reset UI
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text("Capture Colors",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
