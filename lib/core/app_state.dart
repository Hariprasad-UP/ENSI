import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../input/input_backend.dart';
import '../models/device.dart';
import '../models/input_event.dart';
import '../models/peer.dart';
import 'cert_service.dart';
import 'control_router.dart';
import 'discovery_service.dart';
import 'identity.dart';
import 'layout_manager.dart';
import 'layout_store.dart';
import 'session.dart';
import 'transport.dart';
import 'trust_store.dart';

/// Central application state shared across the UI via `provider` (FR-2, FR-6).
///
/// Wires together the [InputBackend], [DiscoveryService], TLS transports, the
/// [CertService] identity, the [TrustStore], and per-peer [PeerSession]s. M1
/// brings discovery, SAS pairing, and an encrypted session online; actual OS
/// input capture/injection remains stubbed until M2.
class AppState extends ChangeNotifier {
  final InputBackend backend;
  final DiscoveryService discovery;
  final LayoutManager layout = LayoutManager();
  final TrustStore trust = TrustStore();
  final LayoutStore _layoutStore = LayoutStore();

  DeviceInfo? _self;
  CertService? _cert;
  DeviceRole _role = DeviceRole.idle;
  final List<Peer> _peers = [];
  final List<PeerSession> _sessions = [];
  PendingPairing? _pendingPairing;
  ControlRouter? _router;
  Timer? _clipTimer;
  String _lastClipboard = '';

  HostTransport? _hostTransport;
  ClientTransport? _clientTransport;
  StreamSubscription<List<Peer>>? _peerSub;
  StreamSubscription<PeerLink>? _hostConnSub;
  StreamSubscription<InputEvent>? _captureSub;

  AppState({required this.backend, required this.discovery});

  DeviceInfo? get self => _self;
  String? get fingerprint => _cert?.fingerprint;
  DeviceRole get role => _role;
  List<Peer> get peers => List.unmodifiable(_peers);
  List<TrustedPeer> get trustedPeers => trust.list();

  /// A pairing currently awaiting user action (SAS approve/wait), or null.
  PendingPairing? get pendingPairing => _pendingPairing;

  /// Initialize identity + TLS cert + trust store, then start LAN discovery and
  /// begin advertising (FR-1).
  Future<void> init() async {
    _self = await IdentityService.load(backend);
    _cert = await CertService.loadOrCreate(_self!.id);
    await trust.load();
    await _layoutStore.load();
    // Place this device on the shared layout (saved position, else origin).
    final myDisplays = await backend.queryDisplays();
    final myOff = _layoutStore.offsetFor(_self!.id);
    layout.placeDevice(_self!.id, myDisplays,
        offsetX: myOff?.x ?? 0, offsetY: myOff?.y ?? 0);
    _peerSub = discovery.peers.listen(_onPeersUpdated);
    await discovery.start();
    await discovery.advertise(_self!, kEnsiPort, fingerprint: _cert!.fingerprint);
    // Shared clipboard (FR-21): poll the local clipboard and sync changes.
    _clipTimer = Timer.periodic(
        const Duration(milliseconds: 700), (_) => _pollClipboard());
    notifyListeners();
  }

