import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/device.dart';
import 'device_list.dart';
import 'layout_editor.dart';

/// Top-level shell: shows this device's identity + role, the discovered peer
/// list, and an entry point to the layout editor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off identity + discovery once the first frame is scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final self = state.self;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ENSI'),
        actions: [
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
            _SelfCard(self: self, role: state.role),
            const SizedBox(height: 16),
            _RoleControls(state: state),
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
  const _SelfCard({required this.self, required this.role});

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
                'role: ${role.name}'),
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
