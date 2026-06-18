import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/trust_store.dart';

/// Lists paired (trusted) devices and lets the user revoke any of them
/// (FR-26). Revoking forgets the pinned certificate, so the device must pair
/// again before it can connect.
class TrustedDevicesScreen extends StatelessWidget {
  const TrustedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trusted = state.trustedPeers;

    return Scaffold(
      appBar: AppBar(title: const Text('Trusted devices')),
      body: trusted.isEmpty
          ? const Center(child: Text('No paired devices yet.'))
          : ListView.separated(
              itemCount: trusted.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final TrustedPeer p = trusted[i];
                return ListTile(
                  leading: const Icon(Icons.verified_user),
                  title: Text('${p.name} (${p.platform.name})'),
                  subtitle: Text(
                    'fingerprint ${_short(p.fingerprint)}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    tooltip: 'Revoke',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRevoke(context, state, p),
                  ),
                );
              },
            ),
    );
  }

  static String _short(String fp) =>
      fp.length <= 16 ? fp : '${fp.substring(0, 8)}…${fp.substring(fp.length - 8)}';

  Future<void> _confirmRevoke(
      BuildContext context, AppState state, TrustedPeer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${p.name}?'),
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
    if (ok == true) await state.revokeTrust(p.id);
  }
}
