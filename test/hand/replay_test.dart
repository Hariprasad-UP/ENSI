import 'dart:async';

import 'package:ensi/hand/hand_tracker.dart';
import 'package:ensi/hand/hand_tracker_impl.dart';
import 'package:ensi/hand/landmark_source.dart';
import 'package:ensi/hand/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic source — feed a scripted landmark stream, no camera/native.
class _FakeSource implements LandmarkSource {
  final _c = StreamController<Landmarks>.broadcast();
  @override
  bool get available => true;
  @override
  Stream<Landmarks> get landmarks => _c.stream;
  @override
  Future<void> start(HandTrackerConfig config) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    if (!_c.isClosed) await _c.close();
  }
  void emit(Landmarks lm) => _c.add(lm);
}

Landmarks _lm(double tipX, double tipY, double ratio, int tsUs,
    {double presence = 1.0}) {
  final v = List<double>.filled(63, 0);
  void set(int i, double x, double y) {
    v[i * 3] = x;
    v[i * 3 + 1] = y;
  }

  set(0, 0.5, 0.9); // wrist
  set(9, 0.5, 0.5); // middle MCP → span 0.4
  set(8, tipX, tipY); // index tip
  set(4, tipX, tipY + ratio * 0.4); // thumb tip → pinch ratio
  return Landmarks.fromList(v, presence: presence, tsUs: tsUs);
}

void main() {
  test('replayed landmark stream produces movement then a click', () async {
    final fake = _FakeSource();
    final tracker = HandTrackerImpl(
        source: fake, screenWidth: 1920, screenHeight: 1080);

    expect(tracker.isAvailable, isTrue);
    await tracker.start(const HandTrackerConfig());

    final got = <HandPointer>[];
    tracker.pointers.listen(got.add);

    fake.emit(_lm(0.5, 0.5, 0.6, 0)); // move, hand open
    await Future<void>.delayed(const Duration(milliseconds: 2));
    fake.emit(_lm(0.5, 0.5, 0.2, 50000)); // pinch starts
    await Future<void>.delayed(const Duration(milliseconds: 2));
    fake.emit(_lm(0.5, 0.5, 0.6, 100000)); // release → click
    await Future<void>.delayed(const Duration(milliseconds: 2));

    expect(got, isNotEmpty);
    expect(got.first.x, closeTo(960, 1.0)); // centered move
    expect(got.first.y, closeTo(540, 1.0));
    expect(got.any((p) => p.gesture == HandGesture.click), isTrue);

    await tracker.dispose();
  });
}
