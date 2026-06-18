import '../models/input_event.dart';
import 'layout_manager.dart';

/// The edge-switch brain (host side). Sits between captured local input and the
/// peer sessions and decides, per event, whether input stays **local** or is
/// routed to a **remote** peer — flipping ownership when the cursor crosses a
/// screen edge that maps to a neighbour in the [LayoutManager] (FR-15..FR-17).
///
/// While control is remote it tracks a virtual cursor in the target's local
/// pixel space (fed by deltas from the host's recentred cursor), forwards
/// translated events, and hands control back when the cursor crosses the return
/// edge. All native effects (suppress local input, warp the cursor) are
/// callbacks so this class stays pure and unit-testable.
class ControlRouter {
  final String selfId;
  final double selfWidth;
  final double selfHeight;

  /// This host's display scale (DPI/96). Used to normalize cursor speed across
  /// machines with different scaling (FR-19).
  final double selfScale;
  final LayoutManager layout;

  /// Suppress (true) / restore (false) local OS input delivery.
  final void Function(bool on) onSuppress;

  /// Warp the local cursor to (x, y) in host pixels (used to recentre/return).
  final void Function(double x, double y) onWarp;

  /// Forward an event to the peer that currently owns the cursor.
  final void Function(String peerId, InputEvent event) onForward;

  String? _owner; // null => local owns the cursor
  ScreenEdge? _entryEdge; // host edge we left through
  double _vx = 0, _vy = 0; // virtual cursor in target-local pixels

  ControlRouter({
    required this.selfId,
    required this.selfWidth,
    required this.selfHeight,
    required this.layout,
    required this.onSuppress,
    required this.onWarp,
    required this.onForward,
    this.selfScale = 1.0,
  });

  bool get controlIsRemote => _owner != null;
  String? get owner => _owner;

  double get _cx => selfWidth / 2;
  double get _cy => selfHeight / 2;

  /// Feed a captured input event. Returns true if it was consumed for routing
  /// (the caller should not also deliver it locally).
  void onCaptured(InputEvent e) {
    if (_owner == null) {
      _whenLocal(e);
    } else {
      _whenRemote(e);
    }
  }

  void _whenLocal(InputEvent e) {
    if (e.type != InputEventType.mouseMove || e.x == null || e.y == null) return;
    final x = e.x!, y = e.y!;
    ScreenEdge? edge;
    double pos;
    if (x >= selfWidth - 1) {
      edge = ScreenEdge.right;
      pos = y;
    } else if (x <= 0) {
      edge = ScreenEdge.left;
      pos = y;
    } else if (y >= selfHeight - 1) {
      edge = ScreenEdge.bottom;
      pos = x;
    } else if (y <= 0) {
      edge = ScreenEdge.top;
      pos = x;
    } else {
      return;
    }
    final sw = layout.resolveEdge(selfId, edge, pos);
    if (sw == null) return;
    _enterRemote(sw, edge);
  }

  void _enterRemote(EdgeSwitch sw, ScreenEdge edge) {
    final p = layout.placements[sw.targetDeviceId];
    if (p == null) return;
    _owner = sw.targetDeviceId;
    _entryEdge = edge;
    // EdgeSwitch entry coords are global-layout; convert to target-local.
    _vx = (sw.entryX - p.offsetX).clamp(0.0, p.width);
    _vy = (sw.entryY - p.offsetY).clamp(0.0, p.height);
    onSuppress(true);
    onWarp(_cx, _cy);
    onForward(_owner!, InputEvent(type: InputEventType.enterScreen, x: _vx, y: _vy));
  }

  void _whenRemote(InputEvent e) {
    final peer = _owner!;
    switch (e.type) {
      case InputEventType.mouseMove:
        if (e.x == null || e.y == null) return;
        final dx = e.x! - _cx;
        final dy = e.y! - _cy;
        onWarp(_cx, _cy); // keep the real cursor centred
        if (dx == 0 && dy == 0) return;
        final p = layout.placements[peer]!;
        final factor = _scaleFactor(p); // DPI normalization (FR-19)
        _vx += dx * factor;
        _vy += dy * factor;
        if (_shouldReturn(p.width, p.height)) {
          _returnLocal();
          return;
        }
        _vx = _vx.clamp(0.0, p.width);
        _vy = _vy.clamp(0.0, p.height);
        onForward(peer, InputEvent(type: InputEventType.mouseMove, x: _vx, y: _vy));
      case InputEventType.mouseDown:
      case InputEventType.mouseUp:
      case InputEventType.mouseScroll:
      case InputEventType.keyDown:
      case InputEventType.keyUp:
        onForward(peer, e);
      case InputEventType.enterScreen:
      case InputEventType.leaveScreen:
      case InputEventType.releaseAll:
        break;
    }
  }

  double _scaleFactor(LayoutPlacement p) {
    final ts =
        p.displays.monitors.isNotEmpty ? p.displays.monitors.first.scale : 1.0;
    final ss = selfScale == 0 ? 1.0 : selfScale;
    return ts / ss;
  }

  bool _shouldReturn(double tw, double th) {
    switch (_entryEdge) {
      case ScreenEdge.right:
        return _vx < 0; // entered target's left; pushed back out
      case ScreenEdge.left:
        return _vx > tw;
      case ScreenEdge.bottom:
        return _vy < 0;
      case ScreenEdge.top:
        return _vy > th;
      case null:
        return false;
    }
  }

  void _returnLocal() {
    final peer = _owner;
    final edge = _entryEdge;
    if (peer != null) {
      // Release anything held on the remote so nothing sticks (NFR-2).
      onForward(peer, const InputEvent(type: InputEventType.releaseAll));
      onForward(peer, const InputEvent(type: InputEventType.leaveScreen));
    }
    _owner = null;
    _entryEdge = null;
    onSuppress(false);
    // Drop the local cursor just inside the edge it left from.
    switch (edge) {
      case ScreenEdge.right:
        onWarp(selfWidth - 2, _cy);
      case ScreenEdge.left:
        onWarp(1, _cy);
      case ScreenEdge.bottom:
        onWarp(_cx, selfHeight - 2);
      case ScreenEdge.top:
        onWarp(_cx, 1);
      case null:
        break;
    }
  }

  /// Force control back to local (e.g. on disconnect).
  void reset() {
    if (_owner != null) onSuppress(false);
    _owner = null;
    _entryEdge = null;
  }
}
