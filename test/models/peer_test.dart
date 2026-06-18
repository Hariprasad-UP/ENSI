import 'package:ensi/models/device.dart';
import 'package:ensi/models/peer.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceInfo _info(String id, {String name = 'Box', DevicePlatform platform = DevicePlatform.windows}) =>
    DeviceInfo(
      id: id,
      name: name,
      platform: platform,
      displays: DisplayGeometry.single(),
      canReceiveInput: true,
    );

void main() {
  group('Peer identity', () {
    test('equality and hashCode are based on device id, not endpoint', () {
      final a = Peer(info: _info('same'), host: '10.0.0.1', port: 24800);
      final b = Peer(info: _info('same'), host: '10.0.0.2', port: 9999);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('peers with different ids are not equal', () {
      final a = Peer(info: _info('one'), host: '10.0.0.1', port: 24800);
      final b = Peer(info: _info('two'), host: '10.0.0.1', port: 24800);
      expect(a, isNot(equals(b)));
    });

    test('a Set de-duplicates peers by id', () {
      final set = {
        Peer(info: _info('dup'), host: '10.0.0.1', port: 1),
        Peer(info: _info('dup'), host: '10.0.0.9', port: 2),
        Peer(info: _info('other'), host: '10.0.0.3', port: 3),
      };
      expect(set, hasLength(2));
    });
  });

  group('Peer display helpers', () {
    test('displayName combines name and platform', () {
      final p = Peer(
        info: _info('id', name: 'Laptop', platform: DevicePlatform.macos),
        host: '10.0.0.5',
        port: 24800,
      );
      expect(p.displayName, 'Laptop (macos)');
    });

    test('endpoint combines host and port', () {
      final p = Peer(info: _info('id'), host: '192.168.1.42', port: 24800);
      expect(p.endpoint, '192.168.1.42:24800');
    });

    test('new peers start untrusted and discovered', () {
      final p = Peer(info: _info('id'), host: '10.0.0.1', port: 24800);
      expect(p.trusted, isFalse);
      expect(p.status, PeerStatus.discovered);
    });
  });
}
