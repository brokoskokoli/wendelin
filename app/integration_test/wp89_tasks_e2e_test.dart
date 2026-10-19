// Gerätetest (WP89): Todoist und Google Tasks auf dem Emulator, nur mit
// Fakes (kein Konto, keine Keys): Einrichtungsseiten, Fehlerwege, echter
// Loopback-Server (state-Filter) und Tool-Ablauf add -> list -> complete.
//
//   tool/e2e_android.sh integration_test/wp89_tasks_e2e_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/google_tasks.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/todoist.dart';
import 'package:wendelin/ui/settings/google_tasks_screen.dart';
import 'package:wendelin/ui/settings/todoist_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../test/settings/integrations_screen_test.dart'
    show pumpIntegrations, settle, tile, tileWidget;
import '../test/support/test_env.dart';
import 'support/e2e.dart' show l10n;

TestEnv _env(String id) => TestEnv(
  startup: StartupSettings(enabledIntegrations: {id}, uiLanguage: 'de'),
);

ToolContext _ctx() => ToolContext(
  sessionId: 's1',
  clock: FixedClock(DateTime.utc(2026, 10, 13, 12)),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

Future<void> _openSetup(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: tile(name),
      matching: find.widgetWithText(
        OutlinedButton,
        l10n(tester).mcpLabelsSetUp,
      ),
    ),
  );
  await settle(tester);
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

String _err(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(ValueKey(key))) as Text).data!;

Future<int> _get(Uri uri) async {
  final c = HttpClient();
  try {
    final r = await (await c.getUrl(uri)).close();
    await r.drain<void>();
    return r.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1+2 Liste, Todoist: 401 -> Fehler, gültig -> verbunden, '
      'Tools add/list/complete mit Undo', (tester) async {
    final env = _env('todoist');
    final c = await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Todoist').status,
      IntegrationStatus.setupRequired,
    );
    expect(tile('Google Tasks'), findsOneWidget);
    await _openSetup(tester, 'Todoist');
    expect(find.byType(TodoistScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('todoistToken')),
      'falsch',
    );
    await tester.tap(find.text(l10n(tester).todoistConnect));
    await settle(tester);
    expect(_err(tester, 'todoistError'), l10n(tester).todoistErrDenied);
    expect(await env.secrets.listKeys(), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('todoistToken')),
      FakeTodoistApi.validToken,
    );
    await tester.tap(find.text(l10n(tester).todoistConnect));
    await settle(tester);
    expect(find.byKey(const ValueKey('todoistToken')), findsNothing);
    expect(await env.secrets.listKeys(), {'todoist.token'});

    final t = todoistIntegrationOf(c.read(integrationsProvider))!;
    Tool tool(String n) => t.tools.singleWhere((x) => x.name == n);
    expect(tool('todoist__add').risk, RiskLevel.write);
    expect(tool('todoist__complete').risk, RiskLevel.write);
    final ctx = _ctx();
    final added = await tool('todoist__add')
        .execute({'title': 'Zahnarzt anrufen'}, ctx);
    expect(added.isError, isFalse);
    final listed = await tool('todoist__list').execute({}, ctx);
    expect(listed.text, contains('Zahnarzt anrufen'));
    final done = await tool('todoist__complete')
        .execute({'title': 'Zahnarzt'}, ctx);
    expect(done.isError, isFalse);
    expect(done.undo, isNotNull);
    await done.undo!.run();
    expect(
      (await tool('todoist__list').execute({}, ctx)).text,
      contains('Zahnarzt anrufen'),
    );
  });

  testWidgets('3 Google Tasks: Anleitung, Erfolg, falscher state, Verlassen, '
      'Tools', (tester) async {
    final env = _env('gtasks');
    final c = await pumpIntegrations(tester, env);
    await _openSetup(tester, 'Google Tasks');
    expect(find.byType(GoogleTasksScreen), findsOneWidget);
    expect(find.text(l10n(tester).googleTasksGuideStep2), findsOneWidget);

    await _fill(tester);
    // Falscher state wird ignoriert, danach Erfolg mit richtigem state.
    env.googleBrowser.onOpen = (url) async {
      env.googleReceiver
        ..deliver({'state': 'fremd', 'code': 'fake-code'})
        ..deliver({
          'state': url.queryParameters['state']!,
          'code': 'fake-code',
        });
    };
    await tester.tap(find.text(l10n(tester).googleTasksSignIn));
    await settle(tester);
    expect(find.byKey(const ValueKey('googleTasksError')), findsNothing);
    expect(await env.secrets.listKeys(), {
      'gtasks.client_id',
      'gtasks.client_secret',
      'gtasks.refresh_token',
    });

    final g = googleTasksIntegrationOf(c.read(integrationsProvider))!;
    Tool tool(String n) => g.tools.singleWhere((x) => x.name == n);
    expect(tool('gtasks__add').risk, RiskLevel.write);
    expect(tool('gtasks__complete').risk, RiskLevel.write);
    final ctx = _ctx();
    final added = await tool('gtasks__add')
        .execute({'title': 'Zahnarzt anrufen'}, ctx);
    expect(added.isError, isFalse);
    expect(
      (await tool('gtasks__list').execute({}, ctx)).text,
      contains('Zahnarzt anrufen'),
    );
    final done = await tool('gtasks__complete')
        .execute({'title': 'Zahnarzt'}, ctx);
    expect(done.isError, isFalse);
    expect(done.undo, isNotNull);
    await done.undo!.run();
  });

  testWidgets('3b Verlassen während Login: Empfänger zu, nichts gespeichert', (
    tester,
  ) async {
    final env = _env('gtasks');
    await pumpIntegrations(tester, env);
    await _openSetup(tester, 'Google Tasks');
    await _fill(tester);
    await tester.tap(find.text(l10n(tester).googleTasksSignIn));
    await tester.pump();
    await tester.pump();
    expect(env.googleBrowser.opened, hasLength(1));
    expect(env.googleReceiver.closed, isFalse);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    expect(find.byType(GoogleTasksScreen), findsNothing);
    expect(env.googleReceiver.closed, isTrue);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets(
    '3c echter Loopback-Server auf dem Gerät: falscher state -> 400',
    (_) async {
      final r = await LoopbackReceiver.start();
      final wait = r.wait(
        const Duration(seconds: 20),
        accept: (q) => q['state'] == 'richtig',
      );
      expect(r.address.address, '127.0.0.1');
      expect(
        await _get(r.redirect.replace(queryParameters: {'state': 'x'})),
        400,
      );
      expect(
        await _get(r.redirect.replace(queryParameters: {'code': 'c'})),
        400,
      );
      expect(
        await _get(r.redirect.replace(queryParameters: {'state': 'richtig'})),
        200,
      );
      final uri = await wait;
      expect(uri.queryParameters['state'], 'richtig');
      await expectLater(_get(r.redirect), throwsA(isA<SocketException>()));
    },
  );
}
