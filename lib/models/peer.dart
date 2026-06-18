import 'device.dart';

enum PeerStatus { discovered, pairing, paired, connected, offline }

/// A remote device discovered on the LAN and/or paired with this one.
class Peer {
  final DeviceInfo info;
  final String host; // IP address
  final int port;
  PeerStatus status;

  /// True once the user has confirmed pairing (PIN) — only trusted peers may
  /// exchange input (FR-25).
  bool trusted;

  Peer({
    required this.info,
    required this.host,
    required this.port,
    this.status = PeerStatus.discovered,
    this.trusted = false,
  });

  String get displayName => '${info.name} (${info.platform.name})';
  String get endpoint => '$host:$port';

  @override
  bool operator ==(Object other) => other is Peer && other.info.id == info.id;

  @override
  int get hashCode => info.id.hashCode;
}
