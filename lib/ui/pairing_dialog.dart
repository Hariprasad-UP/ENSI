import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';

/// Presentational SAS dialog body (no app state) — easy to unit-test.
class PairingDialogView extends StatelessWidget {
  final String peerName;
  final String code;
  final bool isHost;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const PairingDialogView({
    super.key,
    required this.peerName,
    required this.code,
    required this.isHost,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Pair with $peerName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Confirm this code matches on both devices:'),
          const SizedBox(height: 20),
          Text(
            code,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFeatures: const [],
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (!isHost)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Flexible(child: Text('Waiting for the other device to approve…')),
              ],
            ),
        ],
      ),
      actions: isHost
          ? [
              TextButton(onPressed: onReject, child: const Text('Reject')),
              FilledButton(onPressed: onApprove, child: const Text('Approve')),
            ]
          : [
              TextButton(onPressed: onReject, child: const Text('Cancel')),
            ],
    );
  }
}

/// Live SAS dialog wired to [AppState]. Auto-dismisses when the pairing resolves
/// (approved, rejected, or the peer dropped).
class PairingDialog extends StatelessWidget {
  const PairingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.pendingPairing;

    if (pending == null) {
      // Resolved — close on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return PairingDialogView(
      peerName: pending.peerName,
      code: pending.code,
      isHost: pending.isHost,
      onApprove: state.approvePairing,
      onReject: state.rejectPairing,
    );
  }
}
