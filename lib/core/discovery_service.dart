import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';
import '../models/peer.dart';
import 'transport.dart' show kEnsiPort;

/// LAN discovery via a pure-Dart **UDP multicast beacon** (FR-1). Every device
/// periodically broadcasts a small datagram describing itself to the ENSI
/// multicast group and listens for the same from peers — no mDNS responder,
/// Avahi, or Bonjour required, and it works fully offline (C-4).
///
/// A peer is marked `offline` after [_offlineAfter] of silence and dropped after
/// [_removeAfter] (FR-5). The authoritative cert fingerprint used for pairing is
/// taken from the TLS handshake, not the (spoofable) beacon — the beacon's `fp`
/// is advisory only.
class DiscoveryService {
  static const String multicastGroup = '239.255.42.99';
  static const int discoveryPort = 24799;
  static const Duration _beaconInterval = Duration(seconds: 2);
  static const Duration _sweepInterval = Duration(seconds: 2);
  static const Duration _offlineAfter = Duration(seconds: 8);
  static const Duration _removeAfter = Duration(seconds: 30);

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _sweepTimer;

  DeviceInfo? _self;
  int _tcpPort = kEnsiPort;
  String _fingerprint = '';

  final _peersController = StreamController<List<Peer>>.broadcast();
  final Map<String, _PeerEntry> _entries = {};

  Stream<List<Peer>> get peers => _peersController.stream;
  List<Peer> get currentPeers =>
      _entries.values.map((e) => e.peer).toList(growable: false);

  /// Open the multicast socket, join the group, and begin listening for peers.
  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    socket.multicastLoopback = true; // we filter our own beacons by id
    socket.broadcastEnabled = true;
    // Join the multicast group on EVERY interface — the default route may be a
    // VPN or WSL/Docker adapter, so a single join misses the real LAN (FR-1).
    try {
      socket.joinMulticast(InternetAddress(multicastGroup));
    } catch (_) {}
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in ifaces) {
        try {
          socket.joinMulticast(InternetAddress(multicastGroup), iface);
        } catch (_) {}
      }
    } catch (_) {}
    socket.listen(_onSocketEvent);
    _socket = socket;
    _sweepTimer = Timer.periodic(_sweepInterval, (_) => _sweep());
  }

  /// Begin advertising this device (real implementation of the former M0 stub).
  /// Safe to call after [start]; sends an immediate beacon then repeats.
  Future<void> advertise(DeviceInfo self, int port,
      {String fingerprint = ''}) async {
    _self = self;
    _tcpPort = port;
    _fingerprint = fingerprint;
    _sendBeacon();
    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());
  }

  Future<void> _sendBeacon() async {
    final self = _self;
    if (self == null) return;
    final data = utf8.encode(encodeBeacon(self, _tcpPort, _fingerprint));
    // Primary send via the default route.
    try {
      _socket?.send(data, InternetAddress(multicastGroup), discoveryPort);
    } catch (_) {}
    // Also egress every real IPv4 interface (multicast + global broadcast), so
    // peers are found regardless of which interface holds the default route.
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          RawDatagramSocket? s;
          try {
            s = await RawDatagramSocket.bind(addr, 0);
            s.broadcastEnabled = true;
            s.send(data, InternetAddress(multicastGroup), discoveryPort);
            s.send(data, InternetAddress('255.255.255.255'), discoveryPort);
          } catch (_) {
            /* interface may not allow bind/send; skip */
          } finally {
            s?.close();
          }
        }
      }
    } catch (_) {}
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    final beacon = decodeBeacon(utf8.decode(dg.data));
    if (beacon == null) return;
    final id = beacon['id'] as String?;
    if (id == null || id == _self?.id) return; // ignore malformed + self
    _ingest(id, beacon, dg.address.address);
  }

  void _ingest(String id, Map<String, dynamic> b, String host) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _entries[id];
    if (existing != null) {
      // Keep the same Peer instance (AppState holds references to it).
      existing.peer.host = host;
      existing.peer.port = (b['port'] as int?) ?? kEnsiPort;
      if (existing.peer.status == PeerStatus.offline) {
        existing.peer.status = PeerStatus.discovered;
      }
      existing.lastSeenMs = now;
      existing.fingerprint = (b['fp'] as String?) ?? existing.fingerprint;
      _emit();
      return;
    }
    _entries[id] = _PeerEntry(
      peer: Peer(
        info: DeviceInfo(
          id: id,
          name: (b['n'] as String?) ?? 'device',
          platform: DevicePlatform.values[(b['p'] as int?) ?? 0],
          displays: DisplayGeometry.single(),
          canReceiveInput: (b['rx'] as bool?) ?? true,
        ),
        host: host,
        port: (b['port'] as int?) ?? kEnsiPort,
      ),
      lastSeenMs: now,
      fingerprint: (b['fp'] as String?) ?? '',
    );
    _emit();
  }

  void _sweep() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    final toRemove = <String>[];
    for (final e in _entries.values) {
      final age = now - e.lastSeenMs;
      if (age > _removeAfter.inMilliseconds) {
        toRemove.add(e.peer.info.id);
        changed = true;
      } else if (age > _offlineAfter.inMilliseconds &&
          e.peer.status != PeerStatus.offline &&
          e.peer.status != PeerStatus.connected) {
        e.peer.status = PeerStatus.offline;
        changed = true;
      }
    }
    toRemove.forEach(_entries.remove);
    if (changed) _emit();
  }

  /// Advisory fingerprint last seen in a peer's beacon (TLS handshake is
  /// authoritative for pairing).
  String? fingerprintFor(String id) => _entries[id]?.fingerprint;

  void _emit() => _peersController.add(currentPeers);

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _sweepTimer?.cancel();
    _beaconTimer = null;
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await stop();
    await _peersController.close();
  }

  // --- Pure (de)serialization, unit-tested directly ------------------------

  /// Encode this device's beacon datagram payload.
  static String encodeBeacon(DeviceInfo self, int tcpPort, String fingerprint) =>
      jsonEncode({
        'id': self.id,
        'n': self.name,
        'p': self.platform.index,
        'port': tcpPort,
        'fp': fingerprint,
        'rx': self.canReceiveInput,
      });

  /// Decode a received beacon payload, or null if malformed.
  static Map<String, dynamic>? decodeBeacon(String data) {
    try {
      final j = jsonDecode(data);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Status implied by how long ago a peer was last heard from. Pure helper for
  /// the sweep logic (testable without sockets/timers).
  static PeerStatus statusForAgeMs(int ageMs) =>
      ageMs > _offlineAfter.inMilliseconds
          ? PeerStatus.offline
          : PeerStatus.discovered;
}

class _PeerEntry {
  final Peer peer;
  int lastSeenMs;
  String fingerprint;
  _PeerEntry({
    required this.peer,
    required this.lastSeenMs,
    required this.fingerprint,
  });
}
