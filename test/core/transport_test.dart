import 'dart:io';

import 'package:ensi/core/transport.dart';
import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration test for the host/client TCP transport over loopback. Verifies
/// the end-to-end framing (encode -> socket -> line-split -> decode) in both
/// directions. Runs entirely on 127.0.0.1, no LAN required.
void main() {
  late HostTransport host;
  late ClientTransport client;
  late int port;

  setUp(() async {
    // Grab a free ephemeral port to avoid clashing with a running app.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();

    host = HostTransport();
    await host.start(port: port);
    client = ClientTransport();
    await client.connect('127.0.0.1', port: port);
    // Let the server finish accepting the connection before we send.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });

  tearDown(() async {
    await client.dispose();
    await host.dispose();
  });

  test('client -> host: an event sent by the client reaches the host', () async {
    final received = host.incoming.first;
    client.send(const InputEvent(
      type: InputEventType.keyDown,
      keyCode: 65,
      modifiers: InputModifiers.ctrl,
    ));
    final e = await received.timeout(const Duration(seconds: 5));
    expect(e.type, InputEventType.keyDown);
    expect(e.keyCode, 65);
    expect(e.modifiers, InputModifiers.ctrl);
  });

  test('host -> client: an event broadcast by the host reaches the client',
      () async {
    final received = client.incoming.first;
    host.send(const InputEvent(type: InputEventType.mouseMove, x: 42, y: 99));
    final e = await received.timeout(const Duration(seconds: 5));
    expect(e.type, InputEventType.mouseMove);
    expect(e.x, 42);
    expect(e.y, 99);
  });

  test('multiple frames are delivered in order', () async {
    final got = <int>[];
    final sub = host.incoming.listen((e) => got.add(e.keyCode!));
    for (var i = 0; i < 5; i++) {
      client.send(InputEvent(type: InputEventType.keyDown, keyCode: i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    expect(got, [0, 1, 2, 3, 4]);
  });
}
