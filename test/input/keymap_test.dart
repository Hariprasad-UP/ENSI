import 'package:ensi/input/keymap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyMap vk <-> keysym', () {
    test('letters map to lowercase X11 keysyms', () {
      expect(KeyMap.vkToKeysym(0x41), 0x61); // A -> a
      expect(KeyMap.vkToKeysym(0x5A), 0x7A); // Z -> z
    });

    test('digits share the same code point', () {
      for (var d = 0; d < 10; d++) {
        expect(KeyMap.vkToKeysym(0x30 + d), 0x30 + d);
      }
    });

    test('function keys F1..F12', () {
      expect(KeyMap.vkToKeysym(0x70), 0xFFBE); // F1
      expect(KeyMap.vkToKeysym(0x7B), 0xFFC9); // F12
    });

    test('common control keys', () {
      expect(KeyMap.vkToKeysym(0x0D), 0xFF0D); // Enter
      expect(KeyMap.vkToKeysym(0x1B), 0xFF1B); // Esc
      expect(KeyMap.vkToKeysym(0x08), 0xFF08); // Backspace
      expect(KeyMap.vkToKeysym(0x25), 0xFF51); // Left arrow
    });

    test('round-trips through the reverse map', () {
      for (final vk in [0x41, 0x5A, 0x30, 0x39, 0x0D, 0x1B, 0x70, 0x7B, 0xA2]) {
        final ks = KeyMap.vkToKeysym(vk);
        expect(ks, isNotNull, reason: 'vk $vk should map');
        expect(KeyMap.keysymToVk(ks!), vk, reason: 'round-trip vk $vk');
      }
    });

    test('unmapped codes return null', () {
      expect(KeyMap.vkToKeysym(0x0999), isNull);
      expect(KeyMap.keysymToVk(0x0999), isNull);
    });
  });
}
