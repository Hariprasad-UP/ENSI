import 'package:ensi/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonitorGeometry', () {
    test('right and bottom are derived from position + size', () {
      const m = MonitorGeometry(
          id: 1, left: 10, top: 20, width: 100, height: 50);
      expect(m.right, 110);
      expect(m.bottom, 70);
    });

    test('JSON round-trip preserves all fields', () {
      const m = MonitorGeometry(
        id: 2,
        left: 1920,
        top: 0,
        width: 2560,
        height: 1440,
        scale: 1.5,
        isPrimary: true,
      );
      final back = MonitorGeometry.fromJson(m.toJson());
      expect(back.id, m.id);
      expect(back.left, m.left);
      expect(back.top, m.top);
      expect(back.width, m.width);
      expect(back.height, m.height);
      expect(back.scale, m.scale);
      expect(back.isPrimary, m.isPrimary);
    });

    test('scale defaults to 1.0 when absent from JSON', () {
      final m = MonitorGeometry.fromJson({
        'id': 0,
        'l': 0,
        't': 0,
        'w': 800,
        'h': 600,
      });
      expect(m.scale, 1.0);
      expect(m.isPrimary, isFalse);
    });
  });

  group('DisplayGeometry', () {
    test('single() builds one primary 1080p monitor by default', () {
      final d = DisplayGeometry.single();
      expect(d.monitors, hasLength(1));
      final m = d.monitors.single;
      expect(m.width, 1920);
      expect(m.height, 1080);
      expect(m.isPrimary, isTrue);
    });

    test('JSON round-trip preserves a multi-monitor layout', () {
      const geo = DisplayGeometry([
        MonitorGeometry(
            id: 0, left: 0, top: 0, width: 1920, height: 1080, isPrimary: true),
        MonitorGeometry(id: 1, left: 1920, top: 0, width: 1280, height: 1024),
      ]);
      final back = DisplayGeometry.fromJson(geo.toJson());
      expect(back.monitors, hasLength(2));
      expect(back.monitors[1].left, 1920);
      expect(back.monitors[1].width, 1280);
    });
  });

  group('DeviceInfo', () {
    test('JSON round-trip preserves identity and capabilities', () {
      final info = DeviceInfo(
        id: 'abc-123',
        name: 'Studio-PC',
        platform: DevicePlatform.linux,
        displays: DisplayGeometry.single(width: 2560, height: 1440),
        canReceiveInput: true,
      );
      final back = DeviceInfo.fromJson(info.toJson());
      expect(back.id, 'abc-123');
      expect(back.name, 'Studio-PC');
      expect(back.platform, DevicePlatform.linux);
      expect(back.canReceiveInput, isTrue);
      expect(back.displays.monitors.single.width, 2560);
    });

    test('canReceiveInput defaults to false when absent', () {
      final back = DeviceInfo.fromJson({
        'id': 'x',
        'name': 'phone',
        'platform': DevicePlatform.android.index,
        'displays': DisplayGeometry.single().toJson(),
      });
      expect(back.canReceiveInput, isFalse);
    });
  });
}
