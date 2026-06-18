import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/input_event.dart';

/// Default TCP port for the ENSI input stream.
const int kEnsiPort = 24800;

/// Host-side transport: listens for client connections and broadcasts captured
/// [InputEvent]s to the active client (FR-7, FR-10..FR-12).
///
/// v1 uses a plain [ServerSocket]; this MUST be upgraded to [SecureSocket]
/// (TLS) before any real input flows (FR-24, NFR-4). Pairing/trust gating
/// (FR-25) is enforced one layer up in the session manager.
class HostTransport {
  ServerSocket? _server;
  final List<Socket> _clients = [];

  final _incoming = StreamController<InputEvent>.broadcast();

  /// Events received *from* clients (e.g. a mobile input-sender, FR-14).
  Stream<InputEvent> get incoming => _incoming.stream;

  Future<void> start({int port = kEnsiPort}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_onClient);
  }

  void _onClient(Socket socket) {
    _clients.add(socket);
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        try {
          _incoming.add(InputEvent.decodeFrame(line));
        } catch (_) {/* ignore malformed frame */}
      },
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
    );
  }

  /// Forward an event to all connected clients. (Targeting a *specific* client
  /// based on the layout edge-switch is handled by the session manager.)
  void send(InputEvent event) {
    final frame = event.encodeFrame();
    for (final c in _clients) {
      c.add(frame);
    }
  }

  Future<void> stop() async {
    // Iterate a copy: destroy() fires each socket's onDone, which mutates
    // _clients (concurrent-modification otherwise).
    for (final c in List<Socket>.of(_clients)) {
      c.destroy();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _incoming.close();
  }
}

/// Client-side transport: connects to a Host and receives [InputEvent]s to be
/// injected locally.
class ClientTransport {
  Socket? _socket;
  final _incoming = StreamController<InputEvent>.broadcast();

  /// Events received from the Host, to be injected via the InputBackend.
  Stream<InputEvent> get incoming => _incoming.stream;

  Future<void> connect(String host, {int port = kEnsiPort}) async {
    final socket = await Socket.connect(host, port);
    _socket = socket;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        try {
          _incoming.add(InputEvent.decodeFrame(line));
        } catch (_) {/* ignore malformed frame */}
      },
      onDone: () => _incoming.close(),
      onError: (_) => _incoming.close(),
    );
  }

  /// Send an event to the Host (used by mobile input-sender, FR-14).
  void send(InputEvent event) => _socket?.add(event.encodeFrame());

  Future<void> dispose() async {
    _socket?.destroy();
    _socket = null;
    if (!_incoming.isClosed) await _incoming.close();
  }
}
