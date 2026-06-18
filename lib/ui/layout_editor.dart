import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/device.dart';
import '../models/peer.dart';

/// Visual editor for arranging device screens on the shared 2D layout (FR-15,
/// FR-18, FR-20). Each device is a draggable tile sized to its display geometry;
/// the arrangement is written to [AppState.layout] and persisted, and it drives
/// cursor edge-switching (FR-17) via the host's ControlRouter.
class LayoutEditor extends StatefulWidget {
  const LayoutEditor({super.key});

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  // Scale factor: layout pixels -> editor pixels.
  static const double _scale = 0.12;

  // In-progress drag positions (editor pixels) keyed by device id.
  final Map<String, Offset> _drag = {};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final tiles = <_DeviceTile>[];

    var index = 0;
    final self = state.self;
    if (self != null) {
      tiles.add(_DeviceTile(
        id: self.id,
        label: '${self.name}\n(this device)',
        displays: self.displays,
        color: scheme.primaryContainer,
        index: index++,
      ));
    }
    for (final Peer p in state.peers) {
      tiles.add(_DeviceTile(
        id: p.info.id,
        label: p.info.name,
        displays: p.info.displays,
        color: scheme.secondaryContainer,
        index: index++,
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Display layout')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Drag each device so its screen edges touch its neighbours. '
              'The cursor crosses to a device where their edges meet.',
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [for (final t in tiles) _buildTile(context, state, t)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, AppState state, _DeviceTile t) {
    final placement = state.layout.placements[t.id];
    final pos = _drag[t.id] ??
        (placement != null
            ? Offset(placement.offsetX * _scale, placement.offsetY * _scale)
            : Offset(20 + t.index * (t.width * _scale + 16), 40));

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _drag[t.id] = (_drag[t.id] ?? pos) + d.delta;
        }),
        onPanEnd: (_) {
          final p = _drag[t.id] ?? pos;
          state.setLayoutOffset(t.id, t.displays, p.dx / _scale, p.dy / _scale);
        },
        child: Container(
          width: t.width * _scale,
          height: t.height * _scale,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(t.label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _DeviceTile {
  final String id;
  final String label;
  final DisplayGeometry displays;
  final Color color;
  final int index;
  _DeviceTile({
    required this.id,
    required this.label,
    required this.displays,
    required this.color,
    required this.index,
  });

  double get width => _extent((m) => m.right);
  double get height => _extent((m) => m.bottom);

  double _extent(double Function(MonitorGeometry) f) =>
      displays.monitors.map(f).fold<double>(0, (a, b) => a > b ? a : b);
}
