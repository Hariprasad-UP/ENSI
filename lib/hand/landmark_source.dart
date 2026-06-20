import 'hand_tracker.dart';
import 'landmarks.dart';

/// Internal SPI: anything that produces a stream of [Landmarks].
///
/// The real implementation is [MediaPipeBridge] (FFI → native MediaPipe). Tests
/// inject a fake to drive the pipeline deterministically with no camera/native.
abstract class LandmarkSource {
  /// True if a working backend (native lib + camera) is present.
  bool get available;

  Stream<Landmarks> get landmarks;

  Future<void> start(HandTrackerConfig config);
  Future<void> stop();
  Future<void> dispose();
}
