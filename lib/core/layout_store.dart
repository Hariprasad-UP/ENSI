import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists each device's position on the shared layout (FR-20), keyed by device
/// id, so arrangements survive restarts. Mirrors the `shared_preferences`
/// pattern used by [IdentityService] / [TrustStore].
class LayoutStore {
  static const _key = 'ensi.layout.offsets';

  final Map<String, List<double>> _offsets = {}; // id -> [x, y]

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _offsets.clear();
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    map.forEach((id, v) {
      final list = (v as List).map((e) => (e as num).toDouble()).toList();
      if (list.length == 2) _offsets[id] = list;
    });
  }

  ({double x, double y})? offsetFor(String id) {
    final o = _offsets[id];
    return o == null ? null : (x: o[0], y: o[1]);
  }

  Future<void> set(String id, double x, double y) async {
    _offsets[id] = [x, y];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_offsets));
  }
}
