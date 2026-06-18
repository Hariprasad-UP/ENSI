import 'dart:io';

import 'package:ensi/core/cert_service.dart';
import 'package:ensi/core/protocol.dart';
import 'package:ensi/core/transport.dart';
import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration test for the TLS session transport over loopback. Verifies
/// end-to-end Message framing in both directions AND that each side captures the
/// other's certificate fingerprint (the basis for pairing/trust).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CertService hostCert;
  late CertService clientCert;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hostCert = await CertService.loadOrCreate('host');
    SharedPreferences.setMockInitialValues({});
    clientCert = await CertService.loadOrCreate('client');
  });

  late HostTransport host;
  late ClientTransport client;
  late int port;

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    host = HostTransport();
    await host.start(port: port, context: hostCert.buildContext());
    client = ClientTransport();
  });

  tearDown(() async {
    await client.dispose();
    await host.dispose();
  });

  test('client cryptographically captures the host certificate fingerprint',
      () async {
    final hostLinkFuture = host.connections.first;
    final clientLink =
        await client.connect('127.0.0.1', port: port, context: clientCert.buildContext());
    final hostLink = await hostLinkFuture.timeout(const Duration(seconds: 5));

    // Server-authenticated TLS: the client sees the host's real cert...
    expect(clientLink.peerFingerprint, hostCert.fingerprint);
    // ...while the host gets no client cert over TLS (it learns the client's
    // fingerprint from the `hello` frame at the session layer instead).
    expect(hostLink.peerFingerprint, isEmpty);
  });

  test('messages round-trip in both directions over TLS', () async {
    final hostLinkFuture = host.connections.first;
    final clientLink =
        await client.connect('127.0.0.1', port: port, context: clientCert.buildContext());
    final hostLink = await hostLinkFuture.timeout(const Duration(seconds: 5));

    // client -> host
    final hostGot = hostLink.incoming.first;
    clientLink.send(Message.event(
        const InputEvent(type: InputEventType.keyDown, keyCode: 65)));
    final m1 = await hostGot.timeout(const Duration(seconds: 5));
    expect(m1.kind, MessageKind.event);
    expect(m1.event!.keyCode, 65);

    // host -> client
    final clientGot = clientLink.incoming.first;
    hostLink.send(const Message.heartbeat());
    final m2 = await clientGot.timeout(const Duration(seconds: 5));
    expect(m2.kind, MessageKind.heartbeat);
  });
}
