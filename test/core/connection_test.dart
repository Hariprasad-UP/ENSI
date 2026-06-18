import 'dart:async';
import 'dart:io';

import 'package:ensi/core/cert_service.dart';
import 'package:ensi/core/protocol.dart';
import 'package:ensi/core/session.dart';
import 'package:ensi/core/transport.dart';
import 'package:ensi/core/trust_store.dart';
import 'package:ensi/input/stub_backend.dart';
import 'package:ensi/models/device.dart';
import 'package:ensi/models/input_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end pairing + session test over real loopback TLS: discovery is
/// excluded, but the full hello -> SAS -> approve -> connected handshake, the
/// FR-25 input gate, and trust pinning are exercised against live sockets.
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  DeviceInfo info(String id, String name, DevicePlatform p) => DeviceInfo(
        id: id,
        name: name,
        platform: p,
        displays: DisplayGeometry.single(),
        canReceiveInput: true,
      );

  Future<void> waitFor(bool Function() cond,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('condition not met in time');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('untrusted peers pair via SAS, gate input, then connect and exchange',
      () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final host = HostTransport();
    await host.start(port: port, context: hostCert.buildContext());
    final client = ClientTransport();

    final hostTrust = TrustStore();
    await hostTrust.load();
    final clientTrust = TrustStore();
    await clientTrust.load();

    final injected = <InputEvent>[];

    final hostLinkFuture = host.connections.first;
    final clientLink = await client.connect('127.0.0.1',
        port: port, context: clientCert.buildContext());
    final hostLink = await hostLinkFuture.timeout(const Duration(seconds: 5));

    final hostSession = PeerSession(
      link: hostLink,
      self: info('host-id', 'Host', DevicePlatform.windows),
      selfFingerprint: hostCert.fingerprint,
      trust: hostTrust,
      backend: StubInputBackend(label: 'host'),
      isHost: true,
      onChanged: () {},
      onInput: (_) {},
    );
    final clientSession = PeerSession(
      link: clientLink,
      self: info('client-id', 'Client', DevicePlatform.linux),
      selfFingerprint: clientCert.fingerprint,
      trust: clientTrust,
      backend: StubInputBackend(label: 'client'),
      isHost: false,
      onChanged: () {},
      onInput: injected.add,
    );

    // Both reach the pairing state with a matching SAS code.
    await waitFor(() =>
        hostSession.phase == SessionPhase.pairing &&
        clientSession.phase == SessionPhase.pairing);
    expect(hostSession.code, isNotEmpty);
    expect(hostSession.code, clientSession.code, reason: 'SAS must match');

    // FR-25 gate: an event before approval must NOT be delivered.
    hostLink.send(
        Message.event(const InputEvent(type: InputEventType.keyDown, keyCode: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(injected, isEmpty, reason: 'input is gated until trusted');

    // Host approves -> both go connected and pin each other.
    await hostSession.approve();
    await waitFor(() =>
        hostSession.phase == SessionPhase.connected &&
        clientSession.phase == SessionPhase.connected);
    expect(hostTrust.isTrusted('client-id', clientCert.fingerprint), isTrue);
    expect(clientTrust.isTrusted('host-id', hostCert.fingerprint), isTrue);

    // Now input flows host -> client.
    hostSession
        .sendInput(const InputEvent(type: InputEventType.mouseMove, x: 5, y: 6));
    await waitFor(() => injected.isNotEmpty);
    expect(injected.last.type, InputEventType.mouseMove);
    expect(injected.last.x, 5);

    await hostSession.dispose();
    await clientSession.dispose();
    await client.dispose();
    await host.dispose();
  });

  test('a peer already trusted connects without a pairing prompt', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final host = HostTransport();
    await host.start(port: port, context: hostCert.buildContext());
    final client = ClientTransport();

    // Pre-trust each other (simulating a prior pairing).
    final hostTrust = TrustStore();
    await hostTrust.load();
    await hostTrust.trust(TrustedPeer(
      id: 'client-id',
      name: 'Client',
      platform: DevicePlatform.linux,
      fingerprint: clientCert.fingerprint,
      addedAtMs: 1,
    ));
    final clientTrust = TrustStore();
    await clientTrust.load();
    await clientTrust.trust(TrustedPeer(
      id: 'host-id',
      name: 'Host',
      platform: DevicePlatform.windows,
      fingerprint: hostCert.fingerprint,
      addedAtMs: 1,
    ));

    final hostLinkFuture = host.connections.first;
    final clientLink = await client.connect('127.0.0.1',
        port: port, context: clientCert.buildContext());
    final hostLink = await hostLinkFuture.timeout(const Duration(seconds: 5));

    final hostSession = PeerSession(
      link: hostLink,
      self: info('host-id', 'Host', DevicePlatform.windows),
      selfFingerprint: hostCert.fingerprint,
      trust: hostTrust,
      backend: StubInputBackend(label: 'host'),
      isHost: true,
      onChanged: () {},
      onInput: (_) {},
    );
    final clientSession = PeerSession(
      link: clientLink,
      self: info('client-id', 'Client', DevicePlatform.linux),
      selfFingerprint: clientCert.fingerprint,
      trust: clientTrust,
      backend: StubInputBackend(label: 'client'),
      isHost: false,
      onChanged: () {},
      onInput: (_) {},
    );

    // Straight to connected — no pairing step.
    await waitFor(() =>
        hostSession.phase == SessionPhase.connected &&
        clientSession.phase == SessionPhase.connected);

    await hostSession.dispose();
    await clientSession.dispose();
    await client.dispose();
    await host.dispose();
  });
}
