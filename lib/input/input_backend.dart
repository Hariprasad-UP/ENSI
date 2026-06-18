import 'dart:io';

import '../models/device.dart';
import '../models/input_event.dart';
import 'linux_x11_backend.dart';
import 'stub_backend.dart';
import 'windows_backend.dart';

/// Platform abstraction for capturing and injecting OS-level input.
///
/// **This is the hard core of ENSI** (see [docs/REQUIREMENTS.md] §2.4 C-1 and
/// §5.2). Flutter/Dart cannot capture global input or inject OS-level input on
/// its own — every desktop platform needs native code reached via `dart:ffi`
/// or a platform channel:
///
/// * Windows  — capture: `SetWindowsHookEx` (WH_KEYBOARD_LL/WH_MOUSE_LL);
///              inject: `SendInput`.
/// * macOS    — capture: `CGEventTap`; inject: `CGEventPost`
///              (requires Accessibility + Input Monitoring permission).
/// * Linux X11 — capture: `XInput2`; inject: `XTEST`.
/// * Linux Wayland — capture/inject via `libinput` + `/dev/uinput` (restricted).
/// * Mobile   — sender only (C-2): no [captureStream]/[inject] of OS input;
///              builds [InputEvent]s from an on-screen touchpad/keyboard.
///
/// The concrete implementations live behind this interface so the rest of the
/// app is platform-agnostic. Until the native layers land, [StubInputBackend]
/// is used everywhere and logs instead of touching the OS.
abstract class InputBackend {
  /// Host side: a stream of input events captured from the physical devices.
  /// Implementations should grab/suppress local delivery while the cursor is
  /// on a remote screen.
  Stream<InputEvent> captureStream();

  /// Client side: inject an event into the local OS.
  Future<void> inject(InputEvent event);

  /// Report this device's monitors/resolution/scaling (FR-16).
  Future<DisplayGeometry> queryDisplays();

  /// Safety: release every held key and mouse button. MUST be called on
  /// disconnect to avoid stuck modifiers (NFR-2).
  Future<void> releaseAllKeys();

  /// Whether this backend can inject OS-level input (false on mobile).
  bool get canReceiveInput;

  /// Host edge-switch (FR-17): suppress (true) or restore (false) local OS input
  /// delivery while the cursor is on a remote screen. No-op where unsupported.
  void suppressLocal(bool on);

  /// Warp the local cursor to (x, y) in this device's pixels (host side, used to
  /// recentre while routing and to return the cursor on edge-back).
  void warpCursor(double x, double y);

  Future<void> dispose();

  /// Returns the appropriate backend for the current platform. For now every
  /// platform gets the stub; real backends are wired here as they land.
  static InputBackend forCurrentPlatform() {
    if (Platform.isWindows) return WindowsInputBackend();
    if (Platform.isMacOS) return StubInputBackend(label: 'macos');
    if (Platform.isLinux) return LinuxX11InputBackend();
    if (Platform.isAndroid) {
      return StubInputBackend(label: 'android', canReceive: false);
    }
    if (Platform.isIOS) {
      return StubInputBackend(label: 'ios', canReceive: false);
    }
    return StubInputBackend(label: 'unknown', canReceive: false);
  }
}
