import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  final void Function(double) onMotionUpdate;
  StreamSubscription<GyroscopeEvent>? _sub;
  double gyroMotion = 0.0;

  SensorService({required this.onMotionUpdate});

  void start() {
    _sub = gyroscopeEvents.listen((e) {
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      gyroMotion = gyroMotion * 0.92 + mag * 0.08;
      onMotionUpdate(gyroMotion);
    });
  }

  void stop() {
    _sub?.cancel();
  }
}
