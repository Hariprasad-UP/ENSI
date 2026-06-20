import 'dart:math' as math;

/// 1€ filter (Casiez, Roussel & Vogel, 2012) — adaptive low-pass that gives
/// low jitter when the signal is slow and low lag when it's fast. The standard
/// smoother for pointer/gesture input. Pure, allocation-free, unit-testable.
class OneEuroFilter {
  /// Minimum cutoff frequency (Hz). Lower = smoother but laggier at rest.
  final double minCutoff;

  /// Speed coefficient. Higher = less lag when moving fast.
  final double beta;

  /// Cutoff for the derivative estimate.
  final double dCutoff;

  double? _xPrev;
  double _dxPrev = 0;
  int? _tPrevUs;

  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  /// Filter sample [x] taken at [tUs] microseconds.
  double filter(double x, int tUs) {
    if (_tPrevUs == null) {
      _xPrev = x;
      _dxPrev = 0;
      _tPrevUs = tUs;
      return x;
    }
    final dt = (tUs - _tPrevUs!) / 1e6;
    if (dt <= 0) return _xPrev!;

    final dx = (x - _xPrev!) / dt;
    final edx = _lowpass(dx, _alpha(dCutoff, dt), _dxPrev);
    _dxPrev = edx;

    final cutoff = minCutoff + beta * edx.abs();
    final ex = _lowpass(x, _alpha(cutoff, dt), _xPrev!);

    _xPrev = ex;
    _tPrevUs = tUs;
    return ex;
  }

  void reset() {
    _xPrev = null;
    _dxPrev = 0;
    _tPrevUs = null;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  static double _lowpass(double value, double alpha, double prev) =>
      alpha * value + (1 - alpha) * prev;
}
