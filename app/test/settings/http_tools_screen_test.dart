import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/export.dart';
import 'package:wendelin/ui/settings/http_tool_editor_screen.dart';
import 'package:wendelin/ui/settings/http_tools_screen.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/http_tools_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

/// Tall view: the editor is one long page.
const editorSize = Size(390, 4200);

Future<ProviderContainer> pumpHttpTools(
  WidgetTester tester,
  TestEnv env, {
  Size size = editorSize,
}) async {
  setView(tester, size);
  await tester.pumpWidget(env.app(home: const HttpToolsScreen()));
  await settle(tester);
  final c = ProviderScope.containerOf(
    tester.element(find.byType(HttpToolsScreen)),
  );
  // Der Abgleich läuft nur, wenn ihn jemand braucht (wie beim Start).
  c.read(userIntegrationSyncProvider);
  await syncSettle(tester);
  return c;
}

/// The sync runs in the test's fake zone: let it work in steps.
Future<void> syncSettle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await settle(tester);
  }
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

/// Fills a valid new tool `licht` (POST, argument `raum`, secret header).
Future<void> fillLicht(WidgetTester tester) async {
  await tester.tap(find.text('+ HTTP-Tool'));
  await settle(tester);
  await enter(tester, 'name', 'licht');
  await enter(tester, 'description', 'Schaltet das Licht im Raum');
  await tester.tap(find.widgetWithText(ChoiceChip, 'POST'));
  await tester.pump();
  await tester.tap(find.text('+ Argument'));
  await tester.pump();
  await enter(tester, 'argName0', 'raum');
  await enter(tester, 'url', 'https://api.example.org/licht/{raum}');
  await tester.tap(find.widgetWithText(ChoiceChip, 'Geheime Header'));
  await tester.pump();
  await tester.tap(find.text('+ Geheimer Header'));
  await tester.pump();
  await enter(tester, 'secretHeaderName0', 'X-Api-Key');
  await enter(tester, 'secretHeaderValue0', httpCanary);
}

