import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../models/device.dart';
import '../models/input_event.dart';
import 'input_backend.dart';

// Win message constants we care about.
const _wmMouseMove = 0x0200;
const _wmLButtonDown = 0x0201;
const _wmLButtonUp = 0x0202;
const _wmRButtonDown = 0x0204;
const _wmRButtonUp = 0x0205;
const _wmMButtonDown = 0x0207;
const _wmMButtonUp = 0x0208;
const _wmMouseWheel = 0x020A;
const _wmMouseHWheel = 0x020E;
const _wmKeyDown = 0x0100;
const _wmKeyUp = 0x0101;
const _wmSysKeyDown = 0x0104;
const _wmSysKeyUp = 0x0105;
const _wmQuit = 0x0012;
const _whMouseLL = 14;
const _whKeyboardLL = 13;

// Hand-bound hook/message FFI (avoids win32's Win32Result wrappers on the hot path).
typedef _HookProcNative = IntPtr Function(Int32, IntPtr, IntPtr);
typedef _SetHookNative = IntPtr Function(
    Int32, Pointer<NativeFunction<_HookProcNative>>, IntPtr, Uint32);
typedef _SetHookDart = int Function(
    int, Pointer<NativeFunction<_HookProcNative>>, int, int);
typedef _CallNextNative = IntPtr Function(IntPtr, Int32, IntPtr, IntPtr);
typedef _CallNextDart = int Function(int, int, int, int);
typedef _UnhookNative = Int32 Function(IntPtr);
typedef _UnhookDart = int Function(int);
typedef _GetMsgNative = Int32 Function(Pointer<MSG>, IntPtr, Uint32, Uint32);
typedef _GetMsgDart = int Function(Pointer<MSG>, int, int, int);
typedef _GetModuleNative = IntPtr Function(Pointer<Utf16>);
typedef _GetModuleDart = int Function(Pointer<Utf16>);
typedef _GetTidNative = Uint32 Function();
typedef _GetTidDart = int Function();
typedef _PostThreadNative = Int32 Function(Uint32, Uint32, IntPtr, IntPtr);
typedef _PostThreadDart = int Function(int, int, int, int);

/// Windows input backend (FR-10..FR-12): real injection (`SendInput`) and global
/// capture (`WH_MOUSE_LL`/`WH_KEYBOARD_LL`) via `dart:ffi`. The low-level hooks
/// run on a dedicated **hook isolate** with a Win32 message loop and
/// `NativeCallable.isolateLocal` procs (LL hooks must return synchronously). A
/// shared native flag lets the main isolate switch suppression on/off (Phase 3:
/// swallow local input while control is on a remote screen).
class WindowsInputBackend implements InputBackend {
  final _controller = StreamController<InputEvent>.broadcast();
  final Set<int> _heldKeys = {};
  final Set<int> _heldButtons = {};

  ReceivePort? _rp;
  int? _hookThreadId;
  Pointer<Int32>? _suppress;

  @override
  bool get canReceiveInput => true;

  @override
  Stream<InputEvent> captureStream() {
    _startCapture();
    return _controller.stream;
  }

  /// Phase 3 hook: when true, captured local input is swallowed (not delivered
  /// to local apps) because control is on a remote screen.
  void setSuppress(bool on) => _suppress?.value = on ? 1 : 0;

  void _startCapture() {
    if (_rp != null) return; // already capturing
    _suppress = calloc<Int32>()..value = 0;
    final rp = ReceivePort();
    _rp = rp;
    rp.listen((msg) {
      if (msg is int) {
        _hookThreadId = msg; // first message: the hook thread id
      } else if (msg is InputEvent) {
        _controller.add(msg);
      }
    });
    Isolate.spawn(_hookIsolateMain, (rp.sendPort, _suppress!.address));
  }

  Future<void> _stopCapture() async {
    final tid = _hookThreadId;
    if (tid != null) {
      final user32 = DynamicLibrary.open('user32.dll');
      final post = user32
          .lookupFunction<_PostThreadNative, _PostThreadDart>('PostThreadMessageW');
      post(tid, _wmQuit, 0, 0); // break the message loop -> isolate exits
    }
    _rp?.close();
    _rp = null;
    _hookThreadId = null;
    final s = _suppress;
    if (s != null) calloc.free(s);
    _suppress = null;
  }

  // ----------------------------- injection ---------------------------------

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
        break;
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
    if (dy != 0) _sendMouse(MOUSEEVENTF_WHEEL, mouseData: (dy * 120).round());
    if (dx != 0) _sendMouse(MOUSEEVENTF_HWHEEL, mouseData: (dx * 120).round());
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
    final w = GetSystemMetrics(SM_CXSCREEN).toDouble();
    final h = GetSystemMetrics(SM_CYSCREEN).toDouble();
    double scale = 1.0;
    try {
      scale = GetDpiForSystem() / 96.0;
    } catch (_) {/* pre-1607; assume 1.0 */}
    if (w <= 0 || h <= 0) return DisplayGeometry.single();
    return DisplayGeometry([
      MonitorGeometry(
          id: 0, left: 0, top: 0, width: w, height: h, scale: scale, isPrimary: true),
    ]);
  }

  @override
  Future<void> dispose() async {
    await releaseAllKeys();
    await _stopCapture();
    await _controller.close();
  }
}

