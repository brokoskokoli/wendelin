import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_en.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/export.dart';
import 'package:wendelin/ui/settings/routing/condition_builder.dart';
import 'package:wendelin/ui/settings/routing/routing_screen.dart';
import 'package:wendelin/ui/settings/routing/routing_texts.dart';
import 'package:wendelin/ui/settings/routing/rule_editor_screen.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'other_screens_test.dart' show ExportLog;

ProviderProfile _profile(
  String id,
  String name,
  PrivacyLevel privacy,
  String model,
) => ProviderProfile(
  id: id,
  name: name,
  type: ProviderType.anthropic,
  defaultModel: model,
  privacy: privacy,
  authMethod: ApiKeyAuth('provider.$id.apiKey'),
);

final _profiles = [
  _profile('claude', 'Claude API', PrivacyLevel.standard, 'Sonnet'),
  // A real, checked Phala profile (WP52: TEE only with attestation).
  _profile('phala', 'Phala GLM', PrivacyLevel.tee, 'GLM klein').copyWith(
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://api.redpill.ai/v1',
    options: const {'attestation': 'phala'},
  ),
  _profile('ollama', 'Ollama Homeserver', PrivacyLevel.local, 'qwen'),
];

/// The rules of docs/design/screens/routing.
RuleSet designRules() => RuleSet(
  rules: [
    RoutingRule(
      id: 'stark',
      name: 'Starkes Modell',
      condition: PrefixCondition(['Claude', 'Fable']),
      target: const RouteTarget(profileId: 'claude', modelId: 'Opus'),
      stripTrigger: true,
    ),
    RoutingRule(
      id: 'privat',
      name: 'Privat',
      condition: PrivacyCondition(['privat']),
      target: const RouteTarget(profileId: 'phala', modelId: 'GLM klein'),
    ),
    RoutingRule(
      id: 'offline',
      name: 'Offline',
      condition: const NetworkCondition(NetworkState.offline),
      target: const RouteTarget(profileId: 'ollama', modelId: 'qwen'),
    ),
    RoutingRule(
      id: 'notizen',
      name: 'Notizen umschreiben',
      condition: const NeedsToolCondition('obsidian.edit'),
      target: const RouteTarget(profileId: 'claude', modelId: 'Sonnet'),
    ),
  ],
  defaultTarget: const RouteTarget(profileId: 'phala', modelId: 'GLM klein'),
);

/// Environment with the design's profiles and [rules].
Future<TestEnv> routingEnv({
  RuleSet? rules,
  Set<String> toolCategories = const {},
  List<dynamic> overrides = const [],
  Future<String?> Function()? importer,
  ExportLog? exports,
}) async {
  final env = TestEnv(
    storedProfiles: true,
    llmFactory: (p, _) => FakeLlmProvider(const []),
    extraOverrides: [
      toolCategoryMatcherProvider.overrideWithValue(
        FakeToolCategoryMatcher(toolCategories),
      ),
      if (importer != null) routingImporterProvider.overrideWithValue(importer),
      if (exports != null) exporterProvider.overrideWithValue(exports.call),
    ],
  );
  for (final p in _profiles) {
    await env.storage.providerProfiles.save(p);
  }
  await env.storage.providerProfiles.setDefault('phala');
  await env.storage.settings.set(RoutingSettings.rules, rules ?? designRules());
  return env;
}

Future<ProviderContainer> pumpRouting(
  WidgetTester tester,
  TestEnv env, {
  Size size = const Size(390, 1800),
}) async {
  setView(tester, size);
  await tester.pumpWidget(env.app(home: const RoutingScreen()));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(RoutingScreen)));
}

Future<RuleSet> stored(TestEnv env) async =>
    (await env.storage.settings.get(RoutingSettings.rules))!;

Finder ruleTile(String name) => find.widgetWithText(RuleTile, name);

RuleTile tileOf(WidgetTester tester, String name) =>
    tester.widget<RuleTile>(ruleTile(name));

