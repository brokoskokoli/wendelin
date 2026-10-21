import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/bring_share_card.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../screens/main_screen_test.dart'
    show containerOf, pumpApp, pumpUntil, send;
import '../settings/bring_screen_test.dart' show bringPassword, loginBring;
import '../support/http_tools_support.dart';
import '../support/test_env.dart';

/// Environment with HTTP tools and Bring! switched on.
TestEnv agentEnv(
  FakeLlmProvider provider, {
  FakeHttpServer? server,
  ToolPrefs toolPrefs = const ToolPrefs(),
  WendelinStorage? storage,
}) => TestEnv(
  providerConfig: scripted(provider),
  storage: storage,
  startup: StartupSettings(
    enabledIntegrations: const {'bring'},
    toolPrefs: toolPrefs,
  ),
  extraOverrides: [?server?.override],
);

Set<String> toolNamesOf(FakeLlmProvider provider) => {
  for (final t in provider.requests.first.tools) t.name,
};

void main() {
  testWidgets('HTTP-Tool write mit autoRun: ohne Bestätigung, ohne '
      'Rückgängig-Knopf', (tester) async {
    final server = FakeHttpServer();
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([call('c1', 'http__licht', '{"raum":"bad"}')]),
      ScriptedTurn.text('Licht ist an.'),
    ]);
    final env = agentEnv(provider, server: server);
    await storeHttpTools(env, [
      testHttpTool(risk: RiskLevel.write, autoRun: true),
    ]);
    await pumpApp(tester, env);
    await send(tester, 'Mach das Licht im Bad an');
    await pumpUntil(tester, find.text('Licht ist an.'));
    expect(find.byType(ConfirmationSheet), findsNothing);
    expect(server.requests.single.url.path, '/licht/bad');
    expect(find.textContaining('Rückgängig'), findsNothing);
    expect(find.byType(ToolResultCard), findsNothing);
    final chip = tester.widget<ToolChip>(find.byType(ToolChip));
    expect(chip.status, CheckStatus.ok);
    expect(toolNamesOf(provider), contains('http__licht'));
  });

  testWidgets('HTTP-Tool ohne autoRun (external): Bestätigungskarte mit '
      'Methode, Host und Pfad', (tester) async {
    final server = FakeHttpServer();
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([call('c1', 'http__licht', '{"raum":"bad"}')]),
      ScriptedTurn.text('Erledigt.'),
    ]);
    final env = agentEnv(provider, server: server);
    await storeHttpTools(env, [testHttpTool(risk: RiskLevel.write)]);
    await pumpApp(tester, env);
    await send(tester, 'Mach das Licht im Bad an');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('POST api.example.org/licht/bad'),
      findsOneWidget,
    );
    expect(find.text('http__licht · Stufe external'), findsOneWidget);
    expect(server.requests, isEmpty);
    await tester.tap(find.text('Ja, ausführen'));
    await pumpUntil(tester, find.text('Erledigt.'));
    expect(server.requests, hasLength(1));
  });

  testWidgets('sensible Definition wird Standard-Zielen nicht angeboten', (
    tester,
  ) async {
    final provider = FakeLlmProvider([ScriptedTurn.text('Hallo.')]);
    final env = agentEnv(
      provider,
      toolPrefs: const ToolPrefs(sensitiveMinimum: PrivacyLevel.eu),
    );
    await storeHttpTools(env, [
      testHttpTool(),
      testHttpTool(id: 's', name: 'tresor', sensitive: true),
    ]);
    await pumpApp(tester, env);
    await send(tester, 'Hallo');
    await pumpUntil(tester, find.text('Hallo.'));
    final names = toolNamesOf(provider);
    expect(names, contains('http__licht'));
    expect(names, isNot(contains('http__tresor')));
  });

  testWidgets('Bring!: Artikel hinzufügen mit Rückgängig auf der Tool-Karte', (
    tester,
  ) async {
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        call('c1', 'bring__add_items', '{"items":[{"name":"Eier"}]}'),
      ]),
      // Fester Satz (WP122): die Modellantwort entfällt.
    ]);
    final env = agentEnv(provider);
    await loginBring(env);
    await pumpApp(tester, env);
    await send(tester, 'Setz Eier auf die Bring-Liste');
    await pumpUntil(tester, find.textContaining('auf der Liste'));
    final zuhause = env.bring.list('list-zuhause')!;
    expect(zuhause.purchase.map((i) => i.name), contains('Eier'));
    final undo = find.textContaining('Rückgängig · ');
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await pumpUntil(tester, find.text('Rückgängig gemacht'));
    expect(zuhause.purchase.map((i) => i.name), isNot(contains('Eier')));
    expect(find.byType(BringShareCard), findsNothing);
  });

  for (final installed in [true, false]) {
    testWidgets('Bring! nicht erreichbar: „An Bring! senden“ nur mit '
        'installierter App (installiert: $installed)', (tester) async {
      final provider = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          call(
            'c1',
            'bring__add_items',
            '{"items":[{"name":"Milch","spec":"2 Liter"},{"name":"Eier"}]}',
          ),
        ]),
        ScriptedTurn.text('Bring! klemmt gerade.'),
      ]);
      final env = agentEnv(provider);
      if (!installed) env.apps.uninstall(BringAppFallback.androidPackage);
      await loginBring(env);
      env.bring.failNext(
        'lists',
        const PortException(
          PortErrorKind.unavailable,
          'Bring! nicht erreichbar',
        ),
      );
      await pumpApp(tester, env);
      await send(tester, 'Setz Milch und Eier auf die Bring-Liste');
      await pumpUntil(tester, find.text('Bring! klemmt gerade.'));
      await tester.pump();
      final chip = tester.widget<ToolChip>(find.byType(ToolChip));
      expect(chip.status, CheckStatus.failed);
      if (!installed) {
        expect(find.text('An Bring! senden'), findsNothing);
        return;
      }
      await pumpUntil(tester, find.text('An Bring! senden'));
      expect(find.text('Milch (2 Liter), Eier'), findsOneWidget);
      await tester.tap(find.text('An Bring! senden'));
      await tester.pump();
      expect(env.shared, [
        (BringAppFallback.androidPackage, 'Milch (2 Liter)\nEier'),
      ]);
      expect(find.text('An Bring! gesendet'), findsOneWidget);
    });
  }

  testWidgets('Kanarienwerte: geheimer Header und Bring!-Passwort nie in '
      'Einstellungen, Export, Audit-Log, Debug-Log', (tester) async {
    final logs = <String>[];
    final oldPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add('$message');

    final executor = NativeDatabase.memory();
    final storage = WendelinStorage(executor, clock: FixedClock(testNow));
    final server = FakeHttpServer(
      // Der Server spiegelt alles, auch das Secret.
      respond: (r) => http.Response(
        jsonEncode({'echo': r.headers}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        call('c1', 'http__licht', '{"raum":"bad"}'),
        call('c2', 'bring__add_items', '{"items":[{"name":"Eier"}]}'),
      ]),
      ScriptedTurn.text('Fertig.'),
    ]);
    final env = agentEnv(provider, server: server, storage: storage);
    await storeHttpTools(env, [
      testHttpTool(risk: RiskLevel.write, autoRun: true),
    ]);
    await loginBring(env);
    await pumpApp(tester, env);
    await send(tester, 'Licht an und Eier auf die Liste');
    await pumpUntil(tester, find.text('Fertig.'));
    expect(server.requests.single.headers['X-Api-Key'], httpCanary);

    // Ergebnis ans Modell bereinigt.
    final results = jsonEncode([
      for (final m in provider.requests.last.messages) m.toString(),
    ]);
    expect(results, isNot(contains(httpCanary)));

    final container = containerOf(tester);
    final rows = await tester.runAsync(
      () => executor.runSelect('SELECT key, value_json FROM settings', []),
    );
    final settingsJson = jsonEncode(rows);
    expect(settingsJson, contains('http.tools'));
    final export = await tester.runAsync(
      () => container.read(httpToolRepositoryProvider).exportJson(),
    );
    await tester.runAsync(() => storage.audit.query());
    final audit = await tester.runAsync(storage.audit.exportJson);
    expect(audit, contains('http__licht'));
    expect(audit, contains('bring__add_items'));
    // Nach dem Login bleibt nur die Sitzung im Speicher; ihre Tokens
    // tauchen weder in Einstellungen noch in Exporten oder Logs auf.
    expect(
      (await env.secrets.listKeys()).where((k) => k.startsWith('bring.')),
      {'bring.session'},
    );
    final session = jsonDecode(
      (await env.secrets.read('bring.session'))!,
    ) as Map<String, Object?>;
    final tokens = [session['accessToken']! as String];
    if (session['refreshToken'] case final String r) tokens.add(r);
    for (final (what, text) in [
      ('Einstellungen', settingsJson),
      ('Export', export!),
      ('Audit-Log', audit!),
      ('Debug-Log', logs.join('\n')),
    ]) {
      for (final canary in [httpCanary, bringPassword, ...tokens]) {
        expect(text, isNot(contains(canary)), reason: '$what: $canary');
      }
    }
    debugPrint = oldPrint;
  });
}
