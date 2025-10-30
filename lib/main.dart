import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
      title: 'Knb Capture',
      theme: ThemeData.dark(),
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
  // ---------- T U N E A B L E S ----------
  static const int kProbeCount = 5;

  // UI layout (andel av hela höjden)
  static const double kPaletteBarFrac = 0.14;   // topp-palett
  static const double kBottomUIFrac  = 0.16;   // botten-kontroller
  static const double kCameraFrac    = 1 - kPaletteBarFrac - kBottomUIFrac;

  // Ikon/sond-utseende
  static const double kProbeDiameter = 40;     // mindre, lik Adobe
  static const double kMinProbeSepPx = 56;     // min inbördes avstånd

  // Rörelse/sampling
  static const double kScoreStep     = 4;      // sökgrid (px) ~ snabb
  static const int    kSearchSize    = 20;     // ± radie (px)
  static const double kSnapStrength  = 0.85;   // hur snabbt dras mot mål
  static const double kColorLerp     = 0.8;    // färg-lågpass

  // Auto-pause (mindre känslig)
  static const double kAvgColorDeltaThresh = 0.010; // kräver ännu mindre färgförändring
  static const double kGyroStillThresh     = 0.20;  // ~70% trögare på rörelse
  static const double kStillSecondsNeeded  = 3.0;

  // ---------------------------------------

  CameraController? _controller;
  bool _isInitialized = false;

  // pausflaggor och capture
  bool _manualPause = false;
  bool _autoPause   = false;
  bool _isCaptured  = false;

  ui.Image? _capturedImage;
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];

  // live data
  List<Color> _colors = [];
  List<Offset> _positions = [];

  // rörelsedetektion
  StreamSubscription? _gyroSub;
  double _gyroMotion = 0.0;
  double _stillTimer = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _listenGyro();
  }

  void _listenGyro() {
    _gyroSub = gyroscopeEvents.listen((e) {
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      // kraftigare lågpass – jämnare
      _gyroMotion = _gyroMotion * 0.92 + mag * 0.08;

      // om auto-paus aktiv och vi rör luren ordentligt -> återuppta
      if (_autoPause && _gyroMotion > kGyroStillThresh * 1.25) {
        setState(() => _autoPause = false);
      }
    });
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

      // initiera probers startlägen i mittenbandet
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
    // viktning: kontrast + mättnad + “mitt”-ljus
    return (contrast * 1.3 + saturation * 100 + (255 - (brightness - 128).abs())) / 510.0;
  }

  void _processFrame(CameraImage image) {
    if (_manualPause || _autoPause || _isCaptured) return;
    if (!Platform.isIOS || image.format.group != ImageFormatGroup.bgra8888) {
      return; // iOS-optimerad väg (BGRA)
    }

    final bytes  = image.planes.first.bytes;
    final width  = image.width;
    final height = image.height;

    // Beskär bort palett och botten-UI ur skanningen
    final minY = (height * kPaletteBarFrac).toInt();
    final maxY = (height * (kPaletteBarFrac + kCameraFrac)).toInt();
    final minX = (width * 0.05).toInt();
    final maxX = (width * 0.95).toInt();

    final newColors    = List<Color>.from(_colors);
    final newPositions = List<Offset>.from(_positions);
    double totalDelta  = 0.0;

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

          // Undvik att flera väljer samma färg: öka spridning
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

      // snabb, men mjuk “snap” mot mål
      final tgt = Offset(bestX / width, bestY / height);
      const lerp = kSnapStrength;
      newPositions[i] = Offset(
        pos.dx + (tgt.dx - pos.dx) * lerp,
        pos.dy + (tgt.dy - pos.dy) * lerp,
      );

      // färg-lågpass
      final oldC = _colors[i];
      final outC = Color.lerp(oldC, bestC, kColorLerp)!;
      newColors[i] = outC;

      // för stillhetsdetektion
      totalDelta += _colorDistance(oldC, outC);
    }

    // inbördes repulsion + clamp inom skanningsfönster
    _applyRepulsionAndClamp(newPositions);

    // uppdatera
    _positions = newPositions;
    _colors    = newColors;
    if (mounted) setState(() {});

    // auto-pause om nästan stilla (färgmässigt + gyro)
    final avgDelta = totalDelta / _colors.length.clamp(1, 999);
    if (avgDelta < kAvgColorDeltaThresh && _gyroMotion < kGyroStillThresh) {
      _stillTimer += 0.1; // ~ var 100 ms
      if (_stillTimer >= kStillSecondsNeeded) {
        _autoPause = true;
        _stillTimer = 0;
      }
    } else {
      _stillTimer = 0;
    }
  }

  void _applyRepulsionAndClamp(List<Offset> pos) {
    // repulsion i pixelkoordinater
    for (int iter = 0; iter < 2; iter++) {
      for (int i = 0; i < pos.length; i++) {
        for (int j = i + 1; j < pos.length; j++) {
          final p1 = pos[i];
          final p2 = pos[j];

          // räkna i “skanningsytans” pixelrum (höjd=bart kCameraFrac)
          final size = MediaQuery.of(context).size;
          final wPx = size.width;
          final hPx = size.height * kCameraFrac;

          final dx = (p2.dx - p1.dx) * wPx;
          final dy = (p2.dy - p1.dy) * hPx;
          final dist = sqrt(dx * dx + dy * dy);

          if (dist < kMinProbeSepPx && dist > 0) {
            final push = (kMinProbeSepPx - dist) / kMinProbeSepPx * 0.35;
            final nx = dx / dist, ny = dy / dist;
            // flytta isär i normaliserade koordinater
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

    // clampa inom skanningsfönstret (normaliserat)
    for (int i = 0; i < pos.length; i++) {
      pos[i] = Offset(
        pos[i].dx.clamp(0.05, 0.95),
        pos[i].dy.clamp(kPaletteBarFrac + 0.02, kPaletteBarFrac + kCameraFrac - 0.02),
      );
    }
  }

  // ----- UI-händelser -----

  void _toggleManualPause() {
    setState(() => _manualPause = !_manualPause);
  }

  Future<void> _captureColors() async {
    if (!_isInitialized || _controller == null) return;
    try {
      final xfile = await _controller!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final img   = await decodeImageFromList(bytes);

      setState(() {
        _capturedImage    = img;
        _capturedColors   = List.from(_colors);
        _capturedPositions= List.from(_positions);
        _isCaptured       = true;
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
      _autoPause   = false;
    });
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ----- R E N D E R -----

  @override
  Widget build(BuildContext context) {
    final showingColors   = _isCaptured ? _capturedColors   : _colors;
    final showingPositions= _isCaptured ? _capturedPositions: _positions;

    return GestureDetector(
      onTap: _toggleManualPause,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // TOPP: Palett (utanför kameran)
            _PaletteBar(colors: showingColors),

            // MITT: Kamera eller stillbild + prober
            Expanded(
              flex: (kCameraFrac * 1000).round(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isCaptured && _capturedImage != null)
                    CustomPaint(painter: _ImagePainter(_capturedImage!))
                  else if (_isInitialized)
                    CameraPreview(_controller!)
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),

                  // Proberna – håll dem inom “mitt”-ytan
                  if (_isInitialized || _isCaptured)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return Stack(
                          children: List.generate(showingPositions.length, (i) {
                            final pos = showingPositions[i];
                            // mappa normaliserad pos till mitt-ytan
                            final nx = pos.dx;
                            final ny = (pos.dy - kPaletteBarFrac) / kCameraFrac;
                            final dx = nx * w;
                            final dy = ny * h;
                            return Positioned(
                              left: dx - kProbeDiameter / 2,
                              top:  dy - kProbeDiameter / 2,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 20),
                                width:  kProbeDiameter,
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

            // BOTTEN: kontroller (utanför kameran)
            _BottomBar(
              onCapture: _isCaptured ? null : _captureColors,
              onReset:   _isCaptured ? _resetCapture : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- W I D G E T S ----------------

class _PaletteBar extends StatelessWidget {
  const _PaletteBar({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final items = (colors.isEmpty ? List<Color>.filled(5, Colors.transparent) : colors)
        .take(5)
        .toList()
      ..addAll(List<Color>.filled(max(0, 5 - (colors.length)), Colors.transparent));

    return SizedBox(
      height: MediaQuery.of(context).size.height * _CameraScreenState.kPaletteBarFrac,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: items.map((c) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({this.onCapture, this.onReset});
  final VoidCallback? onCapture;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * _CameraScreenState.kBottomUIFrac,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.only(bottom: 28),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: onCapture,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text(
                  'Capture Colors',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 18),
              if (onReset != null)
                ElevatedButton(
                  onPressed: onReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) => false;
}
