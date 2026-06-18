import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/peer.dart';

/// Visual editor for arranging device screens on the shared 2D layout (FR-15,
/// FR-18). Each device is a draggable tile sized to its display geometry; the
/// resulting edge-adjacency drives cursor switching (FR-17).
///
/// This is a functional drag-to-arrange skeleton; snapping/persistence
/// (FR-20) and per-monitor splitting are refined in M3.
class LayoutEditor extends StatefulWidget {
  const LayoutEditor({super.key});

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  // Scale factor: layout pixels -> editor pixels.
  static const double _scale = 0.12;

  // Local editor positions keyed by device id.
  final Map<String, Offset> _positions = {};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tiles = <_DeviceTile>[];

    // Include self + peers.
    var index = 0;
    final self = state.self;
    if (self != null) {
      tiles.add(_DeviceTile(
        id: self.id,
        label: '${self.name}\n(this device)',
        width: _layoutWidth(self.displays.monitors),
        height: _layoutHeight(self.displays.monitors),
        color: Theme.of(context).colorScheme.primaryContainer,
        index: index++,
      ));
    }
    for (final Peer p in state.peers) {
      tiles.add(_DeviceTile(
        id: p.info.id,
        label: p.info.name,
        width: 1920,
        height: 1080,
        color: Theme.of(context).colorScheme.secondaryContainer,
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
              'The cursor crosses where edges meet.',
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
                  children: [
                    for (final t in tiles) _buildTile(t),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(_DeviceTile t) {
    final pos = _positions[t.id] ??
        Offset(20 + t.index * (t.width * _scale + 16), 40);
    _positions[t.id] = pos;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _positions[t.id] = _positions[t.id]! + d.delta;
        }),
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

  double _layoutWidth(List monitors) => 1920;
  double _layoutHeight(List monitors) => 1080;
}

class _DeviceTile {
  final String id;
  final String label;
  final double width;
  final double height;
  final Color color;
  final int index;
  _DeviceTile({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.color,
    required this.index,
  });
}
