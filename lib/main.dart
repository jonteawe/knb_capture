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
  List<Offset> _positions = [];
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];

  final int _sampleCount = 5;
  final Random _rand = Random();
  final double _motionSmoothness = 0.25;

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
        ResolutionPreset.high,
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

      _updateTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (mounted && !_isFrozen) setState(() {});
      });
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  double _colorDistance(Color a, Color b) {
    return sqrt(pow(a.red - b.red, 2) +
            pow(a.green - b.green, 2) +
            pow(a.blue - b.blue, 2)) /
        441.67;
  }

  double _colorQuality(int r, int g, int b) {
    double brightness = (r + g + b) / 3.0;
    double contrast = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
    return ((contrast * 1.5) + (255 - (brightness - 127.5).abs())) / 510.0;
  }

  void _processFrame(CameraImage image) {
    if (_isFrozen) return;
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      if (_positions.isEmpty) {
        // Fördela initiala punkter jämnt
        for (int i = 0; i < _sampleCount; i++) {
          _positions.add(Offset(0.2 + i * 0.15, 0.5));
          _colors.add(Colors.transparent);
        }
      }

      List<Color> newColors = List.from(_colors);
      List<Offset> newPositions = List.from(_positions);

      for (int i = 0; i < _positions.length; i++) {
        final pos = _positions[i];
        int cx = (pos.dx * width).toInt();
        int cy = (pos.dy * height).toInt();
        cx = cx.clamp(0, width - 1);
        cy = cy.clamp(0, height - 1);

        int bestX = cx;
        int bestY = cy;
        double bestScore = 0;
        Color bestColor = _colors[i];

        // Scanna litet område (lokal färgdetektion)
        for (int dx = -8; dx <= 8; dx += 2) {
          for (int dy = -8; dy <= 8; dy += 2) {
            int nx = (cx + dx).clamp(0, width - 1);
            int ny = (cy + dy).clamp(0, height - 1);
            int idx = (ny * width + nx) * 4;
            if (idx + 3 >= bytes.length) continue;

            final b = bytes[idx];
            final g = bytes[idx + 1];
            final r = bytes[idx + 2];
            double q = _colorQuality(r, g, b);

            // Färger som är för lika andra får lite lägre poäng
            for (int j = 0; j < _colors.length; j++) {
              if (j == i) continue;
              double diff = _colorDistance(Color.fromARGB(255, r, g, b), _colors[j]);
              if (diff < 0.15) q *= 0.7;
            }

            if (q > bestScore) {
              bestScore = q;
              bestX = nx;
              bestY = ny;
              bestColor = Color.fromARGB(255, r, g, b);
            }
          }
        }

        // Sätt ny smidig position mot bästa färgområdet
        Offset target = Offset(bestX / width, bestY / height);
        newPositions[i] = Offset(
          pos.dx + (target.dx - pos.dx) * _motionSmoothness,
          pos.dy + (target.dy - pos.dy) * _motionSmoothness,
        );

        // Om färgen knappt ändrats → stanna kvar
        double colorChange = _colorDistance(bestColor, _colors[i]);
        if (colorChange > 0.05) {
          newColors[i] = Color.lerp(_colors[i], bestColor, 0.4)!;
        }
      }

      _positions = newPositions;
      _colors = newColors;
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

          // Placera färgcirklar exakt där färgen hittats
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
                        duration: const Duration(milliseconds: 80),
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: colorsToShow[i],
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
                    );
                  }),
                );
              },
            ),

          // Capture / Reset
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
