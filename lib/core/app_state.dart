import 'dart:async';

import 'package:flutter/foundation.dart';

import '../input/input_backend.dart';
import '../models/device.dart';
import '../models/peer.dart';
import 'discovery_service.dart';
import 'identity.dart';
import 'layout_manager.dart';
import 'transport.dart';

/// Central application state shared across the UI via `provider` (FR-2, FR-6).
///
/// Wires together the [InputBackend], [DiscoveryService], transports, and
/// [LayoutManager]. Most of the cross-device behaviour is stubbed at this
/// milestone (M0/M1) — this class defines the seams so screens can be built
/// against real state.
class AppState extends ChangeNotifier {
  final InputBackend backend;
  final DiscoveryService discovery;
  final LayoutManager layout = LayoutManager();

  DeviceInfo? _self;
  DeviceRole _role = DeviceRole.idle;
  final List<Peer> _peers = [];

  HostTransport? _hostTransport;
  ClientTransport? _clientTransport;
  StreamSubscription<List<Peer>>? _peerSub;

  AppState({required this.backend, required this.discovery});

  DeviceInfo? get self => _self;
  DeviceRole get role => _role;
  List<Peer> get peers => List.unmodifiable(_peers);

  /// Initialize identity + start LAN discovery.
  Future<void> init() async {
    _self = await IdentityService.load(backend);
    _peerSub = discovery.peers.listen(_onPeersUpdated);
    await discovery.start();
    await discovery.advertise(_self!, kEnsiPort);
    notifyListeners();
  }

  void _onPeersUpdated(List<Peer> found) {
    for (final p in found) {
      if (!_peers.contains(p)) _peers.add(p);
    }
    notifyListeners();
  }

  /// Make this device the Host and start accepting clients (FR-6, FR-7).
  Future<void> becomeHost() async {
    _hostTransport = HostTransport();
    await _hostTransport!.start();
    _role = DeviceRole.host;
    // Forward captured input to clients (targeting via layout is a later step).
    backend.captureStream().listen(_hostTransport!.send);
    notifyListeners();
  }

  /// Connect to a Host as a client and inject received input (FR-7, FR-10).
  Future<void> connectToHost(Peer host) async {
    _clientTransport = ClientTransport();
    await _clientTransport!.connect(host.host);
    _role = backend.canReceiveInput
        ? DeviceRole.client
        : DeviceRole.inputSender;
    _clientTransport!.incoming.listen((event) {
      if (backend.canReceiveInput) backend.inject(event);
    });
    notifyListeners();
  }

  /// Confirm pairing for a peer (after PIN match) — gates input exchange
  /// (FR-4, FR-25).
  void trustPeer(Peer peer) {
    peer.trusted = true;
    peer.status = PeerStatus.paired;
    notifyListeners();
  }

  Future<void> reset() async {
    await _hostTransport?.dispose();
    await _clientTransport?.dispose();
    _hostTransport = null;
    _clientTransport = null;
    await backend.releaseAllKeys(); // NFR-2: no stuck keys
    _role = DeviceRole.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _hostTransport?.dispose();
    _clientTransport?.dispose();
    discovery.dispose();
    backend.dispose();
    super.dispose();
  }
}
