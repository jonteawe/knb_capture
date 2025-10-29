import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
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
  int _frameCounter = 0;

  List<Color> _colors = List.filled(5, Colors.black);
  List<Offset> _positions = [];
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];
  XFile? _capturedImage;

  final int _sampleCount = 5;
  final Random _rand = Random();
  final double cameraVisibleFraction = 0.80;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return;

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
      await _controller!.startImageStream(_processFrame);
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("❌ Camera init failed: $e");
    }
  }

  double _colorDistance(Color a, Color b) {
    return sqrt(pow(a.red - b.red, 2) +
            pow(a.green - b.green, 2) +
            pow(a.blue - b.blue, 2)) /
        441.67;
  }

  // 🧠 Updated: Handles dark tones better and boosts subtle contrast
  double _colorInterest(int r, int g, int b) {
    final double brightness = (r + g + b) / 3.0;
    final double contrast = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
    final double saturation = contrast / (brightness + 1);

    // Boost contrast if image is dark
    double lowLightBoost = 1 + ((255 - brightness) / 200);
    double score = (contrast * 1.2 + saturation * 90) * lowLightBoost;

    // Normalize, prevent too low values in total black
    return (score / 300).clamp(0.0, 1.0);
  }

  void _processFrame(CameraImage image) {
    if (_isFrozen) return;
    _frameCounter++;
    bool shouldRebuild = _frameCounter % 2 == 0;

    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      final int minY = (height * (1 - cameraVisibleFraction) / 2).toInt();
      final int maxY = (height * (1 - (1 - cameraVisibleFraction) / 2)).toInt();
      final int minX = (width * 0.1).toInt();
      final int maxX = (width * 0.9).toInt();

      if (_positions.isEmpty) {
        for (int i = 0; i < _sampleCount; i++) {
          _positions.add(Offset(0.2 + i * 0.15, 0.5));
        }
      }

      final List<Color> newColors = List.from(_colors);
      final List<Offset> newPositions = List.from(_positions);

      for (int i = 0; i < _positions.length; i++) {
        final pos = _positions[i];
        int cx = (pos.dx * width).toInt();
        int cy = (pos.dy * height).toInt();
        cx = cx.clamp(minX, maxX);
        cy = cy.clamp(minY, maxY);

        double bestScore = 0;
        int bestX = cx;
        int bestY = cy;
        Color bestColor = _colors[i];

        // 5x5 cluster scan
        for (int dx = -20; dx <= 20; dx += 5) {
          for (int dy = -20; dy <= 20; dy += 5) {
            int nx = (cx + dx).clamp(minX, maxX);
            int ny = (cy + dy).clamp(minY, maxY);
            double rSum = 0, gSum = 0, bSum = 0;
            int count = 0;

            for (int ox = -2; ox <= 2; ox++) {
              for (int oy = -2; oy <= 2; oy++) {
                int xx = (nx + ox).clamp(minX, maxX);
                int yy = (ny + oy).clamp(minY, maxY);
                int idx = (yy * width + xx) * 4;
                if (idx + 3 >= bytes.length) continue;
                bSum += bytes[idx].toDouble();
                gSum += bytes[idx + 1].toDouble();
                rSum += bytes[idx + 2].toDouble();
                count++;
              }
            }

            if (count == 0) continue;
            int r = (rSum / count).toInt();
            int g = (gSum / count).toInt();
            int b = (bSum / count).toInt();

            double score = _colorInterest(r, g, b);
            final c = Color.fromARGB(255, r, g, b);

            for (int j = 0; j < _colors.length; j++) {
              if (j == i) continue;
              score -= max(0, 0.2 - _colorDistance(c, _colors[j])) * 1.5;
            }

            if (score > bestScore) {
              bestScore = score;
              bestX = nx;
              bestY = ny;
              bestColor = c;
            }
          }
        }

        double snapSpeed = min(1.0, max(0.7, bestScore));
        Offset target = Offset(bestX / width, bestY / height);
        newPositions[i] = Offset(
          pos.dx + (target.dx - pos.dx) * snapSpeed,
          pos.dy + (target.dy - pos.dy) * snapSpeed,
        );
        newColors[i] = Color.lerp(_colors[i], bestColor, 0.8)!;
      }

      _positions = newPositions;
      _colors = newColors;
      if (shouldRebuild && mounted) setState(() {});
    }
  }

  Future<void> _captureColors() async {
    if (!_isInitialized || _isFrozen) return;
    try {
      await _controller!.stopImageStream();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await _controller!.takePicture();
      await file.saveTo(path);

      setState(() {
        _capturedImage = XFile(path);
        _capturedColors = List.from(_colors);
        _capturedPositions = List.from(_positions);
        _isFrozen = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("📸 Colors captured!")));
    } catch (e) {
      debugPrint("❌ Capture failed: $e");
    }
  }

  Future<void> _resetCapture() async {
    setState(() {
      _isFrozen = false;
      _capturedImage = null;
      _capturedColors.clear();
      _capturedPositions.clear();
    });
    await _controller!.startImageStream(_processFrame);
  }

  @override
  void dispose() {
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
          // Camera preview or frozen image
          if (_isInitialized)
            FractionallySizedBox(
              heightFactor: cameraVisibleFraction,
              alignment: Alignment.topCenter,
              child: _capturedImage == null
                  ? CameraPreview(_controller!)
                  : Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Top color palette bar (always visible)
          SafeArea(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 80,
              color: Colors.black.withOpacity(0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: colorsToShow.map((c) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Moving color dots on camera
          if (_isInitialized)
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: List.generate(colorsToShow.length, (i) {
                    if (i >= positionsToShow.length) return const SizedBox();
                    final pos = positionsToShow[i];
                    final dx = pos.dx * constraints.maxWidth;
                    final dy = pos.dy * constraints.maxHeight * cameraVisibleFraction;
                    return Positioned(
                      left: dx - 25,
                      top: dy - 25,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 50),
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

          // Bottom buttons
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * (1 - cameraVisibleFraction),
              color: Colors.black,
              padding: const EdgeInsets.only(bottom: 40),
              child: Center(
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
            ),
          ),
        ],
      ),
    );
  }
}
