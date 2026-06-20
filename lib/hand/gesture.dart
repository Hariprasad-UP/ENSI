import 'hand_tracker.dart';
import 'landmarks.dart';

/// Turns a stream of [Landmarks] into discrete gestures:
///   move (implicit), click, dragStart/drag/dragEnd.
///
/// Robustness:
///  * **Hysteresis** — separate pinch on/off thresholds so it never flickers.
///  * **Debounce** — at most one click per [_debounceUs].
///  * **Hold-to-drag** — a pinch held past [_dragHoldUs] becomes a drag.
///  * **Confidence gate / failure recovery** — losing the hand safely releases
///    any held pinch/drag (never leaves a button stuck — NFR-2 parity).
class GestureRecognizer {
  final HandTrackerConfig cfg;

  static const int _dragHoldUs = 250000; // 250 ms pinch → drag
  static const int _debounceUs = 200000; // min gap between clicks
  static const double _minConfidence = 0.5;

  bool _pinched = false;
  bool _dragging = false;
  int _pinchStartUs = 0;
  int _lastClickUs = -1 << 50;

  GestureRecognizer(this.cfg);

  HandGesture update(Landmarks lm) {
    if (lm.presence < _minConfidence) {
      return _release(lm.tsUs); // hand lost → safe release
    }
    final d = lm.pinchDistance;

    if (!_pinched) {
      if (d < cfg.pinchOnThreshold) {
        _pinched = true;
        _pinchStartUs = lm.tsUs;
      }
      return HandGesture.none;
    }

    // Currently pinched.
    if (!_dragging && lm.tsUs - _pinchStartUs > _dragHoldUs) {
      _dragging = true;
      return HandGesture.dragStart;
    }
    if (_dragging) {
      if (d > cfg.pinchOffThreshold) return _release(lm.tsUs); // dragEnd
      return HandGesture.drag;
    }
    if (d > cfg.pinchOffThreshold) return _release(lm.tsUs); // click
    return HandGesture.none;
  }

  HandGesture _release(int tsUs) {
    final wasDragging = _dragging;
    final wasPinched = _pinched;
    _pinched = false;
    _dragging = false;
    if (wasDragging) return HandGesture.dragEnd;
    if (wasPinched && tsUs - _lastClickUs > _debounceUs) {
      _lastClickUs = tsUs;
      return HandGesture.click;
    }
    return HandGesture.none;
  }

  void reset() {
    _pinched = false;
    _dragging = false;
  }
}
