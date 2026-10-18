import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/saf_list_file_port.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/lists_screen.dart';
import 'package:wendelin/ui/settings/web_search_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../platform/saf_list_file_port_test.dart' show FakeSafNative;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

const _files = MethodChannel(filesChannelName);

Future<ProviderContainer> pumpPage(
  WidgetTester tester,
  TestEnv env,
  Widget page,
) async {
  setView(tester, const Size(390, 1400));
  await tester.pumpWidget(env.app(home: page));
  await settle(tester);
  final c = ProviderScope.containerOf(tester.element(find.byWidget(page)));
  await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
  await tester.pumpAndSettle();
  return c;
}

void main() {
  late FakeSafNative native;

  setUp(() {
    native = FakeSafNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, native.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, null),
  );

  group('Listen', () {
    testWidgets('Liste mit neuer Datei anlegen → lists__*-Tools aktiv', (
      tester,
    ) async {
      final env = TestEnv(enabled: const {});
      final c = await pumpPage(tester, env, const ListsScreen());
      final registry = c.read(toolRegistryProvider);
      expect(registry.status('lists'), IntegrationStatus.available);

      await tester.tap(find.text('+ Liste'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name, z. B. Einkaufen'),
        'Einkaufen',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Andere Namen, mit Komma getrennt (optional)',
        ),
        'Einkaufsliste, Supermarkt',
      );
      await tester.tap(find.text('Neue Datei'));
      await settle(tester);
      expect(find.text('Einkaufen.md'), findsOneWidget);
      await tester.tap(find.text('Speichern'));
      await settle(tester);

      final lists = c.read(listDefinitionsProvider);
      expect(lists.single.name, 'Einkaufen');
      expect(lists.single.aliases, ['Einkaufsliste', 'Supermarkt']);
      expect(lists.single.target, startsWith('content://test/document/'));
      expect(
        await env.storage.settings.get(AppSettings.lists),
        hasLength(1),
        reason: 'in den Einstellungen gespeichert',
      );
      final now = c.read(toolRegistryProvider);
      expect(now.status('lists'), IntegrationStatus.active);
      final tools = now
          .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
          .map((t) => t.name);
      expect(
        tools,
        containsAll([
          'lists__add_items',
          'lists__get_items',
          'lists__list_lists',
        ]),
      );
      expect(find.text('Einkaufen'), findsOneWidget, reason: 'in der Liste');
    });

    testWidgets('Datei wählen; ohne Datei kein Speichern; abgebrochene Wahl', (
      tester,
    ) async {
      final env = TestEnv();
      final c = await pumpPage(tester, env, const ListEditScreen());
      await tester.enterText(
        find.widgetWithText(TextField, 'Name, z. B. Einkaufen'),
        'SmartSSH',
      );
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Name und Datei sind nötig.'), findsOneWidget);

      native.nextPick = null;
      await tester.tap(find.text('Datei wählen'));
      await settle(tester);
      expect(find.text('Noch keine Datei'), findsOneWidget);

      native.docs['content://vault/SmartSSH.md'] = Uint8List(0);
      native.nextPick = 'content://vault/SmartSSH.md';
      await tester.tap(find.text('Datei wählen'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Abschnitt in der Datei, z. B. Todo (optional)',
        ),
        'Todo',
      );
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      final l = c.read(listDefinitionsProvider).single;
      expect(l.target, 'content://vault/SmartSSH.md');
      expect(l.section, 'Todo');
    });

    testWidgets('Standard-Aufgabenliste: höchstens eine', (tester) async {
      final a = ListDefinition(
        id: 'a',
        name: 'Aufgaben',
        target: 'content://vault/A.md',
        taskDefault: true,
      );
      final b = ListDefinition(
        id: 'b',
        name: 'Projekte',
        target: 'content://vault/B.md',
      );
      native.docs[a.target] = Uint8List(0);
      native.docs[b.target] = Uint8List(0);
      final env = TestEnv(startup: StartupSettings(lists: [a, b]));
      final c = await pumpPage(tester, env, const ListsScreen());
      await tester.tap(find.text('Projekte'));
      await settle(tester);
      await tester.tap(find.byType(WSwitch));
      await tester.pump();
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      final lists = {for (final l in c.read(listDefinitionsProvider)) l.id: l};
      expect(lists['b']!.taskDefault, isTrue);
      expect(lists['a']!.taskDefault, isFalse);
    });

    testWidgets('bearbeiten und löschen gibt die Datei frei', (tester) async {
      final list = ListDefinition(
        id: 'l1',
        name: 'Einkaufen',
        target: 'content://vault/Einkaufen.md',
      );
      native.docs[list.target] = Uint8List(0);
      final env = TestEnv(startup: StartupSettings(lists: [list]));
      final c = await pumpPage(tester, env, const ListsScreen());
      await tester.tap(find.text('Einkaufen'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Einkaufen'),
        'Einkauf',
      );
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(c.read(listDefinitionsProvider).single.name, 'Einkauf');
      expect(c.read(listDefinitionsProvider).single.id, 'l1');

      await tester.tap(find.text('Einkauf'));
      await settle(tester);
      await tester.tap(find.text('Liste löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await settle(tester);
      expect(c.read(listDefinitionsProvider), isEmpty);
      expect(native.released, [list.target]);
    });

    test('Listen-Definitionen: JSON hin und zurück, Fehler', () {
      final l = ListDefinition(
        id: 'a',
        name: 'Einkaufen',
        target: 'content://x',
        aliases: const ['E'],
        section: 'Todo',
        taskDefault: true,
      );
      final back = listDefinitionFromJson(listDefinitionToJson(l));
      expect(back.taskDefault, isTrue);
      expect(
        listDefinitionFromJson(
          listDefinitionToJson(ListDefinition(id: 'b', name: 'B', target: 't')),
        ).taskDefault,
        isFalse,
      );
      expect(back.id, 'a');
      expect(back.aliases, ['E']);
      expect(back.section, 'Todo');
      expect(() => listDefinitionFromJson({'id': 1}), throwsFormatException);
      expect(() => listDefinitionFromJson('x'), throwsFormatException);
    });
  });

  group('Web-Suche', () {
    testWidgets('Brave mit Key: Key nur im SecretStore, web__search aktiv', (
      tester,
    ) async {
      final env = TestEnv(enabled: const {'web'});
      final c = await pumpPage(tester, env, const WebSearchScreen());
      final before = c.read(toolRegistryProvider);
      expect(before.status('web'), IntegrationStatus.active);
      expect(
        before
            .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
            .map((t) => t.name),
        ['web__fetch'],
        reason: 'ohne Suchdienst nur Seiten lesen',
      );
      await tester.tap(find.text('Brave Search'));
      await settle(tester);
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Bitte den API-Key eingeben.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('searchKey')),
        'BSA-geheim-123',
      );
      await tester.tap(find.text('Speichern'));
      await settle(tester);

      expect(
        await env.secrets.read(WebSearchKind.brave.secretRef),
        'BSA-geheim-123',
      );
      final config = await env.storage.settings.get(AppSettings.webSearch);
      expect(config, const WebSearchConfig(WebSearchKind.brave));
      expect(config!.toJson().toString(), isNot(contains('geheim')));
      final registry = c.read(toolRegistryProvider);
      await tester.runAsync(registry.refresh);
      expect(registry.status('web'), IntegrationStatus.active);
      expect(
        registry
            .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
            .map((t) => t.name),
        containsAll(['web__search', 'web__fetch']),
      );
    });

    testWidgets('SearXNG braucht eine Adresse, keinen Key', (tester) async {
      final env = TestEnv();
      final c = await pumpPage(tester, env, const WebSearchScreen());
      await tester.tap(find.text('SearXNG (eigene Instanz)'));
      await settle(tester);
      expect(find.byKey(const ValueKey('searchKey')), findsNothing);
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(
        find.text('Bitte die Adresse der Instanz angeben.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'https://search.home.lan');
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(
        c.read(webSearchConfigProvider),
        const WebSearchConfig(
          WebSearchKind.searxng,
          baseUrl: 'https://search.home.lan',
        ),
      );
    });

    testWidgets('„Kein Suchdienst“ entfernt Dienst und Keys', (tester) async {
      final env = TestEnv(
        startup: const StartupSettings(
          webSearch: WebSearchConfig(WebSearchKind.tavily),
        ),
      );
      await env.secrets.write(WebSearchKind.tavily.secretRef, 'tvly-x');
      final c = await pumpPage(tester, env, const WebSearchScreen());
      expect(
        find.text('Key gespeichert – leer lassen behält ihn'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kein Suchdienst'));
      await settle(tester);
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(c.read(webSearchConfigProvider), isNull);
      expect(await env.secrets.listKeys(), isEmpty);
      expect(await env.storage.settings.get(AppSettings.webSearch), isNull);
    });

    test('Konfiguration: JSON hin und zurück, Fehler', () {
      const c = WebSearchConfig(WebSearchKind.searxng, baseUrl: 'https://s');
      expect(WebSearchConfig.fromJson(c.toJson()), c);
      expect(
        () => WebSearchConfig.fromJson({'kind': 'google'}),
        throwsFormatException,
      );
      expect(
        () => WebSearchConfig.fromJson({'kind': 'searxng', 'baseUrl': 3}),
        throwsFormatException,
      );
    });
  });
}
