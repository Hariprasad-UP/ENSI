import 'dart:math' as math;
import 'dart:typed_data';

/// A 3D point in normalized image space (x,y in 0..1; z relative depth).
class Point3 {
  final double x, y, z;
  const Point3(this.x, this.y, this.z);
}

/// One frame of 21 MediaPipe hand landmarks plus presence/handedness/timestamp.
///
/// Landmark indices follow MediaPipe Hands: 0 = wrist, 4 = thumb tip,
/// 8 = index tip, 9 = middle-finger MCP. `xyz` is length 63 (21 × x,y,z).
class Landmarks {
  final Float32List xyz; // 63 = 21 landmarks × 3
  final double presence; // 0..1
  final int handedness; // 0 = left, 1 = right
  final int tsUs; // capture timestamp, microseconds

  const Landmarks(this.xyz,
      {required this.presence, required this.handedness, required this.tsUs});

  factory Landmarks.fromList(List<double> v,
      {required double presence, int handedness = 1, required int tsUs}) {
    assert(v.length >= 63, 'expected 63 floats (21x3), got ${v.length}');
    return Landmarks(Float32List.fromList(v),
        presence: presence, handedness: handedness, tsUs: tsUs);
  }

  Point3 point(int i) => Point3(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);

  Point3 get wrist => point(0);
  Point3 get thumbTip => point(4);
  Point3 get indexTip => point(8);
  Point3 get middleMcp => point(9);

  /// Thumb-tip↔index-tip distance, normalized by hand span (wrist↔middle MCP)
  /// so the pinch threshold is independent of how close the hand is to the
  /// camera. Smaller = more pinched.
  double get pinchDistance {
    final span = _dist(wrist, middleMcp);
    final d = _dist(thumbTip, indexTip);
    return span <= 1e-6 ? d : d / span;
  }

  static double _dist(Point3 a, Point3 b) {
    final dx = a.x - b.x, dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
