import 'package:ensi/hand/one_euro_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first sample passes through unchanged', () {
    final f = OneEuroFilter();
    expect(f.filter(5.0, 0), 5.0);
  });

  test('constant input yields constant output', () {
    final f = OneEuroFilter();
    f.filter(5.0, 0);
    for (var t = 33333; t <= 333330; t += 33333) {
      expect(f.filter(5.0, t), closeTo(5.0, 1e-6));
    }
  });

  test('step input converges monotonically toward the new value', () {
    final f = OneEuroFilter(minCutoff: 1.0, beta: 0.0);
    f.filter(0.0, 0);
    double prev = 0;
    double last = 0;
    for (var i = 1; i <= 60; i++) {
      last = f.filter(1.0, i * 33333);
      expect(last, greaterThanOrEqualTo(prev - 1e-9)); // non-decreasing
      expect(last, lessThanOrEqualTo(1.0 + 1e-9));
      prev = last;
    }
    expect(last, greaterThan(0.8)); // has substantially converged
  });

  test('reset clears state', () {
    final f = OneEuroFilter();
    f.filter(10.0, 0);
    f.filter(10.0, 33333);
    f.reset();
    expect(f.filter(2.0, 100000), 2.0); // behaves like first sample again
  });
}