/// Entry point of the hook isolate: installs the LL hooks and pumps messages.
/// [args] = (SendPort to main, address of the shared suppress Int32 flag).
void _hookIsolateMain((SendPort, int) args) {
  final (send, suppressAddr) = args;
  final suppress = Pointer<Int32>.fromAddress(suppressAddr);

  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setHook = user32.lookupFunction<_SetHookNative, _SetHookDart>('SetWindowsHookExW');
  final callNext = user32.lookupFunction<_CallNextNative, _CallNextDart>('CallNextHookEx');
  final unhook = user32.lookupFunction<_UnhookNative, _UnhookDart>('UnhookWindowsHookEx');
  final getMsg = user32.lookupFunction<_GetMsgNative, _GetMsgDart>('GetMessageW');
  final getModule =
      kernel32.lookupFunction<_GetModuleNative, _GetModuleDart>('GetModuleHandleW');
  final getTid = kernel32.lookupFunction<_GetTidNative, _GetTidDart>('GetCurrentThreadId');

  int onMouse(int nCode, int wParam, int lParam) {
    if (nCode >= 0) {
      final s = Pointer<MSLLHOOKSTRUCT>.fromAddress(lParam).ref;
      final ev = _mouseEvent(wParam, s);
      if (ev != null) send.send(ev);
      if (suppress.value != 0) return 1; // Phase 3: swallow when remote
    }
    return callNext(0, nCode, wParam, lParam);
  }

  int onKey(int nCode, int wParam, int lParam) {
    if (nCode >= 0) {
      final s = Pointer<KBDLLHOOKSTRUCT>.fromAddress(lParam).ref;
      final down = wParam == _wmKeyDown || wParam == _wmSysKeyDown;
      final up = wParam == _wmKeyUp || wParam == _wmSysKeyUp;
      if (down || up) {
        send.send(InputEvent(
          type: down ? InputEventType.keyDown : InputEventType.keyUp,
          keyCode: s.vkCode,
        ));
      }
      if (suppress.value != 0) return 1;
    }
    return callNext(0, nCode, wParam, lParam);
  }

  final mouseCb = NativeCallable<_HookProcNative>.isolateLocal(onMouse, exceptionalReturn: 0);
  final keyCb = NativeCallable<_HookProcNative>.isolateLocal(onKey, exceptionalReturn: 0);
  final hMod = getModule(nullptr);
  final hMouse = setHook(_whMouseLL, mouseCb.nativeFunction, hMod, 0);
  final hKey = setHook(_whKeyboardLL, keyCb.nativeFunction, hMod, 0);

  send.send(getTid()); // tell main our thread id so it can post WM_QUIT

  final msg = calloc<MSG>();
  try {
    while (getMsg(msg, 0, 0, 0) > 0) {
      // LL hooks fire during message retrieval; nothing else to dispatch.
    }
  } finally {
    if (hMouse != 0) unhook(hMouse);
    if (hKey != 0) unhook(hKey);
    mouseCb.close();
    keyCb.close();
    calloc.free(msg);
  }
}

InputEvent? _mouseEvent(int wParam, MSLLHOOKSTRUCT s) {
  switch (wParam) {
    case _wmMouseMove:
      return InputEvent(
          type: InputEventType.mouseMove,
          x: s.pt.x.toDouble(),
          y: s.pt.y.toDouble());
    case _wmLButtonDown:
      return const InputEvent(type: InputEventType.mouseDown, button: 0);
    case _wmLButtonUp:
      return const InputEvent(type: InputEventType.mouseUp, button: 0);
    case _wmRButtonDown:
      return const InputEvent(type: InputEventType.mouseDown, button: 1);
    case _wmRButtonUp:
      return const InputEvent(type: InputEventType.mouseUp, button: 1);
    case _wmMButtonDown:
      return const InputEvent(type: InputEventType.mouseDown, button: 2);
    case _wmMButtonUp:
      return const InputEvent(type: InputEventType.mouseUp, button: 2);
    case _wmMouseWheel:
      return InputEvent(type: InputEventType.mouseScroll, scrollDy: _wheelDelta(s.mouseData));
    case _wmMouseHWheel:
      return InputEvent(type: InputEventType.mouseScroll, scrollDx: _wheelDelta(s.mouseData));
  }
  return null;
}

/// High word of mouseData is a signed wheel delta; convert to notches.
double _wheelDelta(int mouseData) {
  final raw = (mouseData >> 16) & 0xFFFF;
  final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
  return signed / 120.0;
}
