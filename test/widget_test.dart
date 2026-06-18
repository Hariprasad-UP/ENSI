// Smoke test for the ENSI app shell.

import 'package:flutter_test/flutter_test.dart';

import 'package:ensi/core/app_state.dart';
import 'package:ensi/core/discovery_service.dart';
import 'package:ensi/input/stub_backend.dart';
import 'package:ensi/main.dart';

void main() {
  testWidgets('App renders the home screen with the ENSI title',
      (WidgetTester tester) async {
    final appState = AppState(
      backend: StubInputBackend(label: 'test'),
      discovery: DiscoveryService(),
    );

    await tester.pumpWidget(EnsiApp(appState: appState));
    await tester.pump();

    expect(find.text('ENSI'), findsWidgets);
    expect(find.text('Become Host'), findsOneWidget);
  });
}
