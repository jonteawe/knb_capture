import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Hanterar gyroskopdata och uppdaterar rörelseenergin till UI:t.
/// Anpassad för nya Flutter-versioner (ersätter `gyroscopeEvents` med `gyroscopeEventStream()`).
class SensorService {
  final void Function(double motion) onMotionUpdate;

  StreamSubscription<GyroscopeEvent>? _sub;
  double gyroMotion = 0.0;

  SensorService({required this.onMotionUpdate});

  /// Startar gyroskoplyssnaren.
  void start() {
    _sub = gyroscopeEventStream().listen((e) {
      // Beräkna rörelseenergi (magnitud)
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

      // Lågpassfilter (mjukar ut rörelsen)
      gyroMotion = gyroMotion * 0.92 + mag * 0.08;

      // Skicka uppdateringen till huvudlogiken
      onMotionUpdate(gyroMotion);
    });
  }

  /// Stoppar strömmen (viktigt vid dispose)
  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
