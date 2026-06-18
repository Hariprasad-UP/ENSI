import 'package:ensi/core/cert_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'loadOrCreate produces a valid, stable, persisted identity',
    () async {
      final a = await CertService.loadOrCreate('device-x');

      // Fingerprint is a 64-char lowercase hex SHA-256.
      expect(a.fingerprint, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a.fingerprint), isTrue);
      expect(a.certPem, contains('BEGIN CERTIFICATE'));

      // A SecurityContext can be built from the PEMs (cert/key are well-formed).
      expect(a.buildContext(), isNotNull);

      // Reload reuses the persisted cert (same fingerprint, no regeneration).
      final b = await CertService.loadOrCreate('device-x');
      expect(b.fingerprint, a.fingerprint);
      expect(b.certPem, a.certPem);
    },
    timeout: const Timeout(Duration(seconds: 90)), // one-time RSA keygen
  );
}
