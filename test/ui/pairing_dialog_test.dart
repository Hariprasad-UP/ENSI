import 'package:ensi/ui/pairing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('host view shows the SAS code and Approve invokes the callback',
      (tester) async {
    var approved = false;
    var rejected = false;
    await tester.pumpWidget(host(PairingDialogView(
      peerName: 'Studio-PC',
      code: '481596',
      isHost: true,
      onApprove: () => approved = true,
      onReject: () => rejected = true,
    )));

    expect(find.text('481596'), findsOneWidget);
    expect(find.textContaining('Studio-PC'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    expect(approved, isTrue);
    expect(rejected, isFalse);
  });

  testWidgets('client view waits for approval and offers no Approve button',
      (tester) async {
    await tester.pumpWidget(host(PairingDialogView(
      peerName: 'Laptop',
      code: '000123',
      isHost: false,
      onApprove: () {},
      onReject: () {},
    )));

    expect(find.text('000123'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
