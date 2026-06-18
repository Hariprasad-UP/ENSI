import 'package:ensi/input/stub_backend.dart';
import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StubInputBackend', () {
    test('canReceiveInput reflects the constructor flag', () {
      expect(StubInputBackend(label: 'desktop').canReceiveInput, isTrue);
      expect(
        StubInputBackend(label: 'phone', canReceive: false).canReceiveInput,
        isFalse,
      );
    });

    test('queryDisplays returns a default single screen', () async {
      final geo = await StubInputBackend(label: 't').queryDisplays();
      expect(geo.monitors, hasLength(1));
      expect(geo.monitors.single.isPrimary, isTrue);
    });

    test('inject and releaseAllKeys are safe no-ops (do not throw)', () async {
      final b = StubInputBackend(label: 't');
      await expectLater(
        b.inject(const InputEvent(type: InputEventType.mouseMove, x: 1, y: 1)),
        completes,
      );
      await expectLater(b.releaseAllKeys(), completes);
      await b.dispose();
    });

    test('captureStream is a broadcast stream that closes on dispose', () async {
      final b = StubInputBackend(label: 't');
      final stream = b.captureStream();
      expect(stream.isBroadcast, isTrue);
      final done = stream.drain<void>(); // completes when the stream closes
      await b.dispose();
      await done; // would hang/throw if dispose didn't close the controller
    });
  });
}
