import 'package:ensi/core/layout_manager.dart';
import 'package:ensi/models/device.dart';
import 'package:ensi/models/peer.dart';
import 'package:flutter_test/flutter_test.dart';

Peer _peer(String id, {double w = 1920, double h = 1080}) => Peer(
      info: DeviceInfo(
        id: id,
        name: id,
        platform: DevicePlatform.linux,
        displays: DisplayGeometry.single(width: w, height: h),
        canReceiveInput: true,
      ),
      host: '10.0.0.1',
      port: 24800,
    );

void main() {
  group('LayoutManager placement', () {
    test('place records the device at the given offset', () {
      final m = LayoutManager();
      m.place(_peer('a'), offsetX: 100, offsetY: 50);
      final p = m.placements['a']!;
      expect(p.offsetX, 100);
      expect(p.offsetY, 50);
      expect(p.width, 1920);
      expect(p.height, 1080);
    });

    test('move updates an existing placement', () {
      final m = LayoutManager();
      m.place(_peer('a'));
      m.move('a', 300, 400);
      expect(m.placements['a']!.offsetX, 300);
      expect(m.placements['a']!.offsetY, 400);
    });

    test('move on an unknown device is a no-op', () {
      final m = LayoutManager();
      expect(() => m.move('ghost', 1, 1), returnsNormally);
    });
  });

  group('LayoutManager.resolveEdge', () {
    late LayoutManager m;

    setUp(() {
      m = LayoutManager();
      // A at origin, B docked to its right edge, C docked below A.
      m.place(_peer('A'), offsetX: 0, offsetY: 0);
      m.place(_peer('B'), offsetX: 1920, offsetY: 0);
      m.place(_peer('C'), offsetX: 0, offsetY: 1080);
    });

    test('crossing the right edge switches to the device on the right', () {
      final s = m.resolveEdge('A', ScreenEdge.right, 500);
      expect(s, isNotNull);
      expect(s!.targetDeviceId, 'B');
    });

    test('crossing the left edge switches back to the left neighbour', () {
      final s = m.resolveEdge('B', ScreenEdge.left, 500);
      expect(s, isNotNull);
      expect(s!.targetDeviceId, 'A');
    });

    test('crossing the bottom edge switches to the device below', () {
      final s = m.resolveEdge('A', ScreenEdge.bottom, 500);
      expect(s, isNotNull);
      expect(s!.targetDeviceId, 'C');
    });

    test('no neighbour on that edge clamps (returns null)', () {
      expect(m.resolveEdge('A', ScreenEdge.left, 500), isNull);
      expect(m.resolveEdge('A', ScreenEdge.top, 500), isNull);
    });

    test('unknown source device returns null', () {
      expect(m.resolveEdge('nope', ScreenEdge.right, 500), isNull);
    });

    test('a neighbour that does not overlap the crossing point is ignored', () {
      final far = LayoutManager();
      far.place(_peer('A'), offsetX: 0, offsetY: 0);
      // To A's right horizontally, but far below A's vertical span.
      far.place(_peer('D'), offsetX: 1920, offsetY: 5000);
      expect(far.resolveEdge('A', ScreenEdge.right, 500), isNull);
    });
  });
}
