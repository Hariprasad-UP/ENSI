import 'dart:async';

import '../input/input_backend.dart';
import '../models/device.dart';
import '../models/input_event.dart';
import 'pairing.dart';
import 'protocol.dart';
import 'transport.dart';
import 'trust_store.dart';

/// Lifecycle of a single peer session.
enum SessionPhase {
  /// TLS up; `hello` frames being exchanged.
  handshaking,

  /// Untrusted peer — awaiting SAS confirmation (host approves).
  pairing,

  /// Trusted + live; input/heartbeats flow.
  connected,

  /// Pairing refused.
  rejected,

  /// Link torn down (timeout, drop, or reset).
  closed,
}

/// A pairing awaiting user attention, surfaced to the UI.
class PendingPairing {
  final String peerId;
  final String peerName;

  /// The 6-digit SAS shown on both devices (FR-4).
  final String code;

  /// True on the device whose keyboard is shared (shows Approve/Reject); the
  /// other side just displays the code and waits.
  final bool isHost;

  const PendingPairing({
    required this.peerId,
    required this.peerName,
    required this.code,
    required this.isHost,
  });
}

/// Drives one peer connection: the hello/SAS/paired handshake, liveness
/// (heartbeat + watchdog), trust gating (FR-25), and clean teardown with
/// `releaseAllKeys()` so no modifier sticks after a drop (NFR-2).
class PeerSession {
  final PeerLink link;
  final DeviceInfo self;
  final String selfFingerprint;
  final TrustStore trust;
  final InputBackend backend;

  /// True if this device is the Host of the session.
  final bool isHost;

  /// Notify the owner (AppState) of any state change.
  final void Function() onChanged;

  /// Deliver a received input event (client injects; host ignores for now).
  final void Function(InputEvent event) onInput;

  static const _heartbeat = Duration(seconds: 2);
  static const _timeout = Duration(seconds: 6);

  SessionPhase phase = SessionPhase.handshaking;
  DeviceInfo? peer;
  String code = '';

  /// Effective peer fingerprint: the cryptographic TLS cert fingerprint when we
  /// have it (client side sees the host's cert), otherwise the one asserted in
  /// the peer's `hello` (host side — `dart:io` can't present self-signed client
  /// certs). SAS stays MITM-safe because the client side is always cryptographic.
  String _peerFp = '';

  Timer? _hbTimer;
  Timer? _watchdog;
  bool _disposed = false;

  PeerSession({
    required this.link,
    required this.self,
    required this.selfFingerprint,
    required this.trust,
    required this.backend,
    required this.isHost,
    required this.onChanged,
    required this.onInput,
  }) {
    _start();
  }

  String get peerFingerprint => _peerFp;
  String? get peerId => peer?.id;

  void _start() {
    _peerFp = link.peerFingerprint; // cryptographic on the client side
    link.incoming.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
    link.send(Message.hello(self, selfFingerprint));
    _hbTimer = Timer.periodic(_heartbeat, (_) => link.send(const Message.heartbeat()));
    _resetWatchdog();
  }

  Future<void> _onMessage(Message m) async {
    _resetWatchdog();
    switch (m.kind) {
      case MessageKind.hello:
        peer = m.device;
        if (_peerFp.isEmpty) _peerFp = m.fingerprint ?? ''; // host learns it here
        code = sasCode(selfFingerprint, _peerFp);
        phase = (peer != null &&
                _peerFp.isNotEmpty &&
                trust.isTrusted(peer!.id, _peerFp))
            ? SessionPhase.connected
            : SessionPhase.pairing;
        onChanged();
      case MessageKind.paired:
        await _pinPeer(); // host approved us — pin the host
        phase = SessionPhase.connected;
        onChanged();
      case MessageKind.reject:
        await _terminate(SessionPhase.rejected);
      case MessageKind.heartbeat:
        break; // liveness only; watchdog already reset
      case MessageKind.event:
        final p = peer;
        if (phase == SessionPhase.connected &&
            p != null &&
            trust.isTrusted(p.id, peerFingerprint) && // FR-25 gate
            m.event != null) {
          onInput(m.event!);
        }
    }
  }

  /// Host action: approve the pending pairing — pin the peer and go live.
  Future<void> approve() async {
    if (peer == null) return;
    await _pinPeer();
    link.send(const Message.paired());
    phase = SessionPhase.connected;
    onChanged();
  }

  /// Reject pairing and tear the session down.
  Future<void> reject() async {
    link.send(const Message.reject());
    await _terminate(SessionPhase.rejected);
  }

  /// Forward a captured input event to a connected, trusted peer.
  void sendInput(InputEvent event) {
    if (phase == SessionPhase.connected) link.send(Message.event(event));
  }

  Future<void> _pinPeer() async {
    final p = peer;
    if (p == null) return;
    await trust.trust(TrustedPeer(
      id: p.id,
      name: p.name,
      platform: p.platform,
      fingerprint: peerFingerprint,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _resetWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_timeout, _onTimeout);
  }

  Future<void> _onTimeout() async {
    await backend.releaseAllKeys(); // NFR-2
    await _terminate(SessionPhase.closed);
  }

  void _onClosed() {
    backend.releaseAllKeys(); // NFR-2
    _terminate(SessionPhase.closed);
  }

  /// Public teardown (AppState.reset / revoke).
  Future<void> dispose() => _terminate(SessionPhase.closed);

  Future<void> _terminate(SessionPhase finalPhase) async {
    if (_disposed) return;
    _disposed = true;
    _hbTimer?.cancel();
    _watchdog?.cancel();
    phase = finalPhase;
    await link.dispose();
    onChanged();
  }
}
