import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cert_service.dart';
import 'protocol.dart';

/// Default TCP port for the ENSI session stream.
const int kEnsiPort = 24800;

/// One established, **TLS-encrypted** session to a single peer (FR-24, NFR-4),
/// carrying newline-framed [Message]s in both directions. The peer's certificate
/// [fingerprint] (captured from the TLS handshake) is the authoritative identity
/// used for pairing/trust — see `session.dart` and [TrustStore].
class PeerLink {
  final SecureSocket socket;

  /// SHA-256 of the peer's TLS certificate, or '' if none was presented.
  final String peerFingerprint;

  final _incoming = StreamController<Message>.broadcast();
  bool _closed = false;

  PeerLink(this.socket, this.peerFingerprint) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        try {
          _incoming.add(Message.decodeFrame(line));
        } catch (_) {/* ignore malformed frame */}
      },
      onDone: _close,
      onError: (_) => _close(),
    );
  }

  Stream<Message> get incoming => _incoming.stream;

  void send(Message message) {
    if (_closed) return;
    try {
      socket.add(message.encodeFrame());
    } catch (_) {/* socket gone; watchdog/onDone will clean up */}
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) _incoming.close();
  }

  Future<void> dispose() async {
    _close();
    socket.destroy();
  }

  static String _fingerprintOf(SecureSocket socket) {
    final cert = socket.peerCertificate;
    return cert == null ? '' : CertService.fingerprintOf(cert);
  }
}

/// Host side: accepts TLS client connections and surfaces each as a [PeerLink]
/// on [connections]. Targeting input to the right client by layout edge is the
/// session/layout layer's job; [broadcast] sends to all current links.
///
/// TLS is **server-authenticated**: the host presents its cert and the client
/// pins it (cryptographic). `dart:io` cannot accept a self-signed *client* cert,
/// so the host learns the client's fingerprint from the `hello` frame instead;
/// SAS pairing stays MITM-safe because it is anchored on the client's
/// cryptographic view of the host cert (see `session.dart`).
class HostTransport {
  SecureServerSocket? _server;
  final List<PeerLink> _links = [];
  final _connections = StreamController<PeerLink>.broadcast();

  Stream<PeerLink> get connections => _connections.stream;
  List<PeerLink> get links => List.unmodifiable(_links);

  Future<void> start({
    int port = kEnsiPort,
    required SecurityContext context,
  }) async {
    _server = await SecureServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      context,
    );
    _server!.listen(_onClient);
  }

  void _onClient(SecureSocket socket) {
    final link = PeerLink(socket, PeerLink._fingerprintOf(socket));
    _links.add(link);
    // Drop the link from the list when its stream ends.
    link.incoming.listen((_) {}, onDone: () => _links.remove(link));
    _connections.add(link);
  }

  void broadcast(Message message) {
    for (final l in List<PeerLink>.of(_links)) {
      l.send(message);
    }
  }

  Future<void> stop() async {
    for (final l in List<PeerLink>.of(_links)) {
      await l.dispose();
    }
    _links.clear();
    await _server?.close();
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _connections.close();
  }
}

/// Client side: opens a TLS connection to a host and returns the [PeerLink].
/// Self-signed peer certs are accepted at the TLS layer ([onBadCertificate] →
/// true); identity is then verified out-of-band by SAS pairing + fingerprint
/// pinning, not by a CA.
class ClientTransport {
  PeerLink? _link;
  PeerLink? get link => _link;

  Future<PeerLink> connect(
    String host, {
    int port = kEnsiPort,
    required SecurityContext context,
  }) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      context: context,
      onBadCertificate: (_) => true, // TOFU: pin via fingerprint after pairing
    );
    final link = PeerLink(socket, PeerLink._fingerprintOf(socket));
    _link = link;
    return link;
  }

  Future<void> dispose() async {
    await _link?.dispose();
    _link = null;
  }
}
