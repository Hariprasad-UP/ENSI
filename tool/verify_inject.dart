// Dev verification (Windows): inject an absolute mouse move via the real
// WindowsInputBackend and read the cursor back to confirm SendInput works.
// Run:  dart run tool/verify_inject.dart
import 'dart:ffi';

import 'package:ensi/input/windows_backend.dart';
import 'package:ensi/models/input_event.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

Future<void> main() async {
  final backend = WindowsInputBackend();
  final pt = calloc<POINT>();
  try {
    GetCursorPos(pt);
    final ox = pt.ref.x, oy = pt.ref.y;
    print('cursor was at $ox,$oy');

    const targetX = 400.0, targetY = 350.0;
    await backend.inject(const InputEvent(
        type: InputEventType.mouseMove, x: targetX, y: targetY));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    GetCursorPos(pt);
    final nx = pt.ref.x, ny = pt.ref.y;
    print('cursor now at $nx,$ny (target $targetX,$targetY)');

    final ok = (nx - targetX).abs() <= 2 && (ny - targetY).abs() <= 2;
    print(ok ? 'INJECT OK ✓' : 'INJECT MISMATCH ✗');

    // restore original position
    await backend.inject(InputEvent(
        type: InputEventType.mouseMove, x: ox.toDouble(), y: oy.toDouble()));
  } finally {
    calloc.free(pt);
    await backend.dispose();
  }
}
