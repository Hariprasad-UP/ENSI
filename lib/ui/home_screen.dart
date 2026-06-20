import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/device.dart';
import 'device_list.dart';
import 'hand_control_tile.dart';
import 'layout_editor.dart';
import 'pairing_dialog.dart';
import 'trusted_devices_screen.dart';

/// Top-level shell: shows this device's identity + role, the discovered peer
/// list, and entry points to the layout editor and trusted devices. Surfaces
/// the SAS pairing dialog automatically whenever a pairing needs attention.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _pairingDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Kick off identity + discovery once the first frame is scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  void _maybeShowPairing(AppState state) {
    if (state.pendingPairing == null || _pairingDialogOpen) return;
    _pairingDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PairingDialog(),
      );
      _pairingDialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final self = state.self;
    _maybeShowPairing(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ENSI'),
        actions: [
          IconButton(
            tooltip: 'Trusted devices',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrustedDevicesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Layout',
            icon: const Icon(Icons.grid_view),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LayoutEditor()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SelfCard(
              self: self,
              role: state.role,
              trustedCount: state.trustedPeers.length,
            ),
            const SizedBox(height: 16),
            _RoleControls(state: state),
            const SizedBox(height: 16),
            const HandControlTile(),
            const SizedBox(height: 16),
            Text('Devices on your network',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Expanded(child: DeviceList()),
          ],
        ),
      ),
    );
  }
}

class _SelfCard extends StatelessWidget {
  final DeviceInfo? self;
  final DeviceRole role;
  final int trustedCount;
  const _SelfCard({
    required this.self,
    required this.role,
    required this.trustedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.computer)),
        title: Text(self?.name ?? 'Identifying this device…'),
        subtitle: Text(self == null
            ? '—'
            : '${self!.platform.name} · '
                '${self!.displays.monitors.length} monitor(s) · '
                'role: ${role.name} · '
                '$trustedCount trusted'),
        trailing: self?.canReceiveInput == false
            ? const Chip(label: Text('sender only'))
            : null,
      ),
    );
  }
}

class _RoleControls extends StatelessWidget {
  final AppState state;
  const _RoleControls({required this.state});

  @override
  Widget build(BuildContext context) {
    final isHost = state.role == DeviceRole.host;
    return Row(
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.keyboard),
          label: Text(isHost ? 'Hosting' : 'Become Host'),
          onPressed: isHost ? null : () => state.becomeHost(),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop / Reset'),
          onPressed:
              state.role == DeviceRole.idle ? null : () => state.reset(),
        ),
      ],
    );
  }
}
