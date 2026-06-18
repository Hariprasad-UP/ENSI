import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../models/device.dart';
import '../models/input_event.dart';
import 'input_backend.dart';

/// Windows input backend (FR-10..FR-12). M2 Phase 1 implements **injection** and
/// display query via `dart:ffi`/Win32 (`SendInput`, `GetSystemMetrics`); global
/// capture (low-level hooks) is added in Phase 2 — [captureStream] is empty for
/// now. ENSI's neutral key code is the Win32 virtual-key code, so keyboard
/// injection is a direct `SendInput` with `wVk = keyCode`.
class WindowsInputBackend implements InputBackend {
  final _controller = StreamController<InputEvent>.broadcast();
  final Set<int> _heldKeys = {};
  final Set<int> _heldButtons = {};

  @override
  bool get canReceiveInput => true;

  @override
  Stream<InputEvent> captureStream() => _controller.stream; // filled in Phase 2

  @override
  Future<void> inject(InputEvent e) async {
    switch (e.type) {
      case InputEventType.mouseMove:
        if (e.x != null && e.y != null) _moveAbsolute(e.x!, e.y!);
      case InputEventType.mouseDown:
        _mouseButton(e.button ?? 0, down: true);
      case InputEventType.mouseUp:
        _mouseButton(e.button ?? 0, down: false);
      case InputEventType.mouseScroll:
        _scroll(e.scrollDx ?? 0, e.scrollDy ?? 0);
      case InputEventType.keyDown:
        if (e.keyCode != null) _key(e.keyCode!, down: true);
      case InputEventType.keyUp:
        if (e.keyCode != null) _key(e.keyCode!, down: false);
      case InputEventType.releaseAll:
        await releaseAllKeys();
      case InputEventType.enterScreen:
      case InputEventType.leaveScreen:
        break; // control frames; not injected
    }
  }

  void _moveAbsolute(double x, double y) {
    final vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (vw <= 1 || vh <= 1) return;
    final nx = (((x - vx) * 65535) / (vw - 1)).round().clamp(0, 65535);
    final ny = (((y - vy) * 65535) / (vh - 1)).round().clamp(0, 65535);
    _sendMouse(
      MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
      dx: nx,
      dy: ny,
    );
  }

  void _mouseButton(int button, {required bool down}) {
    final MOUSE_EVENT_FLAGS flag;
    switch (button) {
      case 1:
        flag = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
      case 2:
        flag = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
      default:
        flag = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    }
    if (down) {
      _heldButtons.add(button);
    } else {
      _heldButtons.remove(button);
    }
    _sendMouse(flag);
  }

  void _scroll(double dx, double dy) {
    if (dy != 0) {
      _sendMouse(MOUSEEVENTF_WHEEL, mouseData: (dy * 120).round());
    }
    if (dx != 0) {
      _sendMouse(MOUSEEVENTF_HWHEEL, mouseData: (dx * 120).round());
    }
  }

  void _key(int vk, {required bool down}) {
    if (down) {
      _heldKeys.add(vk);
    } else {
      _heldKeys.remove(vk);
    }
    final p = calloc<INPUT>();
    try {
      p.ref.type = INPUT_KEYBOARD;
      p.ref.ki.wVk = VIRTUAL_KEY(vk);
      p.ref.ki.dwFlags = down ? const KEYBD_EVENT_FLAGS(0) : KEYEVENTF_KEYUP;
      SendInput(1, p, sizeOf<INPUT>());
    } finally {
      calloc.free(p);
    }
  }

  void _sendMouse(MOUSE_EVENT_FLAGS flags,
      {int dx = 0, int dy = 0, int mouseData = 0}) {
    final p = calloc<INPUT>();
    try {
      p.ref.type = INPUT_MOUSE;
      p.ref.mi.dx = dx;
      p.ref.mi.dy = dy;
      p.ref.mi.mouseData = mouseData;
      p.ref.mi.dwFlags = flags;
      SendInput(1, p, sizeOf<INPUT>());
    } finally {
      calloc.free(p);
    }
  }

  @override
  Future<void> releaseAllKeys() async {
    for (final vk in _heldKeys.toList()) {
      _key(vk, down: false);
    }
    for (final b in _heldButtons.toList()) {
      _mouseButton(b, down: false);
    }
    _heldKeys.clear();
    _heldButtons.clear();
  }

  @override
  Future<DisplayGeometry> queryDisplays() async {
    // Phase 1: report the primary screen + system DPI scale. Full multi-monitor
    // enumeration (EnumDisplayMonitors) is a later refinement.
    final w = GetSystemMetrics(SM_CXSCREEN).toDouble();
    final h = GetSystemMetrics(SM_CYSCREEN).toDouble();
    double scale = 1.0;
    try {
      scale = GetDpiForSystem() / 96.0;
    } catch (_) {/* pre-1607; assume 1.0 */}
    if (w <= 0 || h <= 0) return DisplayGeometry.single();
    return DisplayGeometry([
      MonitorGeometry(
        id: 0,
        left: 0,
        top: 0,
        width: w,
        height: h,
        scale: scale,
        isPrimary: true,
      ),
    ]);
  }

  @override
  Future<void> dispose() async {
    await releaseAllKeys();
    await _controller.close();
  }
}
