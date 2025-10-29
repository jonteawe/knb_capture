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
  bool _manualPause = false;
  bool _autoPause = false;
  bool _isCaptured = false;

  double _stillTimer = 0;
  int _frameCounter = 0;

  List<Color> _colors = [];
  List<Offset> _positions = [];
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];

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
    if (_manualPause || _autoPause || _isCaptured) return;

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
      double totalChange = 0;

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
        totalChange += _colorDistance(_colors[i], newColors[i]);
      }

      double avgChange = totalChange / _colors.length;

      // 🔒 Pausa efter 3 sek stillhet
      if (avgChange < 0.02) {
        _stillTimer += 0.1;
        if (_stillTimer > 3.0) {
          _autoPause = true;
          _stillTimer = 0;
          debugPrint("⏸ Auto-paused efter stillhet");
        }
      } else {
        _stillTimer = 0;
      }

      // 🔓 Starta igen om rörelse upptäcks
      if (avgChange > 0.08 && _autoPause) {
        _autoPause = false;
        debugPrint("▶️ Rörelse upptäckt – fortsätter scanna");
      }

      _positions = newPositions;
      _colors = newColors;
      if (shouldRebuild && mounted) setState(() {});
    }
  }

  void _toggleManualPause() {
    setState(() {
      _manualPause = !_manualPause;
      debugPrint(_manualPause ? "🧊 Manuell paus" : "▶️ Fortsätter skanna");
    });
  }

  Future<void> _captureColors() async {
    if (!_isInitialized) return;
    setState(() {
      _capturedColors = List.from(_colors);
      _capturedPositions = List.from(_positions);
      _isCaptured = true;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("📸 Färger fångade!")));
  }

  void _resetCapture() {
    setState(() {
      _isCaptured = false;
      _capturedColors.clear();
      _capturedPositions.clear();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorsToShow =
        _isCaptured ? _capturedColors : _colors;
    final positionsToShow =
        _isCaptured ? _capturedPositions : _positions;

    return GestureDetector(
      onTap: _toggleManualPause,
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
                    children: List.generate(colorsToShow.length, (i) {
                      if (i >= positionsToShow.length) return const SizedBox();
                      final pos = positionsToShow[i];
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

            // UI under kameran
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height *
                    (1 - cameraVisibleFraction),
                color: Colors.black,
                padding: const EdgeInsets.only(bottom: 40),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _isCaptured ? null : _captureColors,
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
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 20),
                      if (_isCaptured)
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
      ),
    );
  }
}
