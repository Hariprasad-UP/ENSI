// Dev verification (Windows): start the LL-hook capture isolate, inject a few
// events (injected input also flows through low-level hooks), and confirm they
// come back out of captureStream. Proves the isolate + NativeCallable + hook
// pipeline works end to end.
// Run:  dart run tool/verify_capture.dart
import 'package:ensi/input/windows_backend.dart';
import 'package:ensi/models/input_event.dart';

Future<void> main() async {
  final backend = WindowsInputBackend();
  final got = <InputEvent>[];
  final sub = backend.captureStream().listen(got.add);

  await Future<void>.delayed(const Duration(milliseconds: 600)); // install hooks

  await backend.inject(const InputEvent(type: InputEventType.mouseMove, x: 600, y: 500));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await backend.inject(const InputEvent(type: InputEventType.keyDown, keyCode: 0x42)); // 'B'
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await backend.inject(const InputEvent(type: InputEventType.keyUp, keyCode: 0x42));

  await Future<void>.delayed(const Duration(milliseconds: 700));
  await sub.cancel();

  final hist = <InputEventType, int>{};
  for (final e in got) {
    hist[e.type] = (hist[e.type] ?? 0) + 1;
  }
  print('captured ${got.length} events: $hist');
  for (final e in got.where((e) => e.type != InputEventType.mouseMove).take(8)) {
    print('  $e');
  }
  final sawMove = got.any((e) => e.type == InputEventType.mouseMove);
  final sawKey = got.any((e) => e.type == InputEventType.keyDown && e.keyCode == 0x42);
  print((sawMove && sawKey) ? 'CAPTURE OK ✓' : 'CAPTURE INCOMPLETE ✗ (move=$sawMove key=$sawKey)');

  await backend.dispose();
}
