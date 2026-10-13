import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin/ui/settings/providers_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../di/provider_setup_test.dart' show RecordingFactory;
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _key = 'testschluessel-widget-0123456789-GEHEIM';

Future<TestEnv> pumpProviders(
  WidgetTester tester,
  RecordingFactory f, {
  TestEnv? env,
}) async {
  final e = env ?? TestEnv(storedProfiles: true, llmFactory: f.call);
  setView(tester, const Size(390, 1600));
  await tester.pumpWidget(e.app(home: const ProvidersScreen()));
  await tester.pumpAndSettle();
  return e;
}

Future<void> openNew(WidgetTester tester) async {
  await tester.tap(find.text('+ Provider'));
  await tester.pumpAndSettle();
}

Future<void> chooseClaudeAndConnect(WidgetTester tester) async {
  await tester.tap(find.text('Claude'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('apiKey')), _key);
  await tester.tap(find.text('Verbindung testen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('erfolgreich: Modelle laden, wählen, prüfen, Budget, Speichern', (
    tester,
  ) async {
    final f = RecordingFactory(
      models: const [
        ModelInfo(id: 'claude-haiku-5-5', displayName: 'Claude Haiku'),
        ModelInfo(id: 'claude-sonnet-5', displayName: 'Claude Sonnet'),
      ],
    );
    final env = await pumpProviders(tester, f);
    await openNew(tester);
    expect(find.text('Ollama'), findsOneWidget);
    await chooseClaudeAndConnect(tester);

    expect(f.keysSeen, [_key], reason: 'liest den Key aus dem Store');
    expect(f.probedModels, isEmpty, reason: 'noch kein Modell geprüft');
    expect(find.text('Claude Haiku'), findsOneWidget);
    await tester.tap(find.text('Claude Sonnet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    expect(f.probedModels, ['claude-sonnet-5']);
    expect(find.text('Verbindung ok'), findsOneWidget);
    expect(find.text('✓ Tools · ✕ Bilder'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('90 % des Budgets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.byType(ProvidersScreen), findsOneWidget);
    final p = (await env.storage.providerProfiles.list()).single;
    expect(p.name, 'Claude');
    expect(p.defaultModel, 'claude-sonnet-5');
    expect(p.budgetMonthly, 5000000);
    expect(p.warnThreshold, 0.9);
    final ref = (p.authMethod as ApiKeyAuth).secretRef;
    expect(await env.secrets.read(ref), _key);
    expect(p.toJson().toString(), isNot(contains(_key)));
    expect((await env.storage.providerProfiles.defaultProfile())!.id, p.id);
  });

  testWidgets('Key-Feld ist nach „Verbindung testen“ leer', (tester) async {
    final f = RecordingFactory(ok: false);
    await pumpProviders(tester, f);
    await openNew(tester);
    await chooseClaudeAndConnect(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('apiKey')),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.text(_key), findsNothing);
  });

  testWidgets('falscher Key: Meldung, kein Profil, Key wird beim Verlassen '
      'gelöscht', (tester) async {
    final f = RecordingFactory(ok: false);
    final env = await pumpProviders(tester, f);
    await openNew(tester);
    await chooseClaudeAndConnect(tester);
    expect(find.text('API-Key ungültig (401)'), findsOneWidget);
    expect(
      find.text('Key gespeichert – leer lassen behält ihn'),
      findsOneWidget,
    );
    expect(await env.secrets.listKeys(), hasLength(1));
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(await env.storage.providerProfiles.list(), isEmpty);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets(
    'Regression: Ollama ohne Modellvorschlag erreicht die Modellwahl',
    (tester) async {
      final f = RecordingFactory(
        models: const [
          ModelInfo(id: 'qwen2.5:7b'),
          ModelInfo(id: 'llama3.2'),
        ],
      );
      final env = await pumpProviders(tester, f);
      await openNew(tester);
      await tester.tap(find.text('Ollama'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Base-URL'),
        'http://nas:11434/v1',
      );
      await tester.tap(find.text('Verbindung testen'));
      await tester.pumpAndSettle();
      expect(find.text('qwen2.5:7b'), findsWidgets, reason: 'Modellwahl');
      await tester.tap(find.text('llama3.2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modell prüfen'));
      await tester.pumpAndSettle();
      expect(f.probedModels, ['llama3.2']);
      await tester.tap(find.text('lokal').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final p = (await env.storage.providerProfiles.list()).single;
      expect(p.baseUrl, 'http://nas:11434/v1');
      expect(p.defaultModel, 'llama3.2');
      expect(p.privacy, PrivacyLevel.local);
      expect(p.authMethod, const NoAuth());
    },
  );

  testWidgets('Probe mit unbekanntem Modell: Meldung, bleibt bei der Wahl', (
    tester,
  ) async {
    final f = RecordingFactory(models: const [ModelInfo(id: 'm1')]);
    await pumpProviders(tester, f);
    await openNew(tester);
    await chooseClaudeAndConnect(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Modell-ID'),
      'tippfehler',
    );
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    expect(find.text('model tippfehler unbekannt (404)'), findsOneWidget);
    expect(find.text('Modell prüfen'), findsOneWidget);
  });

  testWidgets('Server ohne Modellliste: Modell-ID frei eingeben', (
    tester,
  ) async {
    final f = RecordingFactory(
      listError: const ServerException('Not Found', statusCode: 404),
    );
    final env = await pumpProviders(tester, f);
    await openNew(tester);
    await tester.tap(find.text('Eigener Endpunkt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Base-URL'),
      'http://nas:8080/v1',
    );
    await tester.tap(find.text('Verbindung testen'));
    await tester.pumpAndSettle();
    expect(find.text('Modelle'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Modell-ID'), 'qwen');
    await tester.pump();
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await env.storage.providerProfiles.list()).single.defaultModel,
      'qwen',
    );
  });

  testWidgets('ungültiges Budget wird gemeldet', (tester) async {
    final f = RecordingFactory(models: const [ModelInfo(id: 'm')]);
    final env = await pumpProviders(tester, f);
    await openNew(tester);
    await chooseClaudeAndConnect(tester);
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'viel');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Betrag in Dollar'), findsOneWidget);
    expect(await env.storage.providerProfiles.list(), isEmpty);
  });

  group('Profil bearbeiten', () {
    final existing = ProviderProfile(
      id: 'claude-7',
      name: 'Claude privat',
      type: ProviderType.anthropic,
      baseUrl: providerTemplateById('claude')!.baseUrl,
      defaultModel: 'm1',
      privacy: PrivacyLevel.standard,
      authMethod: const ApiKeyAuth('provider.claude-7.apiKey'),
      budgetMonthly: 2500000,
      warnThreshold: 0.5,
    );

    Future<TestEnv> openEdit(WidgetTester tester, RecordingFactory f) async {
      final env = TestEnv(storedProfiles: true, llmFactory: f.call);
      await env.storage.providerProfiles.save(existing);
      await env.secrets.write('provider.claude-7.apiKey', 'alter-key');
      await pumpProviders(tester, f, env: env);
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      return env;
    }

    testWidgets('gleiche Id, Felder vorbelegt, alter Key bleibt', (
      tester,
    ) async {
      final f = RecordingFactory(
        models: const [
          ModelInfo(id: 'm1'),
          ModelInfo(id: 'm2'),
        ],
      );
      final env = await openEdit(tester, f);
      expect(find.text('Provider bearbeiten'), findsOneWidget);
      expect(find.text('Claude privat'), findsOneWidget);
      expect(find.text('Andere Vorlage'), findsNothing);
      await tester.tap(find.text('Verbindung testen'));
      await tester.pumpAndSettle();
      expect(f.keysSeen.single, 'alter-key');
      await tester.tap(find.text('m2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modell prüfen'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2,50'), findsOneWidget);
      await tester.tap(find.text('EU').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final p = (await env.storage.providerProfiles.list()).single;
      expect(p.id, 'claude-7');
      expect(p.name, 'Claude privat');
      expect(p.defaultModel, 'm2');
      expect(p.privacy, PrivacyLevel.eu);
      expect(p.budgetMonthly, 2500000);
      expect(p.warnThreshold, 0.5);
      expect(p.authMethod, const ApiKeyAuth('provider.claude-7.apiKey'));
      expect(await env.secrets.read('provider.claude-7.apiKey'), 'alter-key');
    });

    testWidgets('Key ersetzen: neuer Key gilt, alter wird gelöscht', (
      tester,
    ) async {
      final f = RecordingFactory(models: const [ModelInfo(id: 'm1')]);
      final env = await openEdit(tester, f);
      await tester.enterText(find.byKey(const ValueKey('apiKey')), 'neuer-key');
      await tester.tap(find.text('Verbindung testen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modell prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final p = (await env.storage.providerProfiles.list()).single;
      final ref = (p.authMethod as ApiKeyAuth).secretRef;
      expect(await env.secrets.read(ref), 'neuer-key');
      expect(await env.secrets.listKeys(), {ref});
    });

    testWidgets('Abbrechen nach neuem Key: alter Key und Profil unverändert', (
      tester,
    ) async {
      final f = RecordingFactory(models: const [ModelInfo(id: 'm1')]);
      final env = await openEdit(tester, f);
      await tester.enterText(find.byKey(const ValueKey('apiKey')), 'neuer-key');
      await tester.tap(find.text('Verbindung testen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(await env.secrets.listKeys(), {'provider.claude-7.apiKey'});
      expect(await env.secrets.read('provider.claude-7.apiKey'), 'alter-key');
      expect(
        (await env.storage.providerProfiles.get('claude-7'))!.defaultModel,
        'm1',
      );
    });

    test('Vorlage zum Profil', () {
      expect(templateFor(existing).id, 'claude');
      expect(
        templateFor(
          existing.copyWith(
            type: ProviderType.openaiCompatible,
            baseUrl: 'http://nas:8080/v1',
          ),
        ).id,
        'custom',
      );
      expect(
        templateFor(
          existing.copyWith(
            type: ProviderType.openaiCompatible,
            baseUrl: 'https://api.mistral.ai/v1',
          ),
        ).id,
        'mistral',
      );
    });
  });
}
