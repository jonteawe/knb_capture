import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  bool _isLocked = false;

  int _frameCounter = 0;
  double _stabilityTimer = 0;

  List<Color> _colors = [];
  List<Offset> _positions = [];

  final int _sampleCount = 5;
  final Random _rand = Random();

  final double cameraVisibleFraction = 0.80;

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
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processFrame);
      setState(() => _isInitialized = true);
      debugPrint("✅ Kamera initierad och aktiv.");
    } catch (e) {
      debugPrint("❌ Fel vid initiering: $e");
    }
  }

  double _colorDistance(Color a, Color b) {
    return sqrt(pow(a.red - b.red, 2) +
            pow(a.green - b.green, 2) +
            pow(a.blue - b.blue, 2)) /
        441.67;
  }

  double _colorInterest(int r, int g, int b) {
    final double brightness = (r + g + b) / 3.0;
    final double contrast = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
    final double saturation = contrast / (brightness + 1);
    return (contrast * 1.3 + saturation * 100 + (255 - (brightness - 128).abs())) / 510.0;
  }

  void _processFrame(CameraImage image) {
    if (_isLocked) return;

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
          _colors.add(Colors.transparent);
        }
      }

      final List<Color> newColors = List.from(_colors);
      final List<Offset> newPositions = List.from(_positions);

      double totalColorChange = 0.0;

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

        for (int dx = -20; dx <= 20; dx += 4) {
          for (int dy = -20; dy <= 20; dy += 4) {
            int nx = (cx + dx).clamp(minX, maxX);
            int ny = (cy + dy).clamp(minY, maxY);
            int idx = (ny * width + nx) * 4;
            if (idx + 3 >= bytes.length) continue;

            final b = bytes[idx];
            final g = bytes[idx + 1];
            final r = bytes[idx + 2];
            double score = _colorInterest(r, g, b);
            final c = Color.fromARGB(255, r, g, b);

            for (int j = 0; j < _colors.length; j++) {
              if (j == i) continue;
              score -= max(0, 0.3 - _colorDistance(c, _colors[j])) * 1.5;
            }

            if (score > bestScore) {
              bestScore = score;
              bestX = nx;
              bestY = ny;
              bestColor = c;
            }
          }
        }

        double snapSpeed = min(1.0, max(0.6, bestScore));
        Offset target = Offset(bestX / width, bestY / height);
        newPositions[i] = Offset(
          pos.dx + (target.dx - pos.dx) * snapSpeed,
          pos.dy + (target.dy - pos.dy) * snapSpeed,
        );

        newColors[i] = Color.lerp(_colors[i], bestColor, 0.8)!;
        totalColorChange += _colorDistance(_colors[i], newColors[i]);
      }

      // 🔒 Stillhet-detektion
      double avgChange = totalColorChange / _colors.length;

      if (avgChange < 0.02) {
        _stabilityTimer += 0.1;
        if (_stabilityTimer >= 3.0) {
          debugPrint("🔒 Låst färger (stilla)");
          _isLocked = true;
          _stabilityTimer = 0;
        }
      } else {
        _stabilityTimer = 0;
      }

      _positions = newPositions;
      _colors = newColors;

      if (shouldRebuild && mounted) setState(() {});
    }
  }

  void _unlock() {
    setState(() {
      _isLocked = false;
      _stabilityTimer = 0;
      debugPrint("🔓 Rörelse – färger uppdateras igen.");
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _unlock, // tillåter att du "väcker" appen manuellt också
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isInitialized)
              FractionallySizedBox(
                heightFactor: cameraVisibleFraction,
                alignment: Alignment.topCenter,
                child: CameraPreview(_controller!),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            if (_isInitialized)
              LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: List.generate(_colors.length, (i) {
                      if (i >= _positions.length) return const SizedBox();
                      final pos = _positions[i];
                      final dx = pos.dx * constraints.maxWidth;
                      final dy =
                          pos.dy * constraints.maxHeight * cameraVisibleFraction;
                      return Positioned(
                        left: dx - 25,
                        top: dy - 25,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 25),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _colors[i],
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

            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height:
                    MediaQuery.of(context).size.height * (1 - cameraVisibleFraction),
                color: Colors.black,
                child: const Center(
                  child: Text(
                    "Knb Capture",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
