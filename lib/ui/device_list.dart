import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/peer.dart';

/// Lists peers discovered on the LAN and lets the user connect/pair (FR-2,
/// FR-4). A real PIN-pairing dialog lands in M1.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final peers = state.peers;

    if (peers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_find, size: 48),
            SizedBox(height: 8),
            Text('Searching the local network for ENSI devices…'),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: peers.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final peer = peers[i];
        return ListTile(
          leading: Icon(peer.trusted ? Icons.verified_user : Icons.devices),
          title: Text(peer.displayName),
          subtitle: Text('${peer.endpoint} · ${peer.status.name}'),
          trailing: FilledButton.tonal(
            onPressed: () => _connect(context, state, peer),
            child: const Text('Connect'),
          ),
        );
      },
    );
  }

  Future<void> _connect(
      BuildContext context, AppState state, Peer peer) async {
    if (!peer.trusted) {
      final ok = await _showPairDialog(context, peer);
      if (ok != true) return;
      state.trustPeer(peer);
    }
    await state.connectToHost(peer);
  }

  Future<bool?> _showPairDialog(BuildContext context, Peer peer) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pair with ${peer.info.name}?'),
        content: const Text(
          'Confirm the matching PIN is shown on the other device.\n'
          '(PIN exchange + TLS pairing is implemented in milestone M1.)',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pair')),
        ],
      ),
    );
  }
}
