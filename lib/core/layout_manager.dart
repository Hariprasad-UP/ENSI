import '../models/device.dart';
import '../models/peer.dart';

/// One device's screen(s) placed on the shared 2D virtual layout (FR-15).
///
/// [offsetX]/[offsetY] position this device's top-left corner within the global
/// layout coordinate space; edge-adjacency is then computed from the resulting
/// rectangles (FR-17, FR-18).
class LayoutPlacement {
  final String deviceId;
  double offsetX;
  double offsetY;
  final DisplayGeometry displays;

  LayoutPlacement({
    required this.deviceId,
    required this.offsetX,
    required this.offsetY,
    required this.displays,
  });

  double get width =>
      displays.monitors.map((m) => m.right).fold<double>(0, _max);
  double get height =>
      displays.monitors.map((m) => m.bottom).fold<double>(0, _max);

  static double _max(double a, double b) => a > b ? a : b;
}

/// Which side of a screen the cursor crossed.
enum ScreenEdge { left, right, top, bottom }

/// Result of an edge-switch lookup: which device to hand off to and where the
/// cursor should appear on it.
class EdgeSwitch {
  final String targetDeviceId;
  final double entryX;
  final double entryY;
  const EdgeSwitch(this.targetDeviceId, this.entryX, this.entryY);
}

/// Holds the arrangement of all participating screens and resolves cursor
/// edge-switches between devices (FR-15..FR-19).
class LayoutManager {
  final Map<String, LayoutPlacement> placements = {};

  void place(Peer peer, {double offsetX = 0, double offsetY = 0}) =>
      placeDevice(peer.info.id, peer.info.displays,
          offsetX: offsetX, offsetY: offsetY);

  /// Place any device (including this host) by id + geometry.
  void placeDevice(String deviceId, DisplayGeometry displays,
      {double offsetX = 0, double offsetY = 0}) {
    placements[deviceId] = LayoutPlacement(
      deviceId: deviceId,
      offsetX: offsetX,
      offsetY: offsetY,
      displays: displays,
    );
  }

  void move(String deviceId, double offsetX, double offsetY) {
    final p = placements[deviceId];
    if (p == null) return;
    p.offsetX = offsetX;
    p.offsetY = offsetY;
  }

  /// Given the device the cursor is leaving and the [edge] + position along it,
  /// find the adjacent device to switch to. Returns null if there is no
  /// neighbour on that edge (cursor stays clamped).
  EdgeSwitch? resolveEdge(String fromDeviceId, ScreenEdge edge, double pos) {
    final from = placements[fromDeviceId];
    if (from == null) return null;

    for (final other in placements.values) {
      if (other.deviceId == fromDeviceId) continue;
      switch (edge) {
        case ScreenEdge.right:
          if (_near(other.offsetX, from.offsetX + from.width) &&
              _overlapsV(from, other, pos)) {
            return EdgeSwitch(
                other.deviceId, other.offsetX + 1, pos - other.offsetY);
          }
        case ScreenEdge.left:
          if (_near(other.offsetX + other.width, from.offsetX) &&
              _overlapsV(from, other, pos)) {
            return EdgeSwitch(other.deviceId, other.width - 1,
                pos - other.offsetY);
          }
        case ScreenEdge.bottom:
          if (_near(other.offsetY, from.offsetY + from.height) &&
              _overlapsH(from, other, pos)) {
            return EdgeSwitch(
                other.deviceId, pos - other.offsetX, other.offsetY + 1);
          }
        case ScreenEdge.top:
          if (_near(other.offsetY + other.height, from.offsetY) &&
              _overlapsH(from, other, pos)) {
            return EdgeSwitch(
                other.deviceId, pos - other.offsetX, other.height - 1);
          }
      }
    }
    return null;
  }

  bool _near(double a, double b) => (a - b).abs() < 4.0;

  bool _overlapsV(LayoutPlacement a, LayoutPlacement b, double y) =>
      y >= b.offsetY && y <= b.offsetY + b.height;

  bool _overlapsH(LayoutPlacement a, LayoutPlacement b, double x) =>
      x >= b.offsetX && x <= b.offsetX + b.width;
}
