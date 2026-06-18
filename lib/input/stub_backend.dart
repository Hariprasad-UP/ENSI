import 'dart:async';
import 'dart:developer' as developer;

import '../models/device.dart';
import '../models/input_event.dart';
import 'input_backend.dart';

/// A no-op [InputBackend] used until the native capture/inject layers are
/// implemented. It logs actions instead of touching the OS so the full app
/// (discovery, pairing, transport, layout UI) can be developed and tested
/// end-to-end without the platform code in place.
class StubInputBackend implements InputBackend {
  final String label;
  final bool _canReceive;
  final _controller = StreamController<InputEvent>.broadcast();

  StubInputBackend({required this.label, bool canReceive = true})
      : _canReceive = canReceive;

  void _log(String msg) =>
      developer.log(msg, name: 'ENSI.input.$label');

  @override
  Stream<InputEvent> captureStream() {
    _log('captureStream() requested — native capture not yet implemented.');
    return _controller.stream;
  }

  @override
  Future<void> inject(InputEvent event) async {
    _log('inject() $event — native injection not yet implemented.');
  }

  @override
  Future<DisplayGeometry> queryDisplays() async {
    // Real backends will query the OS; default to a single 1080p screen.
    return DisplayGeometry.single();
  }

  @override
  Future<void> releaseAllKeys() async => _log('releaseAllKeys()');

  @override
  bool get canReceiveInput => _canReceive;

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
