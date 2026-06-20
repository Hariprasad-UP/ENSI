import 'hand_tracker.dart';
import 'landmarks.dart';
import 'one_euro_filter.dart';

/// Maps the index fingertip (normalized image coords) to absolute screen pixels
/// across the (possibly multi-monitor) virtual desktop, with:
///  * active-region crop + optional X-mirror,
///  * 1€ smoothing on each axis,
///  * **freeze-on-click** (holds the pointer briefly at a click/drag-start so
///    the pinch motion doesn't drift the cursor off-target).
///
/// Screen bounds are injected so this stays pure and unit-testable.
class CursorMapper {
  final HandTrackerConfig cfg;
  final double screenLeft, screenTop, screenWidth, screenHeight;

  static const int _freezeUs = 150000; // 150 ms

  late final OneEuroFilter _fx =
      OneEuroFilter(minCutoff: cfg.minCutoff, beta: cfg.beta);
  late final OneEuroFilter _fy =
      OneEuroFilter(minCutoff: cfg.minCutoff, beta: cfg.beta);

  int _freezeUntilUs = -1 << 50;
  double _lastX = 0, _lastY = 0;

  CursorMapper(
    this.cfg, {
    required this.screenLeft,
    required this.screenTop,
    required this.screenWidth,
    required this.screenHeight,
  });

  HandPointer map(Landmarks lm, HandGesture gesture) {
    final tUs = lm.tsUs;
    final present = lm.presence >= 0.5;

    if (gesture == HandGesture.click || gesture == HandGesture.dragStart) {
      _freezeUntilUs = tUs + _freezeUs;
    }
    if (tUs < _freezeUntilUs) {
      return HandPointer(
          x: _lastX,
          y: _lastY,
          present: present,
          gesture: gesture,
          confidence: lm.presence);
    }

    final tip = lm.indexTip;
    var nx = ((tip.x - cfg.activeRegion.left) / cfg.activeRegion.width)
        .clamp(0.0, 1.0);
    final ny = ((tip.y - cfg.activeRegion.top) / cfg.activeRegion.height)
        .clamp(0.0, 1.0);
    if (cfg.mirrorX) nx = 1.0 - nx;

    _lastX = _fx.filter(screenLeft + nx * screenWidth, tUs);
    _lastY = _fy.filter(screenTop + ny * screenHeight, tUs);

    return HandPointer(
        x: _lastX,
        y: _lastY,
        present: present,
        gesture: gesture,
        confidence: lm.presence);
  }

  void reset() {
    _fx.reset();
    _fy.reset();
    _freezeUntilUs = -1 << 50;
  }
}
