/// The role a device plays in an ENSI session (FR-6..FR-9).
enum DeviceRole {
  /// This device's physical keyboard/mouse are shared to others.
  host,

  /// This device receives input from the Host.
  client,

  /// Mobile: sends input TO the Host (touchpad/keyboard), cannot receive.
  inputSender,

  /// Not yet assigned.
  idle,
}

/// The platform this device runs on.
enum DevicePlatform { windows, macos, linux, android, ios, unknown }

/// Geometry of a single physical monitor on a device.
///
/// Coordinates are in the device's own virtual-desktop space. [scale] is the
/// DPI/scaling factor used to normalize cursor speed across devices (FR-19).
class MonitorGeometry {
  final int id;
  final double left;
  final double top;
  final double width;
  final double height;
  final double scale;
  final bool isPrimary;

  const MonitorGeometry({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.scale = 1.0,
    this.isPrimary = false,
  });

  double get right => left + width;
  double get bottom => top + height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'l': left,
        't': top,
        'w': width,
        'h': height,
        's': scale,
        'p': isPrimary,
      };

  factory MonitorGeometry.fromJson(Map<String, dynamic> j) => MonitorGeometry(
        id: j['id'] as int,
        left: (j['l'] as num).toDouble(),
        top: (j['t'] as num).toDouble(),
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        scale: (j['s'] as num?)?.toDouble() ?? 1.0,
        isPrimary: (j['p'] as bool?) ?? false,
      );
}

/// Full display geometry reported by a device (FR-16): one or more monitors.
class DisplayGeometry {
  final List<MonitorGeometry> monitors;
  const DisplayGeometry(this.monitors);

  factory DisplayGeometry.single({
    double width = 1920,
    double height = 1080,
    double scale = 1.0,
  }) =>
      DisplayGeometry([
        MonitorGeometry(
          id: 0,
          left: 0,
          top: 0,
          width: width,
          height: height,
          scale: scale,
          isPrimary: true,
        ),
      ]);

  List<Map<String, dynamic>> toJson() =>
      monitors.map((m) => m.toJson()).toList();

  factory DisplayGeometry.fromJson(List<dynamic> j) => DisplayGeometry(
        j
            .map((e) => MonitorGeometry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Identity + capabilities of a device participating in (or discoverable for)
/// an ENSI session.
class DeviceInfo {
  /// Stable per-install id (persisted).
  final String id;
  final String name;
  final DevicePlatform platform;
  final DisplayGeometry displays;

  /// Whether this device can *receive* OS-level input. False for mobile (C-2).
  final bool canReceiveInput;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.displays,
    required this.canReceiveInput,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform.index,
        'displays': displays.toJson(),
        'rx': canReceiveInput,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        platform: DevicePlatform.values[j['platform'] as int],
        displays: DisplayGeometry.fromJson(j['displays'] as List<dynamic>),
        canReceiveInput: (j['rx'] as bool?) ?? false,
      );
}
