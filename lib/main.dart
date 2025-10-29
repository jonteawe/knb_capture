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
  List<Offset> _velocities = [];

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

      _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && !_isFrozen) setState(() {});
      });
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
    }
  }

  double _colorDiff(Color a, Color b) {
    return ((a.red - b.red).abs() +
            (a.green - b.green).abs() +
            (a.blue - b.blue).abs()) /
        3.0;
  }

  double _colorIntensity(int r, int g, int b) {
    final double brightness = (r + g + b) / 3.0;
    final double saturation = (max(r, max(g, b)) - min(r, min(g, b))).toDouble();
    return (saturation * 1.2 + (255 - (brightness - 127.5).abs())) / 510.0;
  }

  void _processFrame(CameraImage image) {
    if (_isFrozen) return;
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      final width = image.width;
      final height = image.height;

      // initiera positioner & hastigheter
      if (_positions.isEmpty) {
        for (int i = 0; i < _sampleCount; i++) {
          _positions.add(Offset(0.25 + 0.1 * i, 0.5));
          _velocities.add(Offset.zero);
          _colors.add(Colors.transparent);
        }
      }

      List<Color> newColors = List.from(_colors);

      for (int i = 0; i < _positions.length; i++) {
        final pos = _positions[i];
        int cx = (pos.dx * width).clamp(0, width - 1).toInt();
        int cy = (pos.dy * height).clamp(0, height - 1).toInt();
        int idx = (cy * width + cx) * 4;
        if (idx + 3 >= bytes.length) continue;

        final b = bytes[idx];
        final g = bytes[idx + 1];
        final r = bytes[idx + 2];
        final color = Color.fromARGB(255, r, g, b);
        newColors[i] = color;

        // mäta färgkvalitet
        double quality = _colorIntensity(r, g, b);

        // undvik att likna andra färger för mycket
        double similarityPenalty = 0;
        for (int j = 0; j < _colors.length; j++) {
          if (j == i) continue;
          double diff = _colorDiff(color, _colors[j]);
          similarityPenalty += (diff < 40 ? (1 - diff / 40) : 0);
        }

        double interest = (quality - similarityPenalty * 0.5).clamp(0, 1);

        // Ju sämre kvalitet → större chans att flytta
        if (_rand.nextDouble() > interest) {
          double dx = (_rand.nextDouble() - 0.5) * 0.05;
          double dy = (_rand.nextDouble() - 0.5) * 0.05;

          // Lägg till liten slumpmässig "impuls"
          _velocities[i] = Offset(
            (_velocities[i].dx + dx) * 0.7,
            (_velocities[i].dy + dy) * 0.7,
          );
        } else {
          // Annars sakta ner rörelsen
          _velocities[i] = _velocities[i] * 0.8;
        }

        // Ny smidig position
        Offset newPos = Offset(
          (pos.dx + _velocities[i].dx).clamp(0.05, 0.95),
          (pos.dy + _velocities[i].dy).clamp(0.05, 0.95),
        );

        // Smooth lerp
        _positions[i] = Offset(
          pos.dx + (newPos.dx - pos.dx) * 0.3,
          pos.dy + (newPos.dy - pos.dy) * 0.3,
        );
      }

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

          // Dynamiska färgikoner
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

          // UI-knappar
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
