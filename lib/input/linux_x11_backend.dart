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
typedef _XRootC = UnsignedLong Function(Pointer<Void>);
typedef _XRoot = int Function(Pointer<Void>);
typedef _XWarpC = Int32 Function(Pointer<Void>, UnsignedLong, UnsignedLong,
    Int32, Int32, Uint32, Uint32, Int32, Int32);
typedef _XWarp = int Function(
    Pointer<Void>, int, int, int, int, int, int, int, int);
typedef _XQueryC = Int32 Function(
    Pointer<Void>,
    UnsignedLong,
    Pointer<UnsignedLong>,
    Pointer<UnsignedLong>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Uint32>);
typedef _XQuery = int Function(Pointer<Void>, int, Pointer<UnsignedLong>,
    Pointer<UnsignedLong>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>,
    Pointer<Int32>, Pointer<Uint32>);
typedef _XGrabPtrC = Int32 Function(Pointer<Void>, UnsignedLong, Int32, Uint32,
    Int32, Int32, UnsignedLong, UnsignedLong, UnsignedLong);
typedef _XGrabPtr = int Function(
    Pointer<Void>, int, int, int, int, int, int, int, int);
typedef _XGrabKbdC = Int32 Function(
    Pointer<Void>, UnsignedLong, Int32, Int32, Int32, UnsignedLong);
typedef _XGrabKbd = int Function(Pointer<Void>, int, int, int, int, int);
typedef _XUngrabC = Int32 Function(Pointer<Void>, UnsignedLong);
typedef _XUngrab = int Function(Pointer<Void>, int);

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
  late final _XWarp _warp;
  late final _XQuery _query;
  late final _XGrabPtr _grabPtr;
  late final _XGrabKbd _grabKbd;
  late final _XUngrab _ungrabPtr;
  late final _XUngrab _ungrabKbd;
  int _root = 0;

  // Poll-based capture (no XNextEvent): a timer samples the pointer so the host
  // can detect edges (FR-17). Motion + buttons only for now; capturing keyboard
  // from a Linux host is a follow-up. Experimental — validate on Xorg hardware.
  Timer? _pollTimer;
  int _lastX = -1, _lastY = -1, _lastMask = 0;
  Pointer<UnsignedLong>? _qRoot, _qChild;
  Pointer<Int32>? _qRx, _qRy, _qWx, _qWy;
  Pointer<Uint32>? _qMask;

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
      _root = x11.lookupFunction<_XRootC, _XRoot>('XDefaultRootWindow')(_display);
      _warp = x11.lookupFunction<_XWarpC, _XWarp>('XWarpPointer');
      _query = x11.lookupFunction<_XQueryC, _XQuery>('XQueryPointer');
      _grabPtr = x11.lookupFunction<_XGrabPtrC, _XGrabPtr>('XGrabPointer');
      _grabKbd = x11.lookupFunction<_XGrabKbdC, _XGrabKbd>('XGrabKeyboard');
      _ungrabPtr = x11.lookupFunction<_XUngrabC, _XUngrab>('XUngrabPointer');
      _ungrabKbd = x11.lookupFunction<_XUngrabC, _XUngrab>('XUngrabKeyboard');
      _qRoot = calloc<UnsignedLong>();
      _qChild = calloc<UnsignedLong>();
      _qRx = calloc<Int32>();
      _qRy = calloc<Int32>();
      _qWx = calloc<Int32>();
      _qWy = calloc<Int32>();
      _qMask = calloc<Uint32>();
      _available = true;
    } catch (e) {
      _log('X11/XTest unavailable: $e');
    }
  }

  void _log(String m) => developer.log(m, name: 'ENSI.input.linux');

  @override
  bool get canReceiveInput => _available;

  @override
  Stream<InputEvent> captureStream() {
    if (_available && _pollTimer == null) {
      _pollTimer =
          Timer.periodic(const Duration(milliseconds: 8), (_) => _poll());
    }
    return _controller.stream;
  }

  void _poll() {
    final ok = _query(_display, _root, _qRoot!, _qChild!, _qRx!, _qRy!, _qWx!,
        _qWy!, _qMask!);
    if (ok == 0) return;
    final x = _qRx!.value, y = _qRy!.value, mask = _qMask!.value;
    if (x != _lastX || y != _lastY) {
      _lastX = x;
      _lastY = y;
      _controller.add(InputEvent(
          type: InputEventType.mouseMove, x: x.toDouble(), y: y.toDouble()));
    }
    _diffButton(mask, 1 << 8, 0); // Button1 -> left
    _diffButton(mask, 1 << 9, 2); // Button2 -> middle
    _diffButton(mask, 1 << 10, 1); // Button3 -> right
    _lastMask = mask;
  }

  void _diffButton(int mask, int bit, int ourButton) {
    final now = (mask & bit) != 0;
    final was = (_lastMask & bit) != 0;
    if (now && !was) {
      _controller
          .add(InputEvent(type: InputEventType.mouseDown, button: ourButton));
    } else if (!now && was) {
      _controller
          .add(InputEvent(type: InputEventType.mouseUp, button: ourButton));
    }
  }

  @override
  void warpCursor(double x, double y) {
    if (!_available) return;
    _warp(_display, 0, _root, 0, 0, 0, 0, x.round(), y.round());
    _flush(_display);
    _lastX = x.round(); // don't emit the warp itself as motion
    _lastY = y.round();
  }

  @override
  void suppressLocal(bool on) {
    if (!_available) return;
    if (on) {
      const mask = (1 << 2) | (1 << 3) | (1 << 6); // Btn press/release + motion
      _grabPtr(_display, _root, 0, mask, 1, 1, 0, 0, 0); // GrabModeAsync
      _grabKbd(_display, _root, 0, 1, 1, 0);
    } else {
      _ungrabPtr(_display, 0); // CurrentTime
      _ungrabKbd(_display, 0);
    }
    _flush(_display);
  }

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
        if (e.x != null && e.y != null) {
          _fakeMotion(_display, _screen, e.x!.round(), e.y!.round(), 0);
          _flush(_display);
        }
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
    _pollTimer?.cancel();
    _pollTimer = null;
    await releaseAllKeys();
    if (_available) suppressLocal(false); // ensure ungrabbed
    if (_display != nullptr) _closeDisplay(_display);
    _display = nullptr;
    _available = false;
    for (final p in [_qRoot, _qChild, _qRx, _qRy, _qWx, _qWy, _qMask]) {
      if (p != null) calloc.free(p);
    }
    await _controller.close();
  }
}
