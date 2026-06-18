import 'package:ensi/core/trust_store.dart';
import 'package:ensi/models/device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrustedPeer _peer(String id, String fp) => TrustedPeer(
      id: id,
      name: 'Box-$id',
      platform: DevicePlatform.linux,
      fingerprint: fp,
      addedAtMs: 1700000000000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isTrusted matches only on the pinned fingerprint', () async {
    final store = TrustStore();
    await store.load();
    await store.trust(_peer('dev1', 'FINGERPRINT_A'));

    expect(store.isTrusted('dev1', 'FINGERPRINT_A'), isTrue);
    // Same id, different cert => impersonation => not trusted (FR-25).
    expect(store.isTrusted('dev1', 'FINGERPRINT_B'), isFalse);
    // Unknown id.
    expect(store.isTrusted('dev2', 'FINGERPRINT_A'), isFalse);
  });

  test('revoke removes a peer', () async {
    final store = TrustStore();
    await store.load();
    await store.trust(_peer('dev1', 'FP'));
    expect(store.isTrusted('dev1', 'FP'), isTrue);

    await store.revoke('dev1');
    expect(store.isTrusted('dev1', 'FP'), isFalse);
    expect(store.list(), isEmpty);
  });

  test('trusted peers persist across a reload', () async {
    final a = TrustStore();
    await a.load();
    await a.trust(_peer('dev1', 'FP1'));
    await a.trust(_peer('dev2', 'FP2'));

    // A fresh instance reads the same backing store.
    final b = TrustStore();
    await b.load();
    expect(b.list(), hasLength(2));
    expect(b.isTrusted('dev1', 'FP1'), isTrue);
    expect(b.get('dev2')!.name, 'Box-dev2');
    expect(b.get('dev2')!.platform, DevicePlatform.linux);
  });
}
