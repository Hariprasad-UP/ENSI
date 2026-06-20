import 'package:ensi/hand/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a 63-float landmark vector with specific key points.
List<double> _vec({
  required double indexX,
  required double indexY,
  required double thumbX,
  required double thumbY,
  double wristX = 0.5,
  double wristY = 0.9,
  double mcpX = 0.5,
  double mcpY = 0.5,
}) {
  final v = List<double>.filled(63, 0);
  void set(int i, double x, double y) {
    v[i * 3] = x;
    v[i * 3 + 1] = y;
  }

  set(0, wristX, wristY); // wrist
  set(4, thumbX, thumbY); // thumb tip
  set(8, indexX, indexY); // index tip
  set(9, mcpX, mcpY); // middle MCP
  return v;
}

void main() {
  test('named accessors read the correct indices', () {
    final lm = Landmarks.fromList(
      _vec(indexX: 0.5, indexY: 0.6, thumbX: 0.4, thumbY: 0.6),
      presence: 0.9,
      tsUs: 0,
    );
    expect(lm.indexTip.x, closeTo(0.5, 1e-6));
    expect(lm.indexTip.y, closeTo(0.6, 1e-6));
    expect(lm.thumbTip.x, closeTo(0.4, 1e-6));
    expect(lm.wrist.y, closeTo(0.9, 1e-6));
    expect(lm.middleMcp.y, closeTo(0.5, 1e-6));
  });

  test('pinchDistance is normalized by hand span', () {
    // thumb↔index distance = 0.1; span (wrist↔mcp) = 0.4 → ratio 0.25.
    final lm = Landmarks.fromList(
      _vec(indexX: 0.5, indexY: 0.6, thumbX: 0.4, thumbY: 0.6),
      presence: 1.0,
      tsUs: 0,
    );
    expect(lm.pinchDistance, closeTo(0.25, 1e-6));
  });
}
