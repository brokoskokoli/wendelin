import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';

import '../support/test_env.dart';
import 'main_screen_test.dart' show pumpApp, pumpUntil, send;

void main() {
  testWidgets('Senden, während eine Anfrage läuft, wird ignoriert', (
    tester,
  ) async {
    final env = TestEnv(demo: true);
    await pumpApp(tester, env);

    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    expect(find.byType(UserBubble), findsOneWidget);
    // Die Anfrage läuft noch: der zweite Text wird nicht gesendet.
    await send(tester, 'Noch etwas');
    expect(find.byType(UserBubble), findsOneWidget);
    expect(find.text('Noch etwas'), findsOneWidget, reason: 'bleibt im Feld');

    await pumpUntil(tester, find.textContaining('ist eingetragen'));
  });
}
