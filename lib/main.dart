import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isBusy = false;
  bool _isAppPaused = false;
  Timer? _uiUpdateTimer;
  List<Color> _colors = List.generate(5, (_) => Colors.transparent);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiUpdateTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS kräver att kameran stoppas när appen pausas
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _isAppPaused = true;
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _isAppPaused) {
      _isAppPaused = false;
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!Platform.isIOS) {
      debugPrint("❌ iOS krävs för denna version.");
      return;
    }

    try {
      final camera = widget.cameras.first;

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888, // ✅ nödvändigt på iOS
      );

      // initiera kameran med timeout
      await _controller!.initialize().timeout(const Duration(seconds: 5));

      if (!mounted) return;
      setState(() => _isInitialized = true);

      debugPrint("✅ Kamera initierad på iOS");

      // starta bildström
      await _controller!.startImageStream(_processFrame);

      // uppdatera UI var 0.25 sekund
      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && !_isBusy) setState(() {});
      });
    } catch (e) {
      debugPrint("❌ Fel vid kamera-initiering: $e");
      _showCameraErrorDialog(e.toString());
    }
  }

  void _processFrame(CameraImage image) {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final rand = Random();
      _colors = List.generate(
        5,
        (_) => Color.fromRGBO(
          rand.nextInt(255),
          rand.nextInt(255),
          rand.nextInt(255),
          1.0,
        ),
      );
    } catch (e) {
      debugPrint("⚠️ Fel vid frame-analys: $e");
    } finally {
      _isBusy = false;
    }
  }

  void _showCameraErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Kamera-fel"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isInitialized && _controller != null)
              CameraPreview(_controller!)
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Overlay med fem färgbubblor
            Positioned(
              bottom: 90,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _colors
                    .map(
                      (c) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                            )
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            // Capture-knapp
            Positioned(
              bottom: 20,
              child: ElevatedButton(
                onPressed: () {
                  debugPrint("📸 Tar färgdata (placeholder just nu)");
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: const Text(
                  "Capture Colors",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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
