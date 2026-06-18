import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/device.dart';
import '../models/input_event.dart';
import 'input_backend.dart';
import 'keymap.dart';

// --- Xlib / XTest FFI signatures -------------------------------------------
typedef _XOpenDisplayC = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplay = Pointer<Void> Function(Pointer<Utf8>);
typedef _PtrIntC = Int32 Function(Pointer<Void>);
typedef _PtrInt = int Function(Pointer<Void>);
typedef _PtrScreenIntC = Int32 Function(Pointer<Void>, Int32);
typedef _PtrScreenInt = int Function(Pointer<Void>, int);
typedef _XKeysymToKeycodeC = Uint8 Function(Pointer<Void>, UnsignedLong);
typedef _XKeysymToKeycode = int Function(Pointer<Void>, int);
typedef _XTestMotionC = Int32 Function(
    Pointer<Void>, Int32, Int32, Int32, UnsignedLong);
typedef _XTestMotion = int Function(Pointer<Void>, int, int, int, int);
typedef _XTestButtonC = Int32 Function(
    Pointer<Void>, Uint32, Int32, UnsignedLong);
typedef _XTestButton = int Function(Pointer<Void>, int, int, int);
typedef _XTestKeyC = Int32 Function(Pointer<Void>, Uint32, Int32, UnsignedLong);
typedef _XTestKey = int Function(Pointer<Void>, int, int, int);

/// Linux (X11) input backend (FR-10..FR-12). M2 Phase 1 implements **injection**
/// and display query via XTest/Xlib through `dart:ffi`; global capture/grab is
/// added in Phases 2-3 — [captureStream] is empty for now.
///
/// **Wayland is unsupported** (XTest cannot inject there): on a Wayland session
/// the backend reports [canReceiveInput] = false and no-ops, with a clear log.
class LinuxX11InputBackend implements InputBackend {
  final _controller = StreamController<InputEvent>.broadcast();
  final Set<int> _heldKeycodes = {};
  final Set<int> _heldButtons = {};

  Pointer<Void> _display = nullptr;
  int _screen = 0;
  bool _available = false;

  late final _XTestMotion _fakeMotion;
  late final _XTestButton _fakeButton;
  late final _XTestKey _fakeKey;
  late final _XKeysymToKeycode _keysymToKeycode;
  late final _PtrInt _flush;
  late final _PtrScreenInt _displayWidth;
  late final _PtrScreenInt _displayHeight;
  late final _PtrInt _closeDisplay;

  LinuxX11InputBackend() {
    _init();
  }

  void _init() {
    if (!Platform.isLinux) return;
    if ((Platform.environment['XDG_SESSION_TYPE'] ?? '').toLowerCase() ==
        'wayland') {
      _log('Wayland session detected — X11 injection unavailable (see M5).');
      return;
    }
    try {
      final x11 = DynamicLibrary.open('libX11.so.6');
      final xtst = DynamicLibrary.open('libXtst.so.6');
      final openDisplay =
          x11.lookupFunction<_XOpenDisplayC, _XOpenDisplay>('XOpenDisplay');
      _closeDisplay =
          x11.lookupFunction<_PtrIntC, _PtrInt>('XCloseDisplay');
      _flush = x11.lookupFunction<_PtrIntC, _PtrInt>('XFlush');
      final defaultScreen =
          x11.lookupFunction<_PtrIntC, _PtrInt>('XDefaultScreen');
      _displayWidth =
          x11.lookupFunction<_PtrScreenIntC, _PtrScreenInt>('XDisplayWidth');
      _displayHeight =
          x11.lookupFunction<_PtrScreenIntC, _PtrScreenInt>('XDisplayHeight');
      _keysymToKeycode = x11
          .lookupFunction<_XKeysymToKeycodeC, _XKeysymToKeycode>(
              'XKeysymToKeycode');
      _fakeMotion = xtst
          .lookupFunction<_XTestMotionC, _XTestMotion>('XTestFakeMotionEvent');
      _fakeButton = xtst
          .lookupFunction<_XTestButtonC, _XTestButton>('XTestFakeButtonEvent');
      _fakeKey =
          xtst.lookupFunction<_XTestKeyC, _XTestKey>('XTestFakeKeyEvent');

      _display = openDisplay(nullptr);
      if (_display == nullptr) {
        _log('XOpenDisplay failed — no X11 server available.');
        return;
      }
      _screen = defaultScreen(_display);
      _available = true;
    } catch (e) {
      _log('X11/XTest unavailable: $e');
    }
  }

