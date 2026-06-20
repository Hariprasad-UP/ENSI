import 'dart:async';

import '../hand/hand_tracker.dart';
import '../models/input_event.dart';
import 'input_backend.dart';

/// Bridges [HandTracker] into ENSI's existing input pipeline: each [HandPointer]
/// becomes an [InputEvent] fed to [InputBackend.inject]. Injecting the *local*
/// cursor means ENSI's existing host-capture + ControlRouter carry it across the
/// edge to a paired machine for free — this adapter knows nothing about CV or
/// networking.
class HandInputSource {
  final HandTracker tracker;
  final InputBackend backend;
  StreamSubscription<HandPointer>? _sub;

  HandInputSource(this.tracker, this.backend);

  bool get isAvailable => tracker.isAvailable;

  Future<void> enable(HandTrackerConfig config) async {
    await tracker.start(config); // throws HandTrackerException if unavailable
    _sub = tracker.pointers.listen(_onPointer);
  }

  void _onPointer(HandPointer p) {
    if (!p.present) return;
    backend.inject(InputEvent(type: InputEventType.mouseMove, x: p.x, y: p.y));
    switch (p.gesture) {
      case HandGesture.click:
        backend.inject(const InputEvent(type: InputEventType.mouseDown, button: 0));
        backend.inject(const InputEvent(type: InputEventType.mouseUp, button: 0));
      case HandGesture.dragStart:
        backend.inject(const InputEvent(type: InputEventType.mouseDown, button: 0));
      case HandGesture.dragEnd:
        backend.inject(const InputEvent(type: InputEventType.mouseUp, button: 0));
      case HandGesture.none:
      case HandGesture.drag:
        break;
    }
  }

  Future<void> disable() async {
    await _sub?.cancel();
    _sub = null;
    await tracker.stop();
  }

  Future<void> dispose() async {
    await disable();
    await tracker.dispose();
  }
}
