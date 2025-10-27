import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(KnBCaptureApp(cameras: cameras));
}

class KnBCaptureApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const KnBCaptureApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KnB Capture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: LiveColorCamera(cameras: cameras),
    );
  }
}

class LiveColorCamera extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LiveColorCamera({super.key, required this.cameras});

  @override
  State<LiveColorCamera> createState() => _LiveColorCameraState();
}

class _LiveColorCameraState extends State<LiveColorCamera> {
  late CameraController _controller;
  bool _isInitialized = false;

  List<Color> _liveColors = List.filled(5, Colors.transparent);
  List<Color> _capturedColors = [];
  Timer? _updateTimer;
  final Random _rng = Random();
  final bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.low,
      enableAudio: false,
    );
    await _controller.initialize();
    await _controller.startImageStream(_processFrame);
    setState(() => _isInitialized = true);

    // Uppdatera UI-färger var 0.2 sekunder
    _updateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() {}); // Triggar UI-refresh
    });
  }

  List<Color> _frameColors = [];

  void _processFrame(CameraImage image) {
    final bytes = image.planes[0].bytes;
    final width = image.width;
    final height = image.height;

    List<Color> sampledColors = [];

    for (int i = 0; i < 5; i++) {
      int x = _rng.nextInt(width);
      int y = _rng.nextInt(height);
      int pixelIndex = y * width + x;
      int value = bytes[pixelIndex];
      sampledColors.add(Color.fromARGB(255, value, value, value));
    }

    _frameColors = sampledColors;
    _liveColors = sampledColors;
  }

  Future<void> _captureCurrentColors() async {
    if (_liveColors.any((c) => c == Colors.transparent)) return;

    setState(() {
      _capturedColors = List.from(_liveColors);
    });

    // Spara färgerna som JSON i dokumentmappen
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/captured_colors.txt');
    final jsonColors = _capturedColors
        .map((c) => {'r': c.red, 'g': c.green, 'b': c.blue})
        .toList();
    await file.writeAsString(jsonEncode(jsonColors));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Colors saved successfully!')),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Kameravyn
                CameraPreview(_controller),

                // Overlay med färg-bubblor
                ..._liveColors.asMap().entries.map((entry) {
                  final index = entry.key;
                  final color = entry.value;
                  final positions = [
                    const Offset(100, 150),
                    const Offset(220, 250),
                    const Offset(300, 200),
                    const Offset(160, 380),
                    const Offset(280, 420),
                  ];

                  return Positioned(
                    left: positions[index].dx,
                    top: positions[index].dy,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _captureCurrentColors,
        backgroundColor: Colors.brown[400],
        label: const Text("Capture"),
        icon: const Icon(Icons.camera),
      ),
    );
  }
}
