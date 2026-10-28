import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/integration_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/settings/ha_device_sections.dart';
import 'package:wendelin/ui/settings/ha_screen.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin_core/wendelin_core.dart' show Tool;
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../support/http_tools_support.dart';
import '../support/mcp_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart' show setView;
import 'integrations_screen_test.dart' show settle;
import 'other_screens_test.dart' show pumpPage;

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> open(WidgetTester tester, String id) async {
  final d = key('levelDetails_$id');
  await tester.ensureVisible(d);
  await tester.tap(d);
  await settle(tester);
}

Future<void> choose(WidgetTester tester, String kind, String level) async {
  final l = key('level_kind_${kind}_$level');
  if (l.evaluate().isEmpty) await open(tester, 'kind_$kind');
  await tester.ensureVisible(l);
  await tester.tap(l);
  await settle(tester);
}

/// Header text of the picker of the kind [k].
String head(WidgetTester tester, String k) => tester
    .widget<Text>(
      find.descendant(
        of: key('levelDetails_kind_$k'),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  Future<String?> stored(WidgetTester tester, TestEnv env) async =>
      (await tester.runAsync<String?>(
        () => env.secrets.read('ha.kind_levels'),
      ));

  testWidgets('Stufe je Geräteart: Abschnitt sichtbar, Wahl speichert, '
      'Standard stellt wieder her', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    expect(find.text('Stufe je Geräteart'), findsOneWidget);
    for (final k in ['light', 'media', 'scene', 'switch', 'climate', 'cover']) {
      expect(key('levelDetails_kind_$k'), findsOneWidget, reason: k);
    }
    expect(head(tester, 'light'), 'Details · Stufe B · Standard');
    expect(head(tester, 'switch'), 'Details · Stufe C · Standard');
    expect(find.textContaining('nur je Gerät'), findsOneWidget);

    await choose(tester, 'light', 'a');
    expect(await stored(tester, env), '{"light":"a"}');
    expect(head(tester, 'light'), 'Details · Stufe A · geändert');

    await tester.tap(key('levelRestore_kind_light'));
    await settle(tester);
    expect(await stored(tester, env), isNull);
    expect(head(tester, 'light'), 'Details · Stufe B · Standard');
  });

  testWidgets('Rollos und Schalter: Lockern auf A/B fragt vorher', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    setView(tester, const Size(390, 4000));
    await settle(tester);
    await choose(tester, 'cover', 'b');
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(await stored(tester, env), isNull);
    await choose(tester, 'cover', 'b');
    await tester.tap(find.text('Trotzdem ändern'));
    await settle(tester);
    expect(await stored(tester, env), '{"cover":"b"}');

    await choose(tester, 'switch', 'a');
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    // Verschärfen und Licht fragen nie.
    await choose(tester, 'switch', 'd');
    await choose(tester, 'light', 'a');
    expect(find.text('Weniger Schutz?'), findsNothing);
    expect(await stored(tester, env), contains('"switch":"d"'));
  });

  testWidgets('Kaputter Wert zeigt D, kaputter Speicher alle Arten D', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    await env.secrets.write('ha.kind_levels', '{"light":"x","media":5}');
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    expect(head(tester, 'light'), 'Details · Stufe D · geändert');
    expect(head(tester, 'media'), 'Details · Stufe D · geändert');
    expect(head(tester, 'switch'), 'Details · Stufe C · Standard');
  });

  testWidgets('Unlesbarer Speicher: jede Art D', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    await env.secrets.write('ha.kind_levels', 'kein json');
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    for (final k in ['light', 'media', 'scene', 'switch', 'climate', 'cover']) {
      expect(head(tester, k), 'Details · Stufe D · geändert', reason: k);
    }
  });

  testWidgets('Lesefehler im Art-Speicher: jede Art D (Abschnitt)', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'ha'},
      extraOverrides: [
        haKindLevelsProvider.overrideWith((ref) => throw StateError('kaputt')),
      ],
    );
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    for (final k in ['light', 'media', 'scene', 'switch', 'climate', 'cover']) {
      expect(head(tester, k), 'Details · Stufe D · geändert', reason: k);
    }
  });

  testWidgets('Lesefehler im Art-Speicher: Gerätezeile zeigt D von Geräteart', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'ha'},
      extraOverrides: [
        haKindLevelsProvider.overrideWith((ref) => throw StateError('kaputt')),
      ],
    );
    await env.secrets.write('ha.url', 'http://192.168.1.20:8123');
    await env.secrets.write('ha.token', 'kanarien-token');
    await env.secrets.write(
      'ha.entities',
      '[{"id":"light.kitchen","name":"Küche Deckenlicht","area":"Küche"}]',
    );
    await pumpPage(tester, env, const HaScreen());
    expect(find.text('Details · Stufe D · von Geräteart'), findsOneWidget);
  });

  testWidgets('ha__call und ha__call_secure verweisen auf die Stufen', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    expect(key('levelRef_ha__call'), findsOneWidget);
    expect(key('levelRef_ha__call_secure'), findsOneWidget);
    expect(find.textContaining('nach Geräteart'), findsNothing);
  });

  testWidgets('Gerätezeile zeigt „von Geräteart“, wenn die Art greift; '
      'eigene Stufe gewinnt', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    await env.secrets.write('ha.url', 'http://192.168.1.20:8123');
    await env.secrets.write('ha.token', 'kanarien-token');
    await env.secrets.write(
      'ha.entities',
      '[{"id":"light.kitchen","name":"Küche Deckenlicht","area":"Küche"},'
          '{"id":"light.living","name":"Wohnzimmer","area":"Küche","level":"d"}]',
    );
    await env.secrets.write('ha.kind_levels', '{"light":"a"}');
    await pumpPage(tester, env, const HaScreen());
    expect(find.text('Details · Stufe A · von Geräteart'), findsOneWidget);
    expect(key('levelRestore_light.kitchen'), findsNothing);
  });

  testWidgets('HaAreaSection: ohne Art-Wahl Standard, Rollo-Art greift nur '
      'für ruhige Klassen', (tester) async {
    Future<void> pump(HaKindLevels kinds, HaEntity e) async {
      await tester.pumpWidget(
        TestEnv().app(
          home: Scaffold(
            body: HaAreaSection(
              title: 'Raum',
              entities: [e],
              approved: {e.entityId},
              choiceOf: (x) => x,
              onToggle: (_, _) {},
              onLevel: (_, _) {},
              kinds: kinds,
            ),
          ),
        ),
      );
      await settle(tester);
    }

    const light = HaEntity(entityId: 'light.a', name: 'A');
    await pump(const HaKindLevels(), light);
    expect(find.text('Details · Stufe B · Standard'), findsOneWidget);
    // Garage (unbekannte Klasse): die Art greift nie, Standard D.
    const garage = HaEntity(entityId: 'cover.g', name: 'G');
    await pump(const HaKindLevels({'cover': 'a'}), garage);
    expect(find.text('Details · Stufe D · Standard'), findsOneWidget);
    const blind = HaEntity(
      entityId: 'cover.b',
      name: 'B',
      deviceClass: 'blind',
    );
    await pump(const HaKindLevels({'cover': 'c'}), blind);
    expect(find.text('Details · Stufe C · von Geräteart'), findsOneWidget);
  });

  testWidgets('Szene mit Art-Stufe A: Zeile nennt „höchstens“, nicht die '
      'Zusage; Art D bleibt D', (tester) async {
    Future<void> pump(HaKindLevels kinds) async {
      const e = HaEntity(entityId: 'scene.abend', name: 'Abend');
      await tester.pumpWidget(
        TestEnv().app(
          home: Scaffold(
            body: HaAreaSection(
              title: 'Raum',
              entities: [e],
              approved: {e.entityId},
              choiceOf: (x) => x,
              onToggle: (_, _) {},
              onLevel: (_, _) {},
              kinds: kinds,
            ),
          ),
        ),
      );
      await settle(tester);
    }

    await pump(const HaKindLevels({'scene': 'a'}));
    expect(
      find.text(
        'Details · Höchstens Stufe A · von Geräteart, je nach '
        'Mitgliedern',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Details · Stufe A'), findsNothing);
    await pump(const HaKindLevels({'scene': 'd'}));
    expect(find.text('Details · Stufe D · von Geräteart'), findsOneWidget);
  });

  testWidgets('Art-Abschnitt: vor dem Laden keine Wahl, danach Wahl ohne '
      'gespeicherte Arten zu überschreiben', (tester) async {
    final gate = Completer<HaKindLevels>();
    final env = TestEnv(
      enabled: const {'ha'},
      extraOverrides: [haKindLevelsProvider.overrideWith((_) => gate.future)],
    );
    await env.secrets.write('ha.kind_levels', '{"light":"d"}');
    await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    expect(key('haKindSection'), findsOneWidget);
    expect(key('levelDetails_kind_media'), findsNothing);
    gate.complete(const HaKindLevels({'light': 'd'}));
    await settle(tester);
    // Changed in the meantime (stale copy in the widget): kept as well.
    await tester.runAsync(
      () => env.secrets.write('ha.kind_levels', '{"light":"d","switch":"d"}'),
    );
    await choose(tester, 'media', 'a');
    expect(await stored(tester, env), '{"light":"d","switch":"d","media":"a"}');
  });

  testWidgets('Jedes Tool der Einstellungen hat eine Stufenauswahl oder einen '
      'Verweis', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    final c = await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    final all = c.read(integrationsProvider);
    // MCP- und HTTP-Tools kommen erst zur Laufzeit aus der Registry: sie
    // prüft der Test darunter, ihre eigenen Oberflächen die Tests in
    // `mcp/mcp_level_test.dart` und `settings/http_level_test.dart`.
    expect(all, isNotEmpty);
    final names = <String>{};
    final seen = <Tool>{};
    for (final i in all.values) {
      for (final t in i.tools) {
        // One instance may serve two integrations (maps__navigate, Waze).
        if (!seen.add(t)) continue;
        expect(names.add(t.name), isTrue, reason: 'doppelt: ${t.name}');
      }
    }
    // `tools__search` ist ein internes Meta-Tool (listet nur Beschreibungen
    // anderer Tools), es gehört zu keiner Integration.
    expect(names, isNot(contains('tools__search')));
    for (final entry in all.entries) {
      await pumpPage(tester, env, IntegrationDetailScreen(entry.key));
      for (final t in entry.value.tools) {
        expect(
          key('levelDetails_${t.name}').evaluate().isNotEmpty ||
              key('levelRef_${t.name}').evaluate().isNotEmpty,
          isTrue,
          reason: '${entry.key}/${t.name}: weder Stufenauswahl noch Verweis',
        );
      }
    }
  });

  testWidgets('MCP- und HTTP-Tools der Registry haben eine Stufenauswahl', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'mcp_homeserver', 'http'},
      extraOverrides: mcpOverrides(),
    );
    await tester.runAsync(() async {
      await seedServers(
        env,
        [
          (
            config: McpServerConfig(
              id: 'srv',
              name: 'Homeserver',
              slug: 'homeserver',
              url: Uri.parse('http://homeserver.local:3000/mcp'),
              auth: McpBearerAuth(McpSecretRefs.bearer('srv')),
            ),
            tools: homeToolInfos(),
            check: null,
          ),
        ],
        secrets: {McpSecretRefs.bearer('srv'): 'token'},
      );
      await storeHttpTools(env, [testHttpTool()]);
    });
    final c = await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    c.read(userIntegrationSyncProvider);
    for (var i = 0; i < 100; i++) {
      final ids = c.read(toolRegistryProvider).integrations.map((i) => i.id);
      if (ids.contains('mcp_homeserver') && ids.contains('http')) break;
      await settle(tester);
    }
    final tools = <String>[];
    for (final id in ['mcp_homeserver', 'http']) {
      await pumpPage(tester, env, IntegrationDetailScreen(id));
      final integration = c
          .read(toolRegistryProvider)
          .integrations
          .firstWhere((i) => i.id == id)
          .integration;
      expect(integration.tools, isNotEmpty, reason: id);
      for (final t in integration.tools) {
        tools.add(t.name);
        expect(key('levelDetails_${t.name}'), findsOneWidget, reason: t.name);
      }
    }
    expect(tools, contains('http__licht'));
    expect(tools, contains('mcp_homeserver__get_state'));
  });
}
