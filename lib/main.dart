import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:ui' as ui;

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
  bool _isCaptured = false;
  bool _manualPause = false;
  bool _autoPause = false;

  ui.Image? _capturedImage;

  List<Color> _colors = [];
  List<Offset> _positions = [];
  List<Color> _capturedColors = [];
  List<Offset> _capturedPositions = [];

  final int _sampleCount = 5;
  final Random _rand = Random();
  final double cameraVisibleFraction = 0.80;

  // Gyro & stillhet
  double _gyroMotion = 0;
  double _stillTimer = 0;
  StreamSubscription? _gyroSub;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _listenGyro();
  }

  void _listenGyro() {
    _gyroSub = gyroscopeEvents.listen((GyroscopeEvent event) {
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _gyroMotion = (_gyroMotion * 0.9) + (magnitude * 0.1);

      if (_gyroMotion > 0.15 && _autoPause) {
        _autoPause = false;
        debugPrint("🔓 Rörelse upptäckt – scanning återupptas");
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
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      if (_positions.isEmpty) {
        for (int i = 0; i < _sampleCount; i++) {
          _positions.add(Offset(_rand.nextDouble(), _rand.nextDouble() * 0.8));
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
        cx = cx.clamp(0, width - 1);
        cy = cy.clamp(0, height - 1);

        double bestScore = 0;
        int bestX = cx;
        int bestY = cy;
        Color bestColor = _colors[i];

        for (int dx = -20; dx <= 20; dx += 5) {
          for (int dy = -20; dy <= 20; dy += 5) {
            int nx = (cx + dx).clamp(0, width - 1);
            int ny = (cy + dy).clamp(0, height - 1);
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

      if (avgChange < 0.02 && _gyroMotion < 0.05) {
        _stillTimer += 0.1;
        if (_stillTimer > 3.0) {
          _autoPause = true;
          _stillTimer = 0;
          debugPrint("⏸ Auto-paus (kameran stilla)");
        }
      } else {
        _stillTimer = 0;
      }

      _positions = newPositions;
      _colors = newColors;

      if (mounted) setState(() {});
    }
  }

  void _toggleManualPause() {
    setState(() {
      _manualPause = !_manualPause;
      debugPrint(_manualPause ? "🧊 Manuell paus" : "▶️ Fortsätter skanna");
    });
  }

  Future<void> _captureColors() async {
    if (!_isInitialized || _controller == null) return;

    try {
      final xfile = await _controller!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final image = await decodeImageFromList(bytes);

      setState(() {
        _capturedImage = image;
        _capturedColors = List.from(_colors);
        _capturedPositions = List.from(_positions);
        _isCaptured = true;
      });
      debugPrint("📸 Stillbild tagen och färger låsta");
    } catch (e) {
      debugPrint("❌ Kunde inte ta bild: $e");
    }
  }

  void _resetCapture() {
    setState(() {
      _isCaptured = false;
      _capturedImage = null;
      _capturedColors.clear();
      _capturedPositions.clear();
    });
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorsToShow = _isCaptured ? _capturedColors : _colors;
    final positionsToShow = _isCaptured ? _capturedPositions : _positions;

    return GestureDetector(
      onTap: _toggleManualPause,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // 📸 Kamera-del (80%)
            Expanded(
              flex: 8,
              child: Stack(
                children: [
                  if (_isCaptured && _capturedImage != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ImagePainter(_capturedImage!),
                      ),
                    )
                  else if (_isInitialized)
                    Positioned.fill(
                      child: CameraPreview(_controller!),
                    )
                  else
                    const Center(
                        child: CircularProgressIndicator(color: Colors.white)),

                  if (_isInitialized || _isCaptured)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: List.generate(colorsToShow.length, (i) {
                            if (i >= positionsToShow.length) return const SizedBox();
                            final pos = positionsToShow[i];
                            final dx = pos.dx * constraints.maxWidth;
                            final dy = pos.dy * constraints.maxHeight;
                            return Positioned(
                              left: dx.clamp(0, constraints.maxWidth - 50),
                              top: dy.clamp(0, constraints.maxHeight - 50),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 33),
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
                ],
              ),
            ),

            // 🎨 UI-del (20%)
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.only(bottom: 25),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Färgpalett
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _colors
                          .map(
                            (c) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    // Knappar
                    Row(
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
                  ],
                ),
              ),
            ),
          ],
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
