import 'package:ensi/core/discovery_service.dart';
import 'package:ensi/models/device.dart';
import 'package:ensi/models/peer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceInfo self() => DeviceInfo(
        id: 'dev-42',
        name: 'Studio-PC',
        platform: DevicePlatform.windows,
        displays: DisplayGeometry.single(),
        canReceiveInput: true,
      );

  group('beacon (de)serialization', () {
    test('encode -> decode preserves the advertised fields', () {
      final data = DiscoveryService.encodeBeacon(self(), 24800, 'fp-abc');
      final b = DiscoveryService.decodeBeacon(data)!;
      expect(b['id'], 'dev-42');
      expect(b['n'], 'Studio-PC');
      expect(b['p'], DevicePlatform.windows.index);
      expect(b['port'], 24800);
      expect(b['fp'], 'fp-abc');
      expect(b['rx'], true);
    });

    test('decodeBeacon returns null on malformed input', () {
      expect(DiscoveryService.decodeBeacon('not json'), isNull);
      expect(DiscoveryService.decodeBeacon('[1,2,3]'), isNull); // not a map
    });
  });

  group('staleness', () {
    test('recent peers are discovered, silent peers go offline', () {
      expect(DiscoveryService.statusForAgeMs(1000), PeerStatus.discovered);
      expect(DiscoveryService.statusForAgeMs(7000), PeerStatus.discovered);
      expect(DiscoveryService.statusForAgeMs(9000), PeerStatus.offline);
    });
  });
}
