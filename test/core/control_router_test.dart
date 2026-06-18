import 'package:ensi/core/control_router.dart';
import 'package:ensi/core/layout_manager.dart';
import 'package:ensi/models/device.dart';
import 'package:ensi/models/input_event.dart';
import 'package:ensi/models/peer.dart';
import 'package:flutter_test/flutter_test.dart';

Peer _peer(String id) => Peer(
      info: DeviceInfo(
        id: id,
        name: id,
        platform: DevicePlatform.linux,
        displays: DisplayGeometry.single(width: 1000, height: 1000),
        canReceiveInput: true,
      ),
      host: 'x',
      port: 1,
    );

void main() {
  late LayoutManager layout;
  late List<bool> suppress;
  late List<List<double>> warps;
  late List<MapEntry<String, InputEvent>> forwards;
  late ControlRouter router;

  setUp(() {
    layout = LayoutManager()
      ..place(_peer('H'), offsetX: 0, offsetY: 0)
      ..place(_peer('C'), offsetX: 1000, offsetY: 0); // C is to the right of H
    suppress = [];
    warps = [];
    forwards = [];
    router = ControlRouter(
      selfId: 'H',
      selfWidth: 1000,
      selfHeight: 1000,
      layout: layout,
      onSuppress: suppress.add,
      onWarp: (x, y) => warps.add([x, y]),
      onForward: (p, e) => forwards.add(MapEntry(p, e)),
    );
  });

  test('stays local for an interior mouse move', () {
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 500, y: 500));
    expect(router.controlIsRemote, isFalse);
    expect(forwards, isEmpty);
    expect(suppress, isEmpty);
  });

  test('crossing the right edge transfers control to the right neighbour', () {
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 1000, y: 500));
    expect(router.controlIsRemote, isTrue);
    expect(router.owner, 'C');
    expect(suppress.last, isTrue); // local input suppressed
    // First forwarded frame is enterScreen at the target-local entry point.
    expect(forwards.first.key, 'C');
    expect(forwards.first.value.type, InputEventType.enterScreen);
    expect(forwards.first.value.x, closeTo(1, 0.001)); // global 1001 - offset 1000
    expect(forwards.first.value.y, closeTo(500, 0.001));
  });

  test('while remote, moves forward as target-local deltas (recentred)', () {
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 1000, y: 500));
    forwards.clear();
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 600, y: 520));
    // dx = 600-500 = +100, dy = 520-500 = +20 from centre (500,500).
    final m = forwards.single.value;
    expect(m.type, InputEventType.mouseMove);
    expect(m.x, closeTo(101, 0.001)); // entry 1 + 100
    expect(m.y, closeTo(520, 0.001)); // entry 500 + 20
    // Cursor is warped back to centre to keep producing deltas.
    expect(warps.last, [500, 500]);
  });

  test('keyboard events forward as-is while remote', () {
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 1000, y: 500));
    forwards.clear();
    router.onCaptured(const InputEvent(type: InputEventType.keyDown, keyCode: 65));
    expect(forwards.single.key, 'C');
    expect(forwards.single.value.type, InputEventType.keyDown);
    expect(forwards.single.value.keyCode, 65);
  });

  test('crossing back over the return edge restores local control', () {
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 1000, y: 500));
    // Push hard left: dx = 0 - 500 = -500, repeatedly, until vx < 0.
    router.onCaptured(const InputEvent(type: InputEventType.mouseMove, x: 0, y: 500));
    expect(router.controlIsRemote, isFalse);
    expect(suppress.last, isFalse); // restored
    expect(forwards.last.value.type, InputEventType.leaveScreen);
  });
}
