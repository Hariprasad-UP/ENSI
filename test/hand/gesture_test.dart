import 'package:ensi/hand/gesture.dart';
import 'package:ensi/hand/hand_tracker.dart';
import 'package:ensi/hand/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Landmarks whose [pinchDistance] equals [ratio] (span fixed at 0.4).
Landmarks _lm(double ratio, {double presence = 1.0, required int tsUs}) {
  final v = List<double>.filled(63, 0);
  void set(int i, double x, double y) {
    v[i * 3] = x;
    v[i * 3 + 1] = y;
  }

  set(0, 0.5, 0.9); // wrist
  set(9, 0.5, 0.5); // middle MCP → span 0.4
  set(8, 0.5, 0.6); // index tip
  set(4, 0.5, 0.6 + ratio * 0.4); // thumb tip → dist = ratio*0.4 → ratio after /0.4
  return Landmarks.fromList(v, presence: presence, tsUs: tsUs);
}

void main() {
  final cfg = const HandTrackerConfig(); // pinchOn 0.30, pinchOff 0.45

  test('one pinch → exactly one click', () {
    final g = GestureRecognizer(cfg);
    expect(g.update(_lm(0.20, tsUs: 0)), HandGesture.none); // pinch starts
    expect(g.update(_lm(0.60, tsUs: 100000)), HandGesture.click); // release < 250ms
  });

  test('hysteresis: mid-band does not flicker', () {
    final g = GestureRecognizer(cfg);
    g.update(_lm(0.20, tsUs: 0)); // pinched
    expect(g.update(_lm(0.35, tsUs: 50000)), HandGesture.none); // between on/off → hold
    expect(g.update(_lm(0.60, tsUs: 100000)), HandGesture.click); // crosses off → click
  });

  test('debounce suppresses a too-fast second click', () {
    final g = GestureRecognizer(cfg);
    g.update(_lm(0.20, tsUs: 0));
    expect(g.update(_lm(0.60, tsUs: 100000)), HandGesture.click);
    g.update(_lm(0.20, tsUs: 150000));
    expect(g.update(_lm(0.60, tsUs: 180000)), HandGesture.none); // within 200ms
  });

  test('hold becomes a drag and releases cleanly', () {
    final g = GestureRecognizer(cfg);
    expect(g.update(_lm(0.20, tsUs: 0)), HandGesture.none);
    expect(g.update(_lm(0.20, tsUs: 300000)), HandGesture.dragStart); // >250ms
    expect(g.update(_lm(0.20, tsUs: 350000)), HandGesture.drag);
    expect(g.update(_lm(0.60, tsUs: 400000)), HandGesture.dragEnd);
  });

  test('losing the hand mid-drag emits dragEnd (no stuck button)', () {
    final g = GestureRecognizer(cfg);
    g.update(_lm(0.20, tsUs: 0));
    g.update(_lm(0.20, tsUs: 300000)); // dragStart
    expect(g.update(_lm(0.20, presence: 0.0, tsUs: 350000)), HandGesture.dragEnd);
  });
}
