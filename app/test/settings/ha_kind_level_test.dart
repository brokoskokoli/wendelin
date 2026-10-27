import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_providers.dart';
import 'package:wendelin/ui/settings/ha_device_sections.dart';
import 'package:wendelin/ui/settings/ha_screen.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

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

  testWidgets('Jedes Tool der Einstellungen hat eine Stufenauswahl oder einen '
      'Verweis', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    final c = await pumpPage(tester, env, const IntegrationDetailScreen('ha'));
    final all = c.read(integrationsProvider);
    // Bekannte Lücke (TODO WP160-2c): MCP- und HTTP-Tools kommen erst zur
    // Laufzeit aus der Registry und sind hier nicht aufgezählt.
    expect(all, isNotEmpty);
    final names = <String>{};
    for (final i in all.values) {
      for (final t in i.tools) {
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
}
