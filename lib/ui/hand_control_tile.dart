import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';

/// Toggle for camera hand-tracking. Surfaces failures (e.g. native module not
/// built / no camera) as a SnackBar instead of failing silently.
class HandControlTile extends StatelessWidget {
  const HandControlTile({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final on = state.handTrackingOn;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.front_hand_outlined),
        title: const Text('Hand cursor (camera)'),
        subtitle: Text(on
            ? 'Tracking — move your index finger; pinch to click'
            : 'Control the cursor with hand gestures (experimental)'),
        value: on,
        onChanged: (v) => _toggle(context, state, v),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, AppState state, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (on) {
        await state.enableHandTracking();
      } else {
        await state.disableHandTracking();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Hand tracking unavailable: $e')),
      );
    }
  }
}
