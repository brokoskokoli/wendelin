import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/todoist_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart';

void main() {
  testWidgets('„Token fehlt – Einrichten“ öffnet die Todoist-Seite; falscher '
      'Token speichert nichts, richtiger wird aktiv und nie wieder gezeigt', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'todoist'});
    await pumpIntegrations(tester, env);
    final todoist = tileWidget(tester, 'Todoist');
    expect(todoist.status, IntegrationStatus.setupRequired);
    expect(todoist.detail, 'API-Token fehlt');
    await tester.tap(
      find.descendant(
        of: tile('Todoist'),
        matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
      ),
    );
    await settle(tester);
    expect(find.byType(TodoistScreen), findsOneWidget);

    await tester.tap(find.text('Verbinden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('todoistError')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('todoistToken')),
      'falsch',
    );
    await tester.tap(find.text('Verbinden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('todoistError')), findsOneWidget);
    final text = (tester.widget(
      find.byKey(const ValueKey('todoistError')),
    ) as Text).data;
    expect(text, isNot(contains('falsch')));
    // Wording comes from the ARB file for the failure kind.
    expect(text, 'Todoist hat den Token abgelehnt (ungültig oder widerrufen).');
    expect(await env.secrets.listKeys(), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('todoistToken')),
      FakeTodoistApi.validToken,
    );
    await tester.tap(find.text('Verbinden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('todoistToken')), findsNothing);
    expect(find.textContaining(FakeTodoistApi.validToken), findsNothing);
    expect(await env.secrets.listKeys(), {'todoist.token'});

    await tester.tap(find.text('Abmelden'));
    await settle(tester);
    await tester.tap(find.text('Abmelden').last);
    await settle(tester);
    expect(await env.secrets.listKeys(), isEmpty);
  });
}