Future<void> testSentence(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find
          .ancestor(of: find.text('Testsatz'), matching: find.byType(Container))
          .first,
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Testfeld: Regel 1 greift, Kobalt-Rahmen, Default fest', (
    tester,
  ) async {
    await pumpRouting(tester, await routingEnv());
    expect(find.byType(RuleTile), findsNWidgets(5));
    expect(find.text('prefix "Claude" | "Fable"'), findsNothing);
    expect(
      tileOf(tester, 'Starkes Modell').condition,
      'prefix "Claude" | "Fable"',
    );
    expect(tileOf(tester, 'Starkes Modell').target, 'Opus');
    expect(tileOf(tester, 'Offline').targetLevel, PrivacyLevel.local);
    expect(tileOf(tester, 'Default').target, 'Phala GLM');

    await testSentence(
      tester,
      'Claude, denk gründlich über meinen Wochenplan nach',
    );
    expect(find.text('Regel 1'), findsOneWidget);
    expect(find.text('greift → Claude API · Opus'), findsOneWidget);
    expect(tileOf(tester, 'Starkes Modell').active, isTrue);
    expect(tileOf(tester, 'Default').active, isFalse);

    await testSentence(tester, 'Wie wird das Wetter?');
    expect(find.text('Standard'), findsOneWidget);
    expect(tileOf(tester, 'Default').active, isTrue);
    expect(tileOf(tester, 'Starkes Modell').active, isFalse);

    // Default: gestrichelt, ohne Ziehgriff, nach der Liste.
    final def = tileOf(tester, 'Default');
    expect(def.isDefault, isTrue);
    expect(
      find.descendant(
        of: ruleTile('Default'),
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ReorderableListView),
        matching: ruleTile('Default'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: ruleTile('Offline'),
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Regel „offline“ greift bei Fake-Netz offline', (tester) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    await testSentence(tester, 'Wie wird das Wetter?');
    expect(find.text('Standard'), findsOneWidget);

    env.network.current = NetworkState.offline;
    await testSentence(tester, 'Wie wird das Wetter morgen?');
    expect(find.text('Regel 3'), findsOneWidget);
    expect(find.text('greift → Ollama Homeserver · qwen'), findsOneWidget);
    expect(tileOf(tester, 'Offline').active, isTrue);
  });

  testWidgets('Drag-and-drop ändert Reihenfolge und Testergebnis', (
    tester,
  ) async {
    final env = await routingEnv(toolCategories: {'obsidian.edit'});
    await pumpRouting(tester, env);
    await testSentence(tester, 'Claude, schreib meine Notiz um');
    expect(find.text('Regel 1'), findsOneWidget);
    expect(tileOf(tester, 'Starkes Modell').active, isTrue);

    // „Notizen umschreiben“ am Griff ganz nach oben ziehen.
    final handle = find.descendant(
      of: ruleTile('Notizen umschreiben'),
      matching: find.byType(ReorderableDragStartListener),
    );
    expect(handle, findsOneWidget);
    final from = tester.getCenter(handle);
    final to = tester.getCenter(ruleTile('Starkes Modell'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset(from.dx, from.dy + (to.dy - 20 - from.dy) * i / 10),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await settle(tester);

    expect((await stored(env)).rules.map((r) => r.id), [
      'notizen',
      'stark',
      'privat',
      'offline',
    ]);
    expect(find.text('Regel 1'), findsOneWidget);
    expect(find.text('greift → Claude API · Sonnet'), findsOneWidget);
    expect(tileOf(tester, 'Notizen umschreiben').active, isTrue);
    expect(tileOf(tester, 'Starkes Modell').active, isFalse);
  });

  testWidgets('Regel anlegen', (tester) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    await tester.tap(find.text('+ Regel hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditorScreen), findsOneWidget);
    // Ohne Name und Wort: nicht speicherbar.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed,
      isNull,
    );
    expect(find.text('Bitte einen Namen eingeben.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fable');
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Wörter am Satzanfang, durch Komma getrennt',
      ),
      'Fable, Opus',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await settle(tester);

    expect(find.byType(RoutingScreen), findsOneWidget);
    final rule = (await stored(env)).rules.last;
    expect(rule.name, 'Fable');
    expect(rule.condition, PrefixCondition(['Fable', 'Opus']));
    expect(
      rule.target,
      const RouteTarget(profileId: 'phala', modelId: 'GLM klein'),
    );
    expect(rule.enabled, isTrue);
    expect(ruleTile('Fable'), findsOneWidget);
  });

  testWidgets('Regel bearbeiten: Name, Ziel, Bedingung mit Gruppe und nicht', (
    tester,
  ) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    await tester.tap(ruleTile('Offline'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ohne Netz');
    // Ziel: Claude API, Modell anpassen.
    await tester.tap(find.text('Ollama Homeserver · lokal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude API · Standard').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Modell'), 'haiku');
    // Gruppe mit „nicht Bild“ ergänzen.
    await tester.tap(find.text('+ Gruppe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schlüsselwort').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mit Bild').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'nicht').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await settle(tester);

    final rule = (await stored(env)).rules.firstWhere((r) => r.id == 'offline');
    expect(rule.name, 'Ohne Netz');
    expect(
      rule.target,
      const RouteTarget(profileId: 'claude', modelId: 'haiku'),
    );
    expect(
      rule.condition,
      AndCondition([
        const NetworkCondition(NetworkState.offline),
        const NotCondition(HasImageCondition()),
      ]),
    );
  });

  testWidgets('Regel löschen (mit Rückfrage)', (tester) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    await tester.tap(ruleTile('Privat'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Regel löschen'));
    await tester.tap(find.text('Regel löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await stored(env)).rules, hasLength(4));
    await tester.tap(find.text('Regel löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await settle(tester);
    expect((await stored(env)).rules.map((r) => r.id), [
      'stark',
      'offline',
      'notizen',
    ]);
    expect(ruleTile('Privat'), findsNothing);
  });

  testWidgets('Warnungen: gelöschtes Profil, schwaches Privat-Ziel, Regex', (
    tester,
  ) async {
    final base = designRules();
    final env = await routingEnv(
      rules: base.copyWith(
        rules: [
          ...base.rules,
          RoutingRule(
            id: 'weg',
            name: 'Alt',
            condition: KeywordCondition(['alt']),
            target: const RouteTarget(profileId: 'geloescht', modelId: 'm'),
          ),
          RoutingRule(
            id: 'schwach',
            name: 'Geheim',
            condition: PrivacyCondition(['geheim']),
            target: const RouteTarget(profileId: 'claude', modelId: 'Sonnet'),
          ),
          RoutingRule(
            id: 'regex',
            name: 'Muster',
            condition: RegexCondition('(a+)+'),
            target: const RouteTarget(profileId: 'claude', modelId: 'Sonnet'),
          ),
        ],
      ),
    );
    await pumpRouting(tester, env);
    expect(
      find.textContaining('Regel „Alt“: Das Zielprofil gibt es nicht mehr'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Regel „Geheim“ ist privat, aber „Claude API“'),
      findsOneWidget,
    );
    expect(find.textContaining('Regel „Muster“ ist ungültig'), findsOneWidget);
    expect(tileOf(tester, 'Alt').target, 'geloescht (gelöscht)');

    // Im Editor live: Regex reparieren lässt die Warnung verschwinden.
    await tester.tap(ruleTile('Muster'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ist ungültig'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Muster (auf normalisiertem Text)'),
      r'\bdenk\b',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ist ungültig'), findsNothing);
  });

  testWidgets('Import: Vorschau, Abbrechen ändert nichts, Ersetzen schon', (
    tester,
  ) async {
    final imported = RuleSet(
      rules: [
        RoutingRule(
          id: 'neu',
          name: 'Nur Neues',
          condition: KeywordCondition(['neu']),
          target: const RouteTarget(profileId: 'ollama', modelId: 'qwen'),
        ),
      ],
      defaultTarget: const RouteTarget(profileId: 'fremd', modelId: 'x'),
    );
    var calls = 0;
    final env = await routingEnv(
      importer: () async {
        calls++;
        return jsonEncode(RuleSetJson().encode(imported));
      },
    );
    await pumpRouting(tester, env);
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(find.text('Regeln importieren?'), findsOneWidget);
    expect(
      find.textContaining('1 Regeln ersetzen die bisherigen 4'),
      findsOneWidget,
    );
    expect(find.text('1. Nur Neues'), findsOneWidget);
    expect(
      find.textContaining('„fremd“ gibt es hier nicht; der bisherige Standard'),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(await stored(env), designRules());

    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ersetzen'));
    await settle(tester);
    final now = await stored(env);
    expect(now.rules.single.id, 'neu');
    expect(now.defaultTarget.profileId, 'phala', reason: 'Standard bleibt');
    expect(calls, 2);
    expect(ruleTile('Nur Neues'), findsOneWidget);
  });

  testWidgets('Import eines alten Exports: Ketten werden übersprungen, mit '
      'Hinweis (K28)', (tester) async {
    final old = {
      ...RuleSetJson().encode(designRules()),
      'chains': {
        'phala': [
          {'profileId': 'claude', 'modelId': 'Sonnet'},
        ],
        'claude': <Object?>[],
      },
    };
    final env = await routingEnv(importer: () async => jsonEncode(old));
    await pumpRouting(tester, env);
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(find.text('Regeln importieren?'), findsOneWidget);
    expect(
      find.textContaining('Die Datei enthält Eskalationsketten. Sie wurden '),
      findsOneWidget,
    );
    await tester.tap(find.text('Ersetzen'));
    await settle(tester);
    expect(await stored(env), designRules());
    expect(
      RuleSetJson().encode(await stored(env)).containsKey('chains'),
      isFalse,
    );
  });

  testWidgets('Import: kaputte Datei zeigt den Fehler mit Pfad', (
    tester,
  ) async {
    final env = await routingEnv(
      importer: () async => '{"schemaVersion": 1, "rules": [{"id": "x"}]}',
    );
    await pumpRouting(tester, env);
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'$.rules[0].name: fehlt'), findsOneWidget);
    expect(find.text('Regeln importieren?'), findsNothing);
    expect(await stored(env), designRules());
  });

  testWidgets('Import: Dateifehler als Hinweis', (tester) async {
    final env = await routingEnv(
      importer: () async => throw const PortException(
        PortErrorKind.unsupported,
        'Auf diesem Gerät gibt es keine Dateiauswahl.',
      ),
    );
    await pumpRouting(tester, env);
    await tester.tap(find.text('Importieren'));
    await tester.pumpAndSettle();
    expect(
      find.text('Auf diesem Gerät gibt es keine Dateiauswahl.'),
      findsOneWidget,
    );
  });

  testWidgets('Export: JSON ohne Secrets über den Teilen-Dialog', (
    tester,
  ) async {
    final log = ExportLog();
    final env = await routingEnv(exports: log);
    await env.secrets.write('provider.claude.apiKey', 'sk-ant-geheim');
    await pumpRouting(tester, env);
    await tester.tap(find.text('Exportieren'));
    await settle(tester);
    final (name, mime, content) = log.files.single;
    expect(name, 'wendelin-routing.json');
    expect(mime, 'application/json');
    expect(RuleSetJson().decode(jsonDecode(content)), designRules());
    expect(content, isNot(contains('sk-ant')));
    expect(content, isNot(contains('apiKey')));
  });

  testWidgets('Standardziel ändern setzt auch das Standardprofil', (
    tester,
  ) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    await tester.tap(ruleTile('Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phala GLM · TEE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama Homeserver · lokal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await settle(tester);
    expect(
      (await stored(env)).defaultTarget,
      const RouteTarget(profileId: 'ollama', modelId: 'qwen'),
    );
    expect((await env.storage.providerProfiles.defaultProfile())!.id, 'ollama');
  });

  testWidgets('keine Eskalationsketten mehr: weder Karte noch Seite (K28)', (
    tester,
  ) async {
    final env = await routingEnv();
    await pumpRouting(tester, env);
    expect(find.text('Eskalation bei Fehlschlag'), findsNothing);
    expect(find.textContaining('Eskalationsketten'), findsNothing);
    expect(find.textContaining('Kette'), findsNothing);
  });

  testWidgets('tiefer verschachtelte Bedingung aus Import bleibt erhalten', (
    tester,
  ) async {
    final deep = AndCondition([
      OrCondition([
        AndCondition([
          KeywordCondition(['a']),
          KeywordCondition(['b']),
        ]),
        KeywordCondition(['c']),
      ]),
      const HasImageCondition(),
    ]);
    final base = designRules();
    final env = await routingEnv(
      rules: base.copyWith(
        rules: [
          RoutingRule(
            id: 'tief',
            name: 'Tief',
            condition: deep,
            target: const RouteTarget(profileId: 'claude', modelId: 'Opus'),
          ),
        ],
      ),
    );
    await pumpRouting(tester, env);
    await tester.tap(ruleTile('Tief'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tiefer verschachtelt'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Tiefer');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await settle(tester);
    final rule = (await stored(env)).rules.single;
    expect(rule.name, 'Tiefer');
    expect(rule.condition, deep);
  });

  test('editableTree: Tiefe 2, nicht und zurück', () {
    final c = OrCondition([
      KeywordCondition(['x']),
      NotCondition(
        AndCondition([
          const HasImageCondition(),
          PrefixCondition(['y']),
        ]),
      ),
    ]);
    final tree = editableTree(c)!;
    expect(tree.any, isTrue);
    expect(tree.children[1], isA<GroupNode>());
    expect(tree.children[1].negated, isTrue);
    expect(tree.build(AppLocalizationsDe()), (c, null));
    expect(
      editableTree(const NotCondition(NotCondition(HasImageCondition()))),
      isNull,
    );
    // Ein einzelnes Blatt bleibt ein Blatt.
    expect(
      editableTree(KeywordCondition(['z']))!.build(AppLocalizationsDe()).$1,
      KeywordCondition(['z']),
    );
    // Alle Typen überleben die Hin- und Rückrichtung.
    for (final leaf in <Condition>[
      RegexCondition(r'\bx\b'),
      LanguageCondition(['de', 'fr']),
      const SttConfidenceCondition(0.6),
      const InputLengthCondition(280),
      const NeedsToolCondition('obsidian.edit'),
      TimeWindowCondition(days: {1, 5}, start: 22 * 60, end: 6 * 60),
      PrivacyCondition(),
      const NetworkCondition(NetworkState.metered),
    ]) {
      expect(
        editableTree(leaf)!.build(AppLocalizationsDe()).$1,
        leaf,
        reason: leaf.type,
      );
    }
    final bad = LeafNode(type: 'sttConfidence', text: '2');
    expect(bad.build(AppLocalizationsDe()).$2, contains('zwischen 0 und 1'));
    expect(
      LeafNode(
        type: 'timeWindow',
        start: '25:00',
      ).build(AppLocalizationsDe()).$2,
      isNotNull,
    );
    expect(GroupNode().build(AppLocalizationsDe()).$2, 'Eine Gruppe ist leer.');
  });

  test('Bedingungstyp Sprache: Beschriftung folgt der UI-Sprache', () {
    expect(conditionTypeLabel(AppLocalizationsEn(), 'language'), 'Language');
    expect(conditionTypeLabel(AppLocalizationsDe(), 'language'), 'Sprache');
  });

  testWidgets('Touch-Ziele ≥ 44 und Semantics-Labels', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRouting(tester, await routingEnv(), size: screenSize);
    expect(
      find.bySemanticsLabel('Regel „Starkes Modell“ verschieben'),
      findsOneWidget,
    );
    final grip = find.ancestor(
      of: find.bySemanticsLabel('Regel „Privat“ verschieben'),
      matching: find.byType(ReorderableDragStartListener),
    );
    final size = tester.getSize(grip.first);
    expect(size.width, greaterThanOrEqualTo(WSize.touchMin));
    expect(size.height, greaterThanOrEqualTo(WSize.touchMin));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('Golden Routing (390 × 844)', tags: ['golden'], (tester) async {
    await pumpRouting(tester, await routingEnv(), size: screenSize);
    // Ohne Fokus gesetzt: wie im Entwurf ist der Satzanfang sichtbar.
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'Claude, denk gründlich über meinen Wochenplan nach';
    await tester.pumpAndSettle();
    expect(find.text('Regel 1'), findsOneWidget);
    await expectLater(
      find.byType(RoutingScreen),
      matchesGoldenFile('goldens/routing.png'),
    );
  });
}
