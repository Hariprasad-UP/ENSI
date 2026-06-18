import 'dart:convert';

/// The category of an input event sent across the wire.
enum InputEventType {
  mouseMove,
  mouseDown,
  mouseUp,
  mouseScroll,
  keyDown,
  keyUp,
  // Control frames
  enterScreen, // cursor entered this device at (x, y)
  leaveScreen, // cursor left this device
  releaseAll, // safety: release every held key/button
}

/// A single normalized input event. Coordinates are absolute virtual-desktop
/// coordinates of the *target* device unless otherwise noted.
///
/// This is the unit forwarded from the Host to a Client (see
/// [docs/REQUIREMENTS.md] FR-10..FR-12). Serialized compactly to JSON for now;
/// a binary/protobuf encoding is a later optimization (Q-1).
class InputEvent {
  final InputEventType type;

  /// Absolute x on the target screen (mouse events).
  final double? x;

  /// Absolute y on the target screen (mouse events).
  final double? y;

  /// Scroll delta (mouseScroll).
  final double? scrollDx;
  final double? scrollDy;

  /// Mouse button index (0=left,1=right,2=middle) for mouseDown/Up.
  final int? button;

  /// Platform-independent key code (keyDown/keyUp). We use logical key ids.
  final int? keyCode;

  /// Bitmask of active modifiers (see [InputModifiers]).
  final int modifiers;

  const InputEvent({
    required this.type,
    this.x,
    this.y,
    this.scrollDx,
    this.scrollDy,
    this.button,
    this.keyCode,
    this.modifiers = 0,
  });

  Map<String, dynamic> toJson() => {
        't': type.index,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (scrollDx != null) 'sx': scrollDx,
        if (scrollDy != null) 'sy': scrollDy,
        if (button != null) 'b': button,
        if (keyCode != null) 'k': keyCode,
        if (modifiers != 0) 'm': modifiers,
      };

  factory InputEvent.fromJson(Map<String, dynamic> j) => InputEvent(
        type: InputEventType.values[j['t'] as int],
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        scrollDx: (j['sx'] as num?)?.toDouble(),
        scrollDy: (j['sy'] as num?)?.toDouble(),
        button: j['b'] as int?,
        keyCode: j['k'] as int?,
        modifiers: (j['m'] as int?) ?? 0,
      );

  /// One newline-delimited frame, ready to write to a socket.
  List<int> encodeFrame() => utf8.encode('${jsonEncode(toJson())}\n');

  static InputEvent decodeFrame(String line) =>
      InputEvent.fromJson(jsonDecode(line) as Map<String, dynamic>);

  @override
  String toString() => 'InputEvent(${type.name}, x:$x, y:$y, key:$keyCode)';
}

/// Modifier key bitmask values.
class InputModifiers {
  static const int shift = 1 << 0;
  static const int ctrl = 1 << 1;
  static const int alt = 1 << 2;
  static const int meta = 1 << 3; // Cmd / Win
}
