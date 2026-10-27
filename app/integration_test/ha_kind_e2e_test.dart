// Gerätetest WP160 (E2E-Agent, uncommittet): Stufe je Geräteart mit Fake-HA.
// Läuft mit `tool/e2e_android.sh integration_test/wp160_ha_kind_e2e_test.dart`
// (Skript startet den Fake-HA für `ha_*`; deshalb hier der Name ha_ -> siehe
// Dateiname-Hinweis im Bericht). Geräte: light.kitchen (Licht),
// lock.front (Schloss), cover.garage (device_class garage).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/app.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/locked_scope.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';

const _url = String.fromEnvironment('HA_URL');
const _token = String.fromEnvironment('HA_TOKEN');

ProviderContainer _container(List<Override> overrides) {
  final storage = openInMemoryStorage();
  // Echter SecureSecretStore (Android-Keystore): Token und Art-Stufen
  // überleben einen "Neustart" (neuer Container).
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      startupProvider.overrideWithValue(
        const StartupSettings(enabledIntegrations: {'ha'}, uiLanguage: 'de'),
      ),
      ...overrides,
    ],
  );
  addTearDown(() async {
    c.dispose();
    await storage.close();
  });
  return c;
}

ToolCallBlock _call(String id, String entity, String service) => ToolCallBlock(
  id: id,
  name: 'ha__call',
  argumentsJson: '{"entity":"$entity","service":"$service"}',
);

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Verbindet, setzt Ausgangszustand, gibt (container, api) zurück.
  Future<(ProviderContainer, HaApi)> setup(
    WidgetTester tester,
    FakeLlmProvider llm,
    Map<HaKind, SecurityLevel> kinds,
  ) async {
    final c = _container([
      storedProviderConfigProvider.overrideWith(
        (ref) async => deviceTestProviderConfig(llm),
      ),
    ]);
    late HaApi api;
    await tester.runAsync(() async {
      await c.read(toolRegistryReadyProvider.future);
      api = c.read(haApiProvider);
      final store = c.read(haStoreProvider);
      await store.clear(); // Ausgangszustand: keine alten Daten
      expect(await store.kindLevels(), isA<HaKindLevels>());
      expect((await store.kindLevels()).raw, isEmpty);
      expect(
        await haConnect(api: api, store: store, address: _url, token: _token),
        isNull,
      );
      final all = await api.entities();
      // Alle Geräte freigeben, keine eigenen Gerätestufen (Standard/Art).
      await store.save([
        for (final e in all)
          if (const {
            'light.kitchen',
            'lock.front',
            'cover.garage',
          }.contains(e.entityId))
            e,
      ]);
      var levels = const HaKindLevels();
      for (final MapEntry(:key, :value) in kinds.entries) {
        levels = levels.withLevel(key, value);
      }
      await store.saveKindLevels(levels);
      await c.read(toolRegistryProvider).refresh('ha');
      // Ausgangszustand Fake-HA
      await api.callService((
        domain: 'light',
        service: 'turn_off',
        data: {'entity_id': 'light.kitchen'},
      ));
      expect((await api.state('light.kitchen')).state, 'off');
      expect((await api.state('lock.front')).state, 'locked');
      expect((await api.state('cover.garage')).state, 'closed');
      expect(
        (await api.state('cover.garage')).attributes['device_class'],
        'garage',
      );
    });
    return (c, api);
  }

  Future<Map<String, ToolCallFinished>> lockedRun(
    WidgetTester tester,
    ProviderContainer c,
    String text,
  ) async {
    late Map<String, ToolCallFinished> finished;
    await tester.runAsync(() async {
      final scope = await c.read(lockedScopeProvider)(
        AccessContext.lockedUnknownVoice,
      );
      expect(scope, isNotNull, reason: 'Art Licht A erlaubt gesperrten Lauf');
      expect(scope!.tools, contains('ha__call'));
      final events = await c
          .read(agentControllerProvider.notifier)
          .submit(UserInput(text: text), locked: scope)
          .toList();
      expect(events.last, isA<AgentDone>());
      finished = {
        for (final e in events.whereType<ToolCallFinished>()) e.call.id: e,
      };
    });
    return finished;
  }

  testWidgets('S1 gesperrt: Licht an läuft ohne Entsperren (Art Licht A)', (
    tester,
  ) async {
    expect(_url, startsWith('http://10.0.2.2:'), reason: 'HA_URL fehlt');
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([_call('k', 'light.kitchen', 'turn_on')]),
      ScriptedTurn.text('Licht ist an.'),
    ]);
    final (c, api) = await setup(tester, llm, {HaKind.light: SecurityLevel.a});
    final f = await lockedRun(tester, c, 'Licht an');
    expect(f['k']!.outcome.isError, isFalse, reason: f['k']!.outcome.summary);
    await tester.runAsync(() async {
      expect((await api.state('light.kitchen')).state, 'on');
      expect((await api.state('lock.front')).state, 'locked');
      // Hintergrund-Sync auslaufen lassen, bevor der Container fällt.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await c.read(haStoreProvider).clear();
    });
  });

  testWidgets('K1 Kontrolle: ohne Art-Stufe (Licht Standard B) gesperrt ohne '
      'Stimme kein Licht', (tester) async {
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([_call('k', 'light.kitchen', 'turn_on')]),
      ScriptedTurn.text('x'),
    ]);
    final (c, api) = await setup(tester, llm, {});
    await tester.runAsync(() async {
      final scope = await c.read(lockedScopeProvider)(
        AccessContext.lockedUnknownVoice,
      );
      debugPrint('E2E K1 scope=${scope == null ? 'null' : scope.tools}');
      if (scope != null) {
        final events = await c
            .read(agentControllerProvider.notifier)
            .submit(UserInput(text: 'Licht an'), locked: scope)
            .toList();
        debugPrint(
          'E2E K1 ${[for (final e in events.whereType<ToolCallFinished>()) e.outcome.summary]}',
        );
      }
      expect((await api.state('light.kitchen')).state, 'off');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await c.read(haStoreProvider).clear();
    });
  });

  testWidgets('S2 gesperrt: Schloss auf wird abgewiesen', (tester) async {
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([_call('s', 'lock.front', 'unlock')]),
      ScriptedTurn.text('Nicht möglich.'),
    ]);
    final (c, api) = await setup(tester, llm, {HaKind.light: SecurityLevel.a});
    final f = await lockedRun(tester, c, 'Schloss auf');
    expect(f['s']!.outcome.summary, 'Entsperren nötig');
    await tester.runAsync(() async {
      expect((await api.state('lock.front')).state, 'locked');
      // Hintergrund-Sync auslaufen lassen, bevor der Container fällt.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await c.read(haStoreProvider).clear();
    });
  });

  testWidgets('S3 Art Rollos A: gesperrt Garage auf bleibt abgewiesen', (
    tester,
  ) async {
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([_call('g', 'cover.garage', 'open_cover')]),
      ScriptedTurn.text('Nicht möglich.'),
    ]);
    final (c, api) = await setup(tester, llm, {
      HaKind.light: SecurityLevel.a,
      HaKind.cover: SecurityLevel.a,
    });
    final f = await lockedRun(tester, c, 'Garage auf');
    expect(f['g']!.outcome.summary, 'Entsperren nötig');
    await tester.runAsync(() async {
      expect((await api.state('cover.garage')).state, 'closed');
      // Hintergrund-Sync auslaufen lassen, bevor der Container fällt.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await c.read(haStoreProvider).clear();
    });
  });

  testWidgets('S4 Einstellungen: Abschnitt sichtbar, Wahl bleibt nach '
      'Neustart', (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c1 = _container([]);
    await tester.runAsync(() => c1.read(haStoreProvider).clear());
    Future<void> pumpScreen(ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const WendelinApp(home: IntegrationDetailScreen('ha')),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    String head(String k) => tester
        .widget<Text>(
          find.descendant(
            of: _key('levelDetails_kind_$k'),
            matching: find.byType(Text),
          ),
        )
        .data!;

    await pumpScreen(c1);
    expect(_key('haKindSection'), findsOneWidget);
    expect(find.text('Stufe je Geräteart'), findsOneWidget);
    debugPrint('E2E S4 vorher: light="${head('light')}"');
    expect(head('light'), contains('Standard'));
    await tester.ensureVisible(_key('levelDetails_kind_light'));
    await tester.tap(_key('levelDetails_kind_light'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('level_kind_light_a'));
    await tester.tap(_key('level_kind_light_a'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    debugPrint('E2E S4 nach Wahl: light="${head('light')}"');
    expect(head('light'), 'Details · Stufe A · geändert');

    // "Neustart": Widgetbaum und Container weg, neuer Container, gleicher
    // Keystore.
    await tester.pumpWidget(const SizedBox());
    c1.dispose();
    final c2 = _container([]);
    await pumpScreen(c2);
    debugPrint('E2E S4 nach Neustart: light="${head('light')}"');
    expect(head('light'), 'Details · Stufe A · geändert');
    expect(head('switch'), contains('Standard'));
    await tester.runAsync(() => c2.read(haStoreProvider).clear());
  });
}