String? problemText(WidgetTester tester) {
  final f = find.byKey(const ValueKey('problem'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

bool saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
        .onPressed !=
    null;

void main() {
  testWidgets('Anlegen: Speichern registriert http__licht, Secret nur im '
      'SecretStore, Integration eingeschaltet', (tester) async {
    final server = FakeHttpServer();
    final env = TestEnv(extraOverrides: [server.override]);
    final c = await pumpHttpTools(tester, env);
    await fillLicht(tester);
    expect(problemText(tester), isNull);
    // Methode POST schlägt write vor; ohne Schalter wird bestätigt.
    expect(find.widgetWithText(ChoiceChip, 'read'), findsNothing);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'write'),
    );
    expect(chip.selected, isTrue);

    await tester.tap(find.text('Speichern'));
    await settle(tester);
    await syncSettle(tester);

    expect(find.byType(HttpToolEditorScreen), findsNothing);
    expect(find.text('http__licht'), findsOneWidget);
    final registry = c.read(toolRegistryProvider);
    final info = registry.info(HttpToolsIntegration.plainId);
    expect(info.integration.tools.single.name, 'http__licht');
    expect(info.integration.tools.single.risk, RiskLevel.external);
    expect(info.status, IntegrationStatus.active);
    expect(
      await env.storage.settings.get(
        AppSettings.integrationEnabled(HttpToolsIntegration.plainId),
      ),
      isTrue,
    );
    final keys = await env.secrets.listKeys();
    expect(keys.single, startsWith(httpToolSecretNamespace));
    expect(await env.secrets.read(keys.single), httpCanary);
    final stored = await env.storage.settings.get(httpToolsSetting);
    expect(jsonEncode(stored), isNot(contains(httpCanary)));
    expect(jsonEncode(stored), contains('licht'));
  });

  testWidgets('Validierung: Name live, Platzhalter ohne Argument, '
      'Platzhalter im Host', (tester) async {
    final env = TestEnv();
    await pumpHttpTools(tester, env);
    await fillLicht(tester);
    expect(saveEnabled(tester), isTrue);

    await enter(tester, 'name', 'mit leer');
    expect(find.textContaining('Nur Buchstaben, Ziffern'), findsWidgets);
    expect(saveEnabled(tester), isFalse);
    await enter(tester, 'name', 'licht');

    await enter(tester, 'url', 'https://api.example.org/licht/{zimmer}');
    expect(
      problemText(tester),
      'Platzhalter „{zimmer}“ ist kein Argument im Schema',
    );
    expect(saveEnabled(tester), isFalse);
    // Hervorhebung: bekannte Platzhalter Akzent, unbekannte Fehlerfarbe.
    final field = tester.widget<TextField>(find.byKey(const ValueKey('url')));
    final span = field.controller!.buildTextSpan(
      context: tester.element(find.byKey(const ValueKey('url'))),
      withComposing: false,
    );
    final unknown = span.children!.whereType<TextSpan>().firstWhere(
      (s) => s.text == '{zimmer}',
    );
    expect(unknown.style!.color, WColors.error);

    await enter(tester, 'url', 'https://{raum}.example.org/licht');
    expect(problemText(tester), contains('Host'));
    expect(saveEnabled(tester), isFalse);

    await enter(tester, 'url', 'https://api.example.org/licht/{raum}');
    final ok = tester
        .widget<TextField>(find.byKey(const ValueKey('url')))
        .controller!
        .buildTextSpan(
          context: tester.element(find.byKey(const ValueKey('url'))),
          withComposing: false,
        );
    expect(
      ok.children!
          .whereType<TextSpan>()
          .firstWhere((s) => s.text == '{raum}')
          .style!
          .color,
      WColors.accentLight,
    );
    expect(problemText(tester), isNull);
  });

  testWidgets('Testlauf gegen MockClient: Status, Dauer, gesendete Anfrage '
      'ohne Secret, gekürzte Antwort; Zielprüfung verständlich', (
    tester,
  ) async {
    final server = FakeHttpServer(
      respond: (r) => http.Response(
        '{"state":"an","echo":"${r.headers['X-Api-Key']}"}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final env = TestEnv(extraOverrides: [server.override]);
    await pumpHttpTools(tester, env);
    await fillLicht(tester);
    await enter(tester, 'testArgraum', 'bad');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Testen'));
    await settle(tester);

    expect(server.requests.single.url.path, '/licht/bad');
    expect(server.requests.single.headers['X-Api-Key'], httpCanary);
    expect(find.byType(HttpTestResultView), findsOneWidget);
    expect(find.textContaining('HTTP 200'), findsOneWidget);
    expect(
      find.textContaining('POST https://api.example.org/licht/bad'),
      findsOneWidget,
    );
    expect(find.textContaining('X-Api-Key: $redactedSecret'), findsOneWidget);
    expect(find.textContaining('"state":"an"'), findsOneWidget);
    // Der Server spiegelt das Secret: bereinigt.
    final view = find.byType(HttpTestResultView);
    expect(
      find.descendant(of: view, matching: find.textContaining(httpCanary)),
      findsNothing,
    );
    expect(
      find.descendant(of: view, matching: find.textContaining(scrubbedSecret)),
      findsOneWidget,
    );
    expect(await env.secrets.listKeys(), isEmpty, reason: 'nicht gespeichert');

    await enter(tester, 'url', 'https://127.0.0.1/licht/{raum}');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Testen'));
    await settle(tester);
    expect(find.textContaining('Ziel nicht erlaubt'), findsOneWidget);
    expect(server.requests, hasLength(1));
  });

  testWidgets('Bearbeiten: Secret maskiert, nur ersetzbar; Löschen entfernt '
      'Tool und Secrets', (tester) async {
    final env = TestEnv();
    await storeHttpTools(env, [testHttpTool()]);
    final c = await pumpHttpTools(tester, env);
    expect(
      c.read(toolRegistryProvider).info('http').integration.tools.single.name,
      'http__licht',
    );
    await tester.tap(find.text('http__licht'));
    await settle(tester);
    expect(find.textContaining('$redactedSecret gespeichert'), findsOneWidget);
    expect(find.textContaining(httpCanary), findsNothing);
    expect(find.text('Ersetzen'), findsOneWidget);
    await tester.tap(find.text('Ersetzen'));
    await tester.pump();
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('secretHeaderValue0')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, isEmpty, reason: 'nie vorbefüllt');
    expect(field.obscureText, isTrue);

    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await settle(tester);
    await syncSettle(tester);
    expect(find.text('http__licht'), findsNothing);
    expect(await env.secrets.listKeys(), isEmpty);
    expect(
      c.read(toolRegistryProvider).integrations.map((i) => i.id),
      isNot(contains('http')),
    );
  });

  testWidgets('autoRun-Schalter nur bei write', (tester) async {
    final env = TestEnv();
    await pumpHttpTools(tester, env);
    await fillLicht(tester);
    WSwitch autoRun() => tester.widget<WSwitch>(
      find.byWidgetPredicate(
        (w) => w is WSwitch && w.semanticLabel == 'Ohne Nachfrage ausführen',
      ),
    );
    expect(autoRun().onChanged, isNotNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'external'));
    await tester.pump();
    expect(autoRun().onChanged, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'GET'));
    await tester.pump();
    expect(autoRun().onChanged, isNull);
  });

  testWidgets('Export ohne Secrets, Import über das Dialogfeld', (
    tester,
  ) async {
    final exported = <String>[];
    final env = TestEnv(
      extraOverrides: [
        exporterProvider.overrideWithValue(
          (name, mime, content) async => exported.add(content),
        ),
      ],
    );
    await storeHttpTools(env, [testHttpTool()]);
    await pumpHttpTools(tester, env);
    await tester.tap(find.text('Exportieren'));
    await settle(tester);
    expect(exported.single, contains('http__licht'.substring(6)));
    expect(exported.single, isNot(contains(httpCanary)));

    final other = exportHttpTools([testHttpTool(id: 'y', name: 'tor')]);
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('importJson')),
      jsonEncode(other),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Importieren'));
    await settle(tester);
    expect(find.text('http__tor'), findsOneWidget);
    expect(find.textContaining('1 HTTP-Tool importiert'), findsOneWidget);
    // Hinweis ablaufen lassen.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('importJson')), '{');
    await tester.tap(find.widgetWithText(FilledButton, 'Importieren'));
    await settle(tester);
    expect(find.textContaining('Import fehlgeschlagen'), findsOneWidget);
  });

  testWidgets('Detailseite: HTTP-write mit autoRun zeigt „kein Rückgängig“, '
      'eingebaute write-Tools „10 s rückgängig“', (tester) async {
    final env = TestEnv();
    await storeHttpTools(env, [
      testHttpTool(risk: RiskLevel.write, autoRun: true),
    ]);
    final c = await pumpHttpTools(tester, env);
    expect(c.read(toolRegistryProvider).status('http'), isNotNull);
    await tester.pumpWidget(
      env.app(home: const IntegrationDetailScreen('http')),
    );
    await syncSettle(tester);
    expect(
      find.text('ändert · ohne Nachfrage, kein Rückgängig'),
      findsOneWidget,
    );
    expect(find.textContaining('10 s rückgängig'), findsNothing);
    expect(
      riskText(RiskLevel.write, false),
      'ändert · ohne Nachfrage, 10 s rückgängig',
    );
    expect(
      riskText(RiskLevel.write, true, hasUndo: false),
      'ändert · fragt immer nach',
    );
  });

  testWidgets('Argumenttyp per Auswahl-Chip', (tester) async {
    final env = TestEnv();
    await pumpHttpTools(tester, env);
    await fillLicht(tester);
    await tester.tap(find.byKey(const ValueKey('argType0-integer')));
    await tester.pump();
    expect(find.text('raum (integer)'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });
}
