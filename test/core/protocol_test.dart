import 'package:ensi/core/protocol.dart';
import 'package:ensi/models/device.dart';
import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceInfo info() => DeviceInfo(
        id: 'dev-1',
        name: 'Studio',
        platform: DevicePlatform.windows,
        displays: DisplayGeometry.single(),
        canReceiveInput: true,
      );

  group('Message round-trip via frame', () {
    Message frameRoundTrip(Message m) =>
        Message.decodeFrame(String.fromCharCodes(m.encodeFrame()).trim());

    test('hello carries device info + fingerprint', () {
      final m = Message.hello(info(), 'abc123');
      final back = frameRoundTrip(m);
      expect(back.kind, MessageKind.hello);
      expect(back.fingerprint, 'abc123');
      expect(back.device!.id, 'dev-1');
      expect(back.device!.platform, DevicePlatform.windows);
    });

    test('event carries the input event', () {
      final m = Message.event(
        const InputEvent(type: InputEventType.keyDown, keyCode: 65),
      );
      final back = frameRoundTrip(m);
      expect(back.kind, MessageKind.event);
      expect(back.event!.type, InputEventType.keyDown);
      expect(back.event!.keyCode, 65);
    });

    test('clipboard carries text', () {
      final back = frameRoundTrip(Message.clipboard('copied text 123'));
      expect(back.kind, MessageKind.clipboard);
      expect(back.text, 'copied text 123');
    });

    test('control frames carry no payload', () {
      for (final m in [
        const Message.paired(),
        const Message.reject(),
        const Message.heartbeat(),
      ]) {
        final back = frameRoundTrip(m);
        expect(back.kind, m.kind);
        expect(back.device, isNull);
        expect(back.event, isNull);
        expect(back.fingerprint, isNull);
      }
    });
  });

  test('encodeFrame is newline-terminated', () {
    final bytes = const Message.heartbeat().encodeFrame();
    expect(bytes.last, 0x0a);
  });
}
