import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../models/device.dart';
import '../models/peer.dart';

/// LAN discovery of ENSI peers via mDNS (FR-1), with a UDP-broadcast fallback
/// planned for networks where mDNS is blocked (FR-1, FR-3).
///
/// The service registers/browses the `_ensi._tcp` service type. This class
/// currently implements the *browse* (find peers) path; advertising this
/// device is handled by [DiscoveryService.advertise] (stubbed until a platform
/// mDNS responder is wired — `multicast_dns` is browse-only).
class DiscoveryService {
  static const String serviceType = '_ensi._tcp';

  MDnsClient? _client;
  Timer? _pollTimer;

  final _peersController = StreamController<List<Peer>>.broadcast();
  final Map<String, Peer> _peers = {};

  Stream<List<Peer>> get peers => _peersController.stream;
  List<Peer> get currentPeers => _peers.values.toList(growable: false);

  /// Begin browsing the LAN for ENSI services. Polls periodically so devices
  /// that come online later are picked up (FR-5 reconnect support).
  Future<void> start() async {
    _client = MDnsClient();
    await _client!.start();
    await _scanOnce();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _scanOnce());
  }

  Future<void> _scanOnce() async {
    final client = _client;
    if (client == null) return;

    await for (final PtrResourceRecord ptr
        in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType))) {
      await for (final SrvResourceRecord srv
          in client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))) {
        await for (final IPAddressResourceRecord ip
            in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))) {
          _addOrUpdate(
            id: ptr.domainName,
            name: _friendlyName(ptr.domainName),
            host: ip.address.address,
            port: srv.port,
          );
        }
      }
    }
    _emit();
  }

  void _addOrUpdate({
    required String id,
    required String name,
    required String host,
    required int port,
  }) {
    final existing = _peers[id];
    if (existing != null) {
      existing.status = PeerStatus.discovered;
      return;
    }
    _peers[id] = Peer(
      info: DeviceInfo(
        id: id,
        name: name,
        platform: DevicePlatform.unknown,
        displays: DisplayGeometry.single(),
        canReceiveInput: true,
      ),
      host: host,
      port: port,
    );
  }

  String _friendlyName(String domain) =>
      domain.split('.').first.replaceAll('-', ' ');

  void _emit() => _peersController.add(currentPeers);

  /// Advertise this device on the LAN so others can find it.
  ///
  /// `multicast_dns` is a browser, not a responder, so a real implementation
  /// needs a platform mDNS responder (e.g. `nsd` plugin or native Bonjour/
  /// Avahi). Stubbed for now.
  Future<void> advertise(DeviceInfo self, int port) async {
    // TODO(M1): register _ensi._tcp via platform responder.
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _client?.stop();
    _client = null;
  }

  Future<void> dispose() async {
    await stop();
    await _peersController.close();
  }
}
