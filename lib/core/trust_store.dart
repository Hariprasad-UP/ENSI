import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

/// A peer this device has paired with. Trust is **pinned to the cert
/// [fingerprint]**: a peer is only trusted if it presents the exact certificate
/// recorded at pairing time (trust-on-first-use). A changed fingerprint means a
/// different (or impersonated) device and is rejected (FR-25).
class TrustedPeer {
  final String id;
  final String name;
  final DevicePlatform platform;
  final String fingerprint;
  final int addedAtMs;

  const TrustedPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.addedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'platform': platform.index,
        'fp': fingerprint,
        'at': addedAtMs,
      };

  factory TrustedPeer.fromJson(String id, Map<String, dynamic> j) => TrustedPeer(
        id: id,
        name: j['name'] as String,
        platform: DevicePlatform.values[j['platform'] as int],
        fingerprint: j['fp'] as String,
        addedAtMs: j['at'] as int,
      );
}

/// Persistent store of paired peers (FR-25, FR-26). Mirrors the
/// `shared_preferences` pattern in [IdentityService]; the whole map is stored as
/// one JSON blob under [_key].
class TrustStore {
  static const _key = 'ensi.peers.trusted';

  final Map<String, TrustedPeer> _peers = {};

  /// Hydrate from disk. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _peers.clear();
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    map.forEach((id, v) {
      _peers[id] = TrustedPeer.fromJson(id, v as Map<String, dynamic>);
    });
  }

  /// True only if [id] is paired **and** presents the pinned [fingerprint].
  bool isTrusted(String id, String fingerprint) =>
      _peers[id]?.fingerprint == fingerprint;

  TrustedPeer? get(String id) => _peers[id];

  List<TrustedPeer> list() => _peers.values.toList(growable: false);

  Future<void> trust(TrustedPeer peer) async {
    _peers[peer.id] = peer;
    await _save();
  }

  Future<void> revoke(String id) async {
    _peers.remove(id);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _peers.map((id, p) => MapEntry(id, p.toJson()));
    await prefs.setString(_key, jsonEncode(map));
  }
}
