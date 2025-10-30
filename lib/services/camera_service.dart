import 'package:camera/camera.dart';

class CameraService {
  static Future<CameraController> initializeCamera(List<CameraDescription> cameras) async {
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    return controller;
  }
}
