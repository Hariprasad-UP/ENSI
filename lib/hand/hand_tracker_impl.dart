import 'dart:async';

import 'cursor_mapper.dart';
import 'gesture.dart';
import 'hand_tracker.dart';
import 'landmark_source.dart';
import 'landmarks.dart';
import 'mediapipe_bridge.dart';

/// Concrete [HandTracker]: pulls [Landmarks] from a [LandmarkSource] (MediaPipe
/// native by default; injectable for tests), runs the gesture recognizer and
/// cursor mapper, and emits [HandPointer]s. Screen bounds are supplied by the
/// caller (from the platform display geometry) so the mapper stays pure.
class HandTrackerImpl implements HandTracker {
  final LandmarkSource _source;
  final double screenLeft, screenTop, screenWidth, screenHeight;

  final _out = StreamController<HandPointer>.broadcast();
  GestureRecognizer? _gesture;
  CursorMapper? _mapper;
  StreamSubscription<Landmarks>? _sub;
  bool _running = false;

  HandTrackerImpl({
    LandmarkSource? source,
    required this.screenWidth,
    required this.screenHeight,
    this.screenLeft = 0,
    this.screenTop = 0,
  }) : _source = source ?? MediaPipeBridge();

  @override
  bool get isAvailable => _source.available;

  @override
  Stream<HandPointer> get pointers => _out.stream;

  @override
  Future<void> start(HandTrackerConfig config) async {
    if (_running) return;
    if (!_source.available) {
      throw HandTrackerException(
          'hand tracking unavailable — native library/model not found '
          '(build it per docs/HAND_TRACKING_BUILD_PLAN.md Task 0)');
    }
    _gesture = GestureRecognizer(config);
    _mapper = CursorMapper(config,
        screenLeft: screenLeft,
        screenTop: screenTop,
        screenWidth: screenWidth,
        screenHeight: screenHeight);
    _sub = _source.landmarks.listen(_onLandmarks, onError: _out.addError);
    await _source.start(config);
    _running = true;
  }

  void _onLandmarks(Landmarks lm) {
    final g = _gesture!.update(lm);
    if (!_out.isClosed) _out.add(_mapper!.map(lm, g));
  }

  @override
  Future<void> calibrate() async {
    // v1: the default active region works; richer calibration is future work.
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _source.dispose();
    if (!_out.isClosed) await _out.close();
  }
}
