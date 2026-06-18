import 'dart:convert';

import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputEvent JSON round-trip', () {
    void expectRoundTrip(InputEvent e) {
      final back = InputEvent.fromJson(e.toJson());
      expect(back.type, e.type);
      expect(back.x, e.x);
      expect(back.y, e.y);
      expect(back.scrollDx, e.scrollDx);
      expect(back.scrollDy, e.scrollDy);
      expect(back.button, e.button);
      expect(back.keyCode, e.keyCode);
      expect(back.modifiers, e.modifiers);
    }

    test('mouseMove preserves coordinates', () {
      expectRoundTrip(
        const InputEvent(type: InputEventType.mouseMove, x: 12.5, y: -7.25),
      );
    });

    test('mouseDown preserves button', () {
      expectRoundTrip(
        const InputEvent(type: InputEventType.mouseDown, button: 2),
      );
    });

    test('mouseScroll preserves deltas', () {
      expectRoundTrip(
        const InputEvent(
            type: InputEventType.mouseScroll, scrollDx: 1.0, scrollDy: -3.0),
      );
    });

    test('keyDown preserves keyCode and modifiers', () {
      expectRoundTrip(
        const InputEvent(
          type: InputEventType.keyDown,
          keyCode: 65,
          modifiers: InputModifiers.ctrl | InputModifiers.shift,
        ),
      );
    });

    test('control frame (releaseAll) carries only its type', () {
      const e = InputEvent(type: InputEventType.releaseAll);
      final json = e.toJson();
      expect(json.keys, equals({'t'}));
      expect(InputEvent.fromJson(json).type, InputEventType.releaseAll);
    });
  });

  group('toJson omits absent fields', () {
    test('null coordinates and zero modifiers are dropped', () {
      const e = InputEvent(type: InputEventType.leaveScreen);
      final json = e.toJson();
      expect(json.containsKey('x'), isFalse);
      expect(json.containsKey('y'), isFalse);
      expect(json.containsKey('m'), isFalse);
    });

    test('zero modifiers omitted but non-zero kept', () {
      expect(
        const InputEvent(type: InputEventType.keyDown, keyCode: 1)
            .toJson()
            .containsKey('m'),
        isFalse,
      );
      expect(
        const InputEvent(
                type: InputEventType.keyDown,
                keyCode: 1,
                modifiers: InputModifiers.alt)
            .toJson()['m'],
        InputModifiers.alt,
      );
    });
  });

  group('wire framing', () {
    test('encodeFrame is newline-terminated UTF-8', () {
      final bytes = const InputEvent(type: InputEventType.mouseMove, x: 1, y: 2)
          .encodeFrame();
      expect(bytes.last, 0x0a); // trailing '\n'
      // Exactly one frame delimiter.
      expect(bytes.where((b) => b == 0x0a).length, 1);
    });

    test('decodeFrame reverses encodeFrame (a frame survives the wire)', () {
      const original = InputEvent(
        type: InputEventType.keyDown,
        keyCode: 13,
        modifiers: InputModifiers.meta,
      );
      // Simulate the transport: bytes -> utf8 -> split on '\n'.
      final line = utf8.decode(original.encodeFrame()).split('\n').first;
      final decoded = InputEvent.decodeFrame(line);
      expect(decoded.type, original.type);
      expect(decoded.keyCode, original.keyCode);
      expect(decoded.modifiers, original.modifiers);
    });

    test('decodeFrame throws on malformed input', () {
      expect(() => InputEvent.decodeFrame('not json'), throwsFormatException);
    });
  });

  test('InputModifiers are distinct single bits', () {
    final all = [
      InputModifiers.shift,
      InputModifiers.ctrl,
      InputModifiers.alt,
      InputModifiers.meta,
    ];
    // No two modifiers share a bit.
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        expect(all[i] & all[j], 0, reason: 'modifiers $i and $j overlap');
      }
    }
  });
}
