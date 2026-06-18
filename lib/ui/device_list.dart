import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/peer.dart';

/// Lists peers discovered on the LAN and lets the user connect (FR-2). Pairing
/// (the SAS dialog) is surfaced globally by the home screen via
/// [AppState.pendingPairing]; here we just kick off the connection and reflect
/// live per-peer status.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final peers = state.peers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('Connect by IP'),
            onPressed: () => _showConnectByIp(context, state),
          ),
        ),
        Expanded(
          child: peers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_find, size: 48),
                      SizedBox(height: 8),
                      Text('Searching the local network…\n'
                          'If nothing appears, use “Connect by IP”.',
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: peers.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final peer = peers[i];
                    return ListTile(
                      leading: Icon(
                          peer.trusted ? Icons.verified_user : Icons.devices),
                      title: Text(peer.displayName),
                      subtitle: Text('${peer.endpoint} · ${peer.status.name}'),
                      trailing: _trailingFor(context, state, peer),
                      onLongPress: peer.trusted
                          ? () => _confirmRevoke(context, state, peer)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showConnectByIp(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect by IP'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Host IP address',
            hintText: 'e.g. 192.168.1.3',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Connect')),
        ],
      ),
    );
    if (ip != null && ip.isNotEmpty) {
      await _connect(messenger, () => state.connectToAddress(ip), ip);
    }
  }

  /// Run a connect action, surfacing any failure as a SnackBar instead of
  /// crashing the app on an unhandled SocketException.
  Future<void> _connect(ScaffoldMessengerState messenger,
      Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not connect to $label: $e')),
      );
    }
  }

  Widget _trailingFor(BuildContext context, AppState state, Peer peer) {
    switch (peer.status) {
      case PeerStatus.connected:
        return const Chip(
          avatar: Icon(Icons.link, size: 18),
          label: Text('Connected'),
        );
      case PeerStatus.pairing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return FilledButton.tonal(
          onPressed: () => _connect(ScaffoldMessenger.of(context),
              () => state.connectToHost(peer), peer.info.name),
          child: const Text('Connect'),
        );
    }
  }

  Future<void> _confirmRevoke(
      BuildContext context, AppState state, Peer peer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${peer.info.name}?'),
        content: const Text(
            'This device will have to pair again before it can connect.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (ok == true) await state.revokeTrust(peer.info.id);
  }
}
