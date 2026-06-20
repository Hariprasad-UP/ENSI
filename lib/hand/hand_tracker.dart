import 'dart:ui' show Rect;

/// Gesture emitted alongside each pointer sample.
enum HandGesture { none, click, dragStart, drag, dragEnd }

/// One emitted pointer sample — already smoothed and mapped to screen pixels.
class HandPointer {
  final double x, y; // absolute local-screen pixels
  final bool present;
  final HandGesture gesture;
  final double confidence; // 0..1

  const HandPointer({
    required this.x,
    required this.y,
    required this.present,
    required this.gesture,
    required this.confidence,
  });
}

/// Tunable configuration for the tracker (defaults are sensible for 640×480).
class HandTrackerConfig {
  final int targetFps;

  /// Sub-rectangle of the camera frame (normalized 0..1) mapped to the screen.
  /// A margin avoids forcing the user to reach the frame edges.
  final Rect activeRegion;

  /// Mirror X (selfie view) so moving the hand right moves the cursor right.
  final bool mirrorX;

  /// Pinch hysteresis as a ratio of hand span (smaller = more pinched).
  final double pinchOnThreshold, pinchOffThreshold;

  /// 1€ filter parameters.
  final double minCutoff, beta;

  /// Camera selection / capture format.
  final int cameraIndex, frameWidth, frameHeight;

  const HandTrackerConfig({
    this.targetFps = 30,
    this.activeRegion = const Rect.fromLTWH(0.15, 0.15, 0.7, 0.7),
    this.mirrorX = true,
    this.pinchOnThreshold = 0.30,
    this.pinchOffThreshold = 0.45,
    this.minCutoff = 1.0,
    this.beta = 0.007,
    this.cameraIndex = 0,
    this.frameWidth = 640,
    this.frameHeight = 480,
  });
}

/// Thrown when the tracker can't run (e.g. native bridge / camera unavailable).
class HandTrackerException implements Exception {
  final String message;
  HandTrackerException(this.message);
  @override
  String toString() => 'HandTrackerException: $message';
}

/// Public hand-tracking contract. The concrete implementation
/// ([HandTrackerImpl]) is swappable (MediaPipe native today, sidecar fallback)
/// without the rest of ENSI knowing.
abstract class HandTracker {
  Future<void> start(HandTrackerConfig config);
  Stream<HandPointer> get pointers;
  Future<void> calibrate();
  Future<void> stop();
  Future<void> dispose();

  /// Whether a working backend is present (native lib + camera). When false,
  /// [start] throws [HandTrackerException].
  bool get isAvailable;
}