  void _log(String m) => developer.log(m, name: 'ENSI.input.linux');

  @override
  bool get canReceiveInput => _available;

  @override
  Stream<InputEvent> captureStream() => _controller.stream; // filled in Phase 2

  @override
  Future<void> inject(InputEvent e) async {
    if (!_available) return;
    switch (e.type) {
      case InputEventType.mouseMove:
        if (e.x != null && e.y != null) {
          _fakeMotion(_display, _screen, e.x!.round(), e.y!.round(), 0);
          _flush(_display);
        }
      case InputEventType.mouseDown:
        _button(e.button ?? 0, press: true);
      case InputEventType.mouseUp:
        _button(e.button ?? 0, press: false);
      case InputEventType.mouseScroll:
        _scroll(e.scrollDx ?? 0, e.scrollDy ?? 0);
      case InputEventType.keyDown:
        if (e.keyCode != null) _key(e.keyCode!, press: true);
      case InputEventType.keyUp:
        if (e.keyCode != null) _key(e.keyCode!, press: false);
      case InputEventType.releaseAll:
        await releaseAllKeys();
      case InputEventType.enterScreen:
      case InputEventType.leaveScreen:
        break;
    }
  }

  // ENSI button 0=left,1=right,2=middle -> X11 button 1=left,2=middle,3=right.
  int _xButton(int b) => b == 1 ? 3 : (b == 2 ? 2 : 1);

  void _button(int button, {required bool press}) {
    final xb = _xButton(button);
    if (press) {
      _heldButtons.add(xb);
    } else {
      _heldButtons.remove(xb);
    }
    _fakeButton(_display, xb, press ? 1 : 0, 0);
    _flush(_display);
  }

  void _scroll(double dx, double dy) {
    // X11 maps wheel to button clicks: 4=up, 5=down, 6=left, 7=right.
    void click(int b, int times) {
      for (var i = 0; i < times; i++) {
        _fakeButton(_display, b, 1, 0);
        _fakeButton(_display, b, 0, 0);
      }
      _flush(_display);
    }

    if (dy != 0) click(dy > 0 ? 4 : 5, dy.abs().ceil());
    if (dx != 0) click(dx > 0 ? 7 : 6, dx.abs().ceil());
  }

  void _key(int vk, {required bool press}) {
    final keysym = KeyMap.vkToKeysym(vk);
    if (keysym == null) return;
    final keycode = _keysymToKeycode(_display, keysym);
    if (keycode == 0) return;
    if (press) {
      _heldKeycodes.add(keycode);
    } else {
      _heldKeycodes.remove(keycode);
    }
    _fakeKey(_display, keycode, press ? 1 : 0, 0);
    _flush(_display);
  }

  @override
  Future<void> releaseAllKeys() async {
    if (!_available) return;
    for (final kc in _heldKeycodes.toList()) {
      _fakeKey(_display, kc, 0, 0);
    }
    for (final b in _heldButtons.toList()) {
      _fakeButton(_display, b, 0, 0);
    }
    _heldKeycodes.clear();
    _heldButtons.clear();
    _flush(_display);
  }

  @override
  Future<DisplayGeometry> queryDisplays() async {
    if (!_available) return DisplayGeometry.single();
    final w = _displayWidth(_display, _screen).toDouble();
    final h = _displayHeight(_display, _screen).toDouble();
    if (w <= 0 || h <= 0) return DisplayGeometry.single();
    return DisplayGeometry([
      MonitorGeometry(
          id: 0, left: 0, top: 0, width: w, height: h, isPrimary: true),
    ]);
  }

  @override
  Future<void> dispose() async {
    await releaseAllKeys();
    if (_display != nullptr) _closeDisplay(_display);
    _display = nullptr;
    _available = false;
    await _controller.close();
  }
}
