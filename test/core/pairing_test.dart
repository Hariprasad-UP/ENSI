import 'package:ensi/core/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fpA = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888';
  const fpB = '1111aaaa2222bbbb3333cccc4444dddd5555eeee6666ffff7777aaaa8888bbbb';

  group('sasCode', () {
    test('is a deterministic 6-digit, zero-padded string', () {
      final code = sasCode(fpA, fpB);
      expect(code, hasLength(6));
      expect(int.tryParse(code), isNotNull);
      expect(code, sasCode(fpA, fpB)); // stable
    });

    test('is symmetric in its arguments (order-independent)', () {
      expect(sasCode(fpA, fpB), sasCode(fpB, fpA));
    });

    test('different fingerprint pairs yield different codes', () {
      const fpC =
          'deadbeef0000111122223333444455556666777788889999aaaabbbbccccdddd';
      expect(sasCode(fpA, fpB), isNot(sasCode(fpA, fpC)));
    });

    test('always returns exactly 6 characters even when numerically small', () {
      // Scan a range of inputs; every code must be 6 chars (padding holds).
      for (var i = 0; i < 50; i++) {
        final code = sasCode('fp$i', 'peer$i');
        expect(code, hasLength(6), reason: 'code "$code" for i=$i');
      }
    });
  });
}