  Future<void> _pollClipboard() async {
    if (_sessions.isEmpty) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || text == _lastClipboard) return;
    _lastClipboard = text;
    for (final s in List<PeerSession>.of(_sessions)) {
      s.sendClipboard(text);
    }
  }

  void _onRemoteClipboard(String text) {
    if (text == _lastClipboard) return;
    _lastClipboard = text; // record first so the poll doesn't echo it back
    Clipboard.setData(ClipboardData(text: text));
  }

  void _onPeersUpdated(List<Peer> found) {
    for (final p in found) {
      if (!_peers.contains(p)) {
        // Reflect any existing trust immediately in the discovered list.
        p.trusted = discovery.fingerprintFor(p.info.id) != null &&
            trust.isTrusted(p.info.id, discovery.fingerprintFor(p.info.id)!);
        _peers.add(p);
      }
    }
    notifyListeners();
  }

  /// Make this device the Host and start accepting TLS clients (FR-6, FR-7).
  Future<void> becomeHost() async {
    final cert = _cert;
    if (cert == null) return;
    try {
    _hostTransport = HostTransport();
    await _hostTransport!.start(context: cert.buildContext());
    _role = DeviceRole.host;

    // Edge-switch routing: place self in the layout and route captured input
    // through the ControlRouter, which forwards to the peer that owns the cursor.
    final displays = await backend.queryDisplays();
    final m = displays.monitors.first;
    final selfOff = _layoutStore.offsetFor(_self!.id);
    layout.placeDevice(_self!.id, displays,
        offsetX: selfOff?.x ?? 0, offsetY: selfOff?.y ?? 0);
    _router = ControlRouter(
      selfId: _self!.id,
      selfWidth: m.width,
      selfHeight: m.height,
      selfScale: m.scale,
      layout: layout,
      onSuppress: backend.suppressLocal,
      onWarp: backend.warpCursor,
      onForward: (peerId, e) => _sessionFor(peerId)?.sendInput(e),
    );

    _hostConnSub = _hostTransport!.connections.listen((link) {
      _sessions.add(_newSession(link, isHost: true, onInput: (_) {}));
    });
    _captureSub = backend.captureStream().listen(_router!.onCaptured);
    } catch (e) {
      await _hostTransport?.dispose();
      _hostTransport = null;
      _router = null;
      _role = DeviceRole.idle;
      // ignore: avoid_print
      print('becomeHost failed: $e');
    }
    notifyListeners();
  }

  /// Connect to a Host as a client (FR-7, FR-10). Pairing (if needed) proceeds
  /// via [pendingPairing] + [approvePairing].
  Future<void> connectToHost(Peer host) =>
      connectToAddress(host.host, port: host.port);

  /// Connect directly to a host by IP[:port] (FR-3) — bypasses discovery, which
  /// is essential when multicast is blocked by the network or virtual adapters.
  Future<void> connectToAddress(String host, {int port = kEnsiPort}) async {
    final cert = _cert;
    if (cert == null) return;
    final client = ClientTransport();
    final link = await client.connect(host, port: port, context: cert.buildContext());
    _clientTransport = client;
    _sessions.add(_newSession(
      link,
      isHost: false,
      onInput: (event) {
        if (backend.canReceiveInput) backend.inject(event);
      },
    ));
    _role = backend.canReceiveInput ? DeviceRole.client : DeviceRole.inputSender;
    notifyListeners();
  }

  PeerSession _newSession(
    PeerLink link, {
    required bool isHost,
    required void Function(InputEvent) onInput,
  }) =>
      PeerSession(
        link: link,
        self: _self!,
        selfFingerprint: _cert!.fingerprint,
        trust: trust,
        backend: backend,
        isHost: isHost,
        onChanged: _onSessionChanged,
        onInput: onInput,
        onClipboard: _onRemoteClipboard,
      );

  void _onSessionChanged() {
    // Surface manually-connected peers (Connect-by-IP has no discovered row).
    for (final s in _sessions) {
      if (s.peer != null && _peerById(s.peer!.id) == null) {
        _peers.add(Peer(info: s.peer!, host: s.link.remoteHost, port: kEnsiPort));
      }
    }
    // Mirror each session's phase onto its Peer row.
    for (final s in _sessions) {
      final p = _peerById(s.peerId);
      if (p == null) continue;
      p.trusted = s.peerId != null && trust.isTrusted(s.peerId!, s.peerFingerprint);
      p.status = switch (s.phase) {
        SessionPhase.connected => PeerStatus.connected,
        SessionPhase.pairing || SessionPhase.handshaking => PeerStatus.pairing,
        SessionPhase.rejected => PeerStatus.discovered,
        SessionPhase.closed => PeerStatus.offline,
      };
    }

    // Auto-arrange a newly connected peer to the right of this host so
    // edge-switch works out of the box (custom layouts come from the editor).
    final selfPlacement = layout.placements[_self?.id];
    for (final s in _sessions) {
      if (s.phase == SessionPhase.connected &&
          s.peer != null &&
          !layout.placements.containsKey(s.peer!.id)) {
        final off = _layoutStore.offsetFor(s.peer!.id);
        layout.placeDevice(s.peer!.id, s.peer!.displays,
            offsetX: off?.x ?? (selfPlacement?.width ?? 1920),
            offsetY: off?.y ?? 0);
      }
    }

    // Surface the first session needing SAS attention.
    PendingPairing? pending;
    for (final s in _sessions) {
      if (s.phase == SessionPhase.pairing) {
        pending = PendingPairing(
          peerId: s.peerId ?? '',
          peerName: s.peer?.name ?? 'device',
          code: s.code,
          isHost: s.isHost,
        );
        break;
      }
    }
    _pendingPairing = pending;

    _sessions.removeWhere((s) =>
        s.phase == SessionPhase.closed || s.phase == SessionPhase.rejected);

    // If the peer that held the cursor is gone, return control locally.
    final owner = _router?.owner;
    if (owner != null && _sessionFor(owner) == null) _router!.reset();

    notifyListeners();
  }

  /// Host: approve the active SAS pairing (FR-4, FR-25).
  Future<void> approvePairing() async {
    final pp = _pendingPairing;
    if (pp == null) return;
    await _sessionFor(pp.peerId)?.approve();
  }

  /// Reject the active SAS pairing.
  Future<void> rejectPairing() async {
    final pp = _pendingPairing;
    if (pp == null) return;
    await _sessionFor(pp.peerId)?.reject();
  }

  /// Confirm pairing for a peer — kept for compatibility; the real flow is
  /// driven by [pendingPairing] + [approvePairing].
  Future<void> approveFor(String peerId) => _sessionFor(peerId)?.approve() ?? Future.value();

  /// Revoke a trusted device (FR-26): forget its pinned cert and drop any live
  /// session with it.
  Future<void> revokeTrust(String peerId) async {
    await trust.revoke(peerId);
    await _sessionFor(peerId)?.dispose();
    final p = _peerById(peerId);
    if (p != null) p.trusted = false;
    notifyListeners();
  }

  /// Persist a device's position on the shared layout (called from the editor).
  Future<void> setLayoutOffset(
      String id, DisplayGeometry displays, double x, double y) async {
    layout.placeDevice(id, displays, offsetX: x, offsetY: y);
    await _layoutStore.set(id, x, y);
    notifyListeners();
  }

  Peer? _peerById(String? id) {
    if (id == null) return null;
    for (final p in _peers) {
      if (p.info.id == id) return p;
    }
    return null;
  }

  PeerSession? _sessionFor(String id) {
    for (final s in _sessions) {
      if (s.peerId == id) return s;
    }
    return null;
  }

  Future<void> reset() async {
    await _captureSub?.cancel();
    await _hostConnSub?.cancel();
    _captureSub = null;
    _hostConnSub = null;
    for (final s in List<PeerSession>.of(_sessions)) {
      await s.dispose();
    }
    _sessions.clear();
    await _hostTransport?.dispose();
    await _clientTransport?.dispose();
    _hostTransport = null;
    _clientTransport = null;
    _router?.reset(); // lifts local-input suppression
    _router = null;
    await backend.releaseAllKeys(); // NFR-2: no stuck keys
    _pendingPairing = null;
    _role = DeviceRole.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    _peerSub?.cancel();
    _captureSub?.cancel();
    _hostConnSub?.cancel();
    for (final s in _sessions) {
      s.dispose();
    }
    _hostTransport?.dispose();
    _clientTransport?.dispose();
    discovery.dispose();
    backend.dispose();
    super.dispose();
  }
}
