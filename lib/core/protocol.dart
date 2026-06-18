import 'dart:convert';

import '../models/device.dart';
import '../models/input_event.dart';

/// The kind of frame on the ENSI session stream. Input events share the wire
/// with the small set of control frames that drive pairing + liveness.
enum MessageKind {
  /// First frame after TLS connect: who I am + my cert fingerprint.
  hello,

  /// Host -> client: pairing approved (each side then pins the other).
  paired,

  /// Either side: pairing rejected / session refused.
  reject,

  /// Liveness keep-alive (NFR-2). No payload.
  heartbeat,

  /// A captured/injected input event (FR-10..FR-12).
  event,

  /// Shared clipboard text (FR-21).
  clipboard,
}

/// A single framed message exchanged over the (TLS) session transport.
///
/// Serialized as one newline-delimited JSON object, reusing the framing approach
/// of [InputEvent.encodeFrame]. The SAS pairing code is intentionally **never**
/// sent — both sides derive it locally from the exchanged [hello] fingerprints.
class Message {
  final MessageKind kind;
  final DeviceInfo? device; // hello
  final String? fingerprint; // hello
  final InputEvent? event; // event
  final String? text; // clipboard

  const Message({
    required this.kind,
    this.device,
    this.fingerprint,
    this.event,
    this.text,
  });

  factory Message.hello(DeviceInfo device, String fingerprint) =>
      Message(kind: MessageKind.hello, device: device, fingerprint: fingerprint);

  factory Message.event(InputEvent event) =>
      Message(kind: MessageKind.event, event: event);

  factory Message.clipboard(String text) =>
      Message(kind: MessageKind.clipboard, text: text);

  const Message.paired() : this._control(MessageKind.paired);
  const Message.reject() : this._control(MessageKind.reject);
  const Message.heartbeat() : this._control(MessageKind.heartbeat);

  const Message._control(this.kind)
      : device = null,
        fingerprint = null,
        event = null,
        text = null;

  Map<String, dynamic> toJson() => {
        'k': kind.index,
        if (device != null) 'd': device!.toJson(),
        if (fingerprint != null) 'f': fingerprint,
        if (event != null) 'e': event!.toJson(),
        if (text != null) 'c': text,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        kind: MessageKind.values[j['k'] as int],
        device: j['d'] == null
            ? null
            : DeviceInfo.fromJson(j['d'] as Map<String, dynamic>),
        fingerprint: j['f'] as String?,
        event: j['e'] == null
            ? null
            : InputEvent.fromJson(j['e'] as Map<String, dynamic>),
        text: j['c'] as String?,
      );

  /// One newline-delimited frame, ready to write to a socket.
  List<int> encodeFrame() => utf8.encode('${jsonEncode(toJson())}\n');

  static Message decodeFrame(String line) =>
      Message.fromJson(jsonDecode(line) as Map<String, dynamic>);

  @override
  String toString() => 'Message(${kind.name})';
}
