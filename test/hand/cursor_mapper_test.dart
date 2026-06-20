import 'package:ensi/hand/cursor_mapper.dart';
import 'package:ensi/hand/hand_tracker.dart';
import 'package:ensi/hand/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

Landmarks _tip(double x, double y, {double presence = 1.0, required int tsUs}) {
  final v = List<double>.filled(63, 0);
  v[8 * 3] = x; // index tip x
  v[8 * 3 + 1] = y; // index tip y
  return Landmarks.fromList(v, presence: presence, tsUs: tsUs);
}

CursorMapper _mapper(HandTrackerConfig cfg) => CursorMapper(cfg,
    screenLeft: 0, screenTop: 0, screenWidth: 1920, screenHeight: 1080);

void main() {
  test('active-region center maps to screen center', () {
    final m = _mapper(const HandTrackerConfig());
    final p = m.map(_tip(0.5, 0.5, tsUs: 0), HandGesture.none);
    expect(p.x, closeTo(960, 0.5));
    expect(p.y, closeTo(540, 0.5));
  });

  test('mirrorX flips horizontally', () {
    final m = _mapper(const HandTrackerConfig()); // mirrorX = true
    // Left edge of active region (x=0.15) → mirror → right of screen.
    final left = m.map(_tip(0.15, 0.5, tsUs: 0), HandGesture.none);
    expect(left.x, closeTo(1920, 0.5));
    final m2 = _mapper(const HandTrackerConfig());
    final right = m2.map(_tip(0.85, 0.5, tsUs: 0), HandGesture.none);
    expect(right.x, closeTo(0, 0.5));
  });

  test('coordinates clamp to the active region', () {
    final m = _mapper(const HandTrackerConfig());
    final p = m.map(_tip(0.0, 1.0, tsUs: 0), HandGesture.none);
    expect(p.x, inInclusiveRange(0, 1920));
    expect(p.y, inInclusiveRange(0, 1080));
  });

  test('freeze-on-click holds the pointer for the freeze window', () {
    final m = _mapper(const HandTrackerConfig());
    final a = m.map(_tip(0.5, 0.5, tsUs: 0), HandGesture.none); // establish point
    // Click at a *different* tip → should return the frozen (previous) point.
    final clicked = m.map(_tip(0.8, 0.8, tsUs: 10000), HandGesture.click);
    expect(clicked.x, closeTo(a.x, 0.5));
    expect(clicked.y, closeTo(a.y, 0.5));
    // Still within 150ms freeze → frozen.
    final during = m.map(_tip(0.2, 0.2, tsUs: 100000), HandGesture.none);
    expect(during.x, closeTo(a.x, 0.5));
    // After the window → moves again.
    final after = m.map(_tip(0.2, 0.2, tsUs: 300000), HandGesture.none);
    expect(after.x, isNot(closeTo(a.x, 0.5)));
  });
}
