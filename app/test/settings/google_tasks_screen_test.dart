import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/google_tasks_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart';

Future<void> _openPage(WidgetTester tester, TestEnv env) async {
  await pumpIntegrations(tester, env);
  final g = tileWidget(tester, 'Google Tasks');
  expect(g.status, IntegrationStatus.setupRequired);
  expect(g.detail, 'Google-Anmeldung fehlt');
  await tester.tap(
    find.descendant(
      of: tile('Google Tasks'),
      matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
    ),
  );
  await settle(tester);
  expect(find.byType(GoogleTasksScreen), findsOneWidget);
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('googleTasksClientId')),
    'abc.apps.googleusercontent.com',
  );
  await tester.enterText(
    find.byKey(const ValueKey('googleTasksClientSecret')),
    'GOCSPX-geheim',
  );
}

String _error(WidgetTester tester) => (tester.widget(
  find.byKey(const ValueKey('googleTasksError')),
) as Text).data!;

void main() {
  testWidgets('Einrichten zeigt Anleitung; leere Felder und falscher state '
      'speichern nichts', (tester) async {
    final env = TestEnv(enabled: const {'gtasks'});
    await _openPage(tester, env);
    expect(find.textContaining('Google Tasks API'), findsOneWidget);

    await tester.tap(find.text('Bei Google anmelden'));
    await settle(tester);
    expect(_error(tester), contains('Client-ID und Client-Secret'));

    await _fill(tester);
    // An answer with a foreign state is ignored; the denial that follows
    // ends the login with the German text of its kind.
    env.googleBrowser.onOpen = (url) async {
      env.googleReceiver
        ..deliver({'state': 'fremd', 'code': 'fake-code'})
        ..deliver({
          'state': url.queryParameters['state']!,
          'error': 'access_denied',
        });
    };
    await tester.tap(find.text('Bei Google anmelden'));
    await settle(tester);
    expect(_error(tester), contains('Testnutzer'));
    expect(_error(tester), isNot(contains('geheim')));
    expect(await env.secrets.listKeys(), isEmpty);
    expect(env.googleBrowser.opened.single.host, 'accounts.google.com');
  });

  testWidgets('Seite verlassen bricht die laufende Anmeldung ab', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'gtasks'});
    await _openPage(tester, env);
    await _fill(tester);
    await tester.tap(find.text('Bei Google anmelden'));
    await tester.pump();
    await tester.pump();
    expect(env.googleBrowser.opened, hasLength(1));
    expect(env.googleReceiver.closed, isFalse);
    // Back out of the page while the browser login is pending.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await settle(tester);
    expect(find.byType(GoogleTasksScreen), findsNothing);
    expect(env.googleReceiver.closed, isTrue);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets('Anmeldung speichert Client und Token, zeigt sie nie wieder; '
      'Abmelden widerruft und löscht', (tester) async {
    final env = TestEnv(enabled: const {'gtasks'});
    await _openPage(tester, env);
    await _fill(tester);
    env.googleBrowser.onOpen = (url) async => env.googleReceiver.deliver({
      'state': url.queryParameters['state']!,
      'code': 'fake-code',
    });
    await tester.tap(find.text('Bei Google anmelden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('googleTasksClientId')), findsNothing);
    expect(find.textContaining('geheim'), findsNothing);
    expect(await env.secrets.listKeys(), {
      'gtasks.client_id',
      'gtasks.client_secret',
      'gtasks.refresh_token',
    });

    await tester.tap(find.text('Abmelden'));
    await settle(tester);
    await tester.tap(find.text('Abmelden').last);
    await settle(tester);
    expect(await env.secrets.listKeys(), isEmpty);
    expect(env.googleTasks.revoked, hasLength(1));
  });
}
