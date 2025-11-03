import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/camera_service.dart';
import '../services/sensor_service.dart';
import '../services/color_save_service.dart'; // 🔹 Ny modul för att spara färger
import '../widgets/palette_bar.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/image_painter.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // ---------- TUNABLES ----------
  static const int kProbeCount = 5;
  static const double kPaletteBarFrac = 0.14;
  static const double kBottomUIFrac = 0.16;
  static const double kCameraFrac = 1 - kPaletteBarFrac - kBottomUIFrac;
  static const double kProbeDiameter = 40;
  static const double kMinProbeSepPx = 56;
  static const double kScoreStep = 4;
  static const int kSearchSize = 20;
  static const double kSnapStrength = 0.85;
  static const double kColorLerp = 0.8;
  static const double kAvgColorDeltaThresh = 0.010;
  static const double kGyroStillThresh = 0.20;
  static const double kStillSecondsNeeded = 3.0;
  // -------------------------------

  CameraController? _controller;
  bool _isInitialized = false;
  bool _manualPause = false;
  bool _autoPause = false;
  bool _isCaptured = false;

  ui.Image? _capturedImage;
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];

  List<Color> _colors = [];
  List<Offset> _positions = [];

  double _gyroMotion = 0.0;
  double _stillTimer = 0.0;
  FlashMode _flashMode = FlashMode.off;

  late SensorService _sensorService;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _sensorService = SensorService(onMotionUpdate: _onGyroMotion);
    _sensorService.start();
  }

  void _onGyroMotion(double motion) {
    _gyroMotion = motion;
    if (_autoPause && motion > kGyroStillThresh * 1.25) {
      setState(() => _autoPause = false);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _controller = await CameraService.initializeCamera(widget.cameras);
      await _controller!.startImageStream(_processFrame);
      await _controller!.setFlashMode(_flashMode);

      _positions = List.generate(
        kProbeCount,
        (i) => Offset(0.2 + i * (0.6 / (kProbeCount - 1)), 0.55),
      );
      _colors = List.generate(kProbeCount, (_) => Colors.transparent);

      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('❌ Kamera-fel: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    });

    try {
      await _controller!.setFlashMode(_flashMode);
      debugPrint('🔦 Flash mode: $_flashMode');
    } catch (e) {
      debugPrint('⚠️ Kunde inte ändra flashläge: $e');
    }
  }

  double _colorDistance(Color a, Color b) {
    return sqrt(pow(a.red - b.red, 2) +
            pow(a.green - b.green, 2) +
            pow(a.blue - b.blue, 2)) /
        441.67;
  }

  double _colorInterest(int r, int g, int b) {
    final brightness = (r + g + b) / 3.0;
    final contrast = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
    final saturation = contrast / (brightness + 1);
    return (contrast * 1.3 + saturation * 100 + (255 - (brightness - 128).abs())) / 510.0;
  }

  void _processFrame(CameraImage image) {
    if (_manualPause || _autoPause || _isCaptured) return;
    if (!Platform.isIOS || image.format.group != ImageFormatGroup.bgra8888) return;

    final bytes = image.planes.first.bytes;
    final width = image.width;
    final height = image.height;

    final minY = (height * kPaletteBarFrac).toInt();
    final maxY = (height * (kPaletteBarFrac + kCameraFrac)).toInt();
    final minX = (width * 0.05).toInt();
    final maxX = (width * 0.95).toInt();

    final newColors = List<Color>.from(_colors);
    final newPositions = List<Offset>.from(_positions);
    double totalDelta = 0.0;

    for (int i = 0; i < _positions.length; i++) {
      final pos = _positions[i];

      int cx = (pos.dx * width).toInt().clamp(minX, maxX);
      int cy = (pos.dy * height).toInt().clamp(minY, maxY);

      double bestScore = -1e9;
      int bestX = cx, bestY = cy;
      Color bestC = _colors[i];

      for (int dx = -kSearchSize; dx <= kSearchSize; dx += kScoreStep.toInt()) {
        for (int dy = -kSearchSize; dy <= kSearchSize; dy += kScoreStep.toInt()) {
          final nx = (cx + dx).clamp(minX, maxX);
          final ny = (cy + dy).clamp(minY, maxY);
          final idx = (ny * width + nx) * 4;
          if (idx + 3 >= bytes.length) continue;

          final b = bytes[idx];
          final g = bytes[idx + 1];
          final r = bytes[idx + 2];
          final c = Color.fromARGB(255, r, g, b);

          double score = _colorInterest(r, g, b);
          for (int j = 0; j < _colors.length; j++) {
            if (j == i) continue;
            score -= max(0, 0.28 - _colorDistance(c, _colors[j])) * 1.7;
          }

          if (score > bestScore) {
            bestScore = score;
            bestX = nx;
            bestY = ny;
            bestC = c;
          }
        }
      }

      final tgt = Offset(bestX / width, bestY / height);
      const lerp = kSnapStrength;
      newPositions[i] = Offset(
        pos.dx + (tgt.dx - pos.dx) * lerp,
        pos.dy + (tgt.dy - pos.dy) * lerp,
      );

      final oldC = _colors[i];
      final outC = Color.lerp(oldC, bestC, kColorLerp)!;
      newColors[i] = outC;
      totalDelta += _colorDistance(oldC, outC);
    }

    _applyRepulsionAndClamp(newPositions);

    _positions = newPositions;
    _colors = newColors;
    if (mounted) setState(() {});

    final avgDelta = totalDelta / _colors.length.clamp(1, 999);
    if (avgDelta < kAvgColorDeltaThresh && _gyroMotion < kGyroStillThresh) {
      _stillTimer += 0.1;
      if (_stillTimer >= kStillSecondsNeeded) {
        _autoPause = true;
        _stillTimer = 0;
      }
    } else {
      _stillTimer = 0;
    }
  }

  void _applyRepulsionAndClamp(List<Offset> pos) {
    for (int iter = 0; iter < 2; iter++) {
      for (int i = 0; i < pos.length; i++) {
        for (int j = i + 1; j < pos.length; j++) {
          final p1 = pos[i];
          final p2 = pos[j];

          final size = MediaQuery.of(context).size;
          final wPx = size.width;
          final hPx = size.height * kCameraFrac;

          final dx = (p2.dx - p1.dx) * wPx;
          final dy = (p2.dy - p1.dy) * hPx;
          final dist = sqrt(dx * dx + dy * dy);

          if (dist < kMinProbeSepPx && dist > 0) {
            final push = (kMinProbeSepPx - dist) / kMinProbeSepPx * 0.35;
            final nx = dx / dist, ny = dy / dist;
            pos[i] = Offset(
              (p1.dx - nx * push / wPx).clamp(0.0, 1.0),
              (p1.dy - ny * push / hPx).clamp(0.0, 1.0),
            );
            pos[j] = Offset(
              (p2.dx + nx * push / wPx).clamp(0.0, 1.0),
              (p2.dy + ny * push / hPx).clamp(0.0, 1.0),
            );
          }
        }
      }
    }

    for (int i = 0; i < pos.length; i++) {
      pos[i] = Offset(
        pos[i].dx.clamp(0.05, 0.95),
        pos[i].dy.clamp(kPaletteBarFrac + 0.02, kPaletteBarFrac + kCameraFrac - 0.02),
      );
    }
  }

  void _toggleManualPause() => setState(() => _manualPause = !_manualPause);

  Future<void> _captureColors() async {
    if (!_isInitialized || _controller == null) return;
    try {
      await _controller!.setFlashMode(_flashMode);
      final xfile = await _controller!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final img = await decodeImageFromList(bytes);

      setState(() {
        _capturedImage = img;
        _capturedColors = List.from(_colors);
        _capturedPositions = List.from(_positions);
        _isCaptured = true;
      });
    } catch (e) {
      debugPrint('❌ takePicture error: $e');
    }
  }

  void _resetCapture() {
    setState(() {
      _isCaptured = false;
      _capturedImage = null;
      _capturedColors.clear();
      _capturedPositions.clear();
      _manualPause = false;
      _autoPause = false;
    });
  }

  @override
  void dispose() {
    _sensorService.stop();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showingColors = _isCaptured ? _capturedColors : _colors;
    final showingPositions = _isCaptured ? _capturedPositions : _positions;

    return GestureDetector(
      onTap: _toggleManualPause,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Knb Capture'),
          backgroundColor: Colors.black,
          elevation: 0,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: Drawer(
          backgroundColor: Colors.grey[900],
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.blueAccent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: const [
                    Text(
                      'Knb Capture',
                      style: TextStyle(color: Colors.white, fontSize: 22),
                    ),
                    Text(
                      'Användarmeny',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white),
                title: const Text('Logga ut', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    Navigator.of(context).pushReplacementNamed('/');
                  }
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            PaletteBar(colors: showingColors),
            Expanded(
              flex: (kCameraFrac * 1000).round(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isCaptured && _capturedImage != null)
                    CustomPaint(painter: ImagePainter(_capturedImage!))
                  else if (_isInitialized)
                    CameraPreview(_controller!)
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  if (_isInitialized || _isCaptured)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return Stack(
                          children: List.generate(showingPositions.length, (i) {
                            final pos = showingPositions[i];
                            final nx = pos.dx;
                            final ny = (pos.dy - kPaletteBarFrac) / kCameraFrac;
                            final dx = nx * w;
                            final dy = ny * h;
                            return Positioned(
                              left: dx - kProbeDiameter / 2,
                              top: dy - kProbeDiameter / 2,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 20),
                                width: kProbeDiameter,
                                height: kProbeDiameter,
                                decoration: BoxDecoration(
                                  color: showingColors.isNotEmpty
                                      ? showingColors[i]
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.35),
                                      blurRadius: 6,
                                    )
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (_isCaptured)
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: ElevatedButton.icon(
                  onPressed: () => ColorSaveService.saveColorsToFirebase(context, _capturedColors),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Save Colors to Cloud'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                ),
              ),
            BottomBar(
              onCapture: _isCaptured ? null : _captureColors,
              onReset: _isCaptured ? _resetCapture : null,
              onToggleFlash: _toggleFlash,
              isFlashOn: _flashMode == FlashMode.torch,
            ),
          ],
        ),
      ),
    );
  }
}
