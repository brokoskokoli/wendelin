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
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin/ui/settings/lists_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin/ui/settings/web_search_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart'
    show ListDefinition;
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/saf_list_file_port_test.dart' show FakeSafNative;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

const _files = MethodChannel(filesChannelName);

Future<ProviderContainer> pumpHome(
  WidgetTester tester,
  TestEnv env,
  Widget home,
) async {
  setView(tester, const Size(390, 1600));
  await tester.pumpWidget(env.app(home: home));
  await settle(tester);
  final c = ProviderScope.containerOf(
    tester.element(find.byWidget(home, skipOffstage: false)),
  );
  await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
  await tester.pumpAndSettle();
  return c;
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Zurück'));
  await settle(tester);
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

  group('Daten werden beim erneuten Öffnen neu gelesen', () {
    testWidgets('Gedächtnis, Protokoll, Kosten', (tester) async {
      final env = TestEnv(
        storedProfiles: true,
        llmFactory: (_, _) => throw UnimplementedError(),
      );
      await env.storage.providerProfiles.save(
        ProviderProfile(
          id: 'a',
          name: 'Profil a',
          type: ProviderType.anthropic,
          defaultModel: 'm',
          privacy: PrivacyLevel.standard,
          authMethod: const NoAuth(),
        ),
      );
      await pumpHome(tester, env, const SettingsScreen());

      Future<void> open(String area) async {
        await tester.tap(find.text(area));
        await settle(tester);
      }

      await open('Gedächtnis');
      expect(find.text('Noch keine Einträge.'), findsOneWidget);
      await back(tester);
      await open('Datenschutz und Logs');
      expect(find.text('Keine Einträge.'), findsOneWidget);
      await back(tester);
      await open('Kosten');
      expect(find.textContaining('heute 0,00'), findsOneWidget);
      await back(tester);

      await tester.runAsync(() async {
        await env.storage.memory.save(
          'Neu gemerkt',
          category: StoredMemoryCategory.fact,
          source: 'user',
        );
        await env.storage.audit.record(
          AuditEntry(
            at: testNow,
            kind: AuditKind.request,
            payload: const {'text': 'Neue Anfrage'},
          ),
        );
        await env.storage.usage.record(
          sessionId: 's',
          profileId: 'a',
          modelId: 'm',
          usage: Usage.zero,
          costMicros: 30000,
        );
      });

      await open('Gedächtnis');
      expect(find.text('Neu gemerkt'), findsOneWidget);
      await back(tester);
      await open('Datenschutz und Logs');
      expect(find.text('Neue Anfrage'), findsOneWidget);
      await back(tester);
      await open('Kosten');
      expect(find.textContaining('heute 0,03'), findsOneWidget);
    });
  });

  group('Listen-Dateien', () {
    final list = ListDefinition(
      id: 'l1',
      name: 'Einkaufen',
      target: 'content://vault/Einkaufen.md',
    );

    testWidgets('beim Start: verlorene Rechte → Integration „Datei neu '
        'auswählen“, Liste markiert; neue Wahl behebt es', (tester) async {
      native.docs[list.target] = Uint8List(0);
      native.revoked.add(list.target);
      final env = TestEnv(
        enabled: const {'lists'},
        startup: StartupSettings(lists: [list], enabledIntegrations: {'lists'}),
      );
      final c = await pumpHome(tester, env, const MainScreen());
      await settle(tester);
      final registry = c.read(toolRegistryProvider);
      expect(registry.status('lists'), IntegrationStatus.error);
      expect(registry.info('lists').error, 'Datei neu auswählen: Einkaufen');

      await tester.pumpWidget(env.app(home: const ListsScreen()));
      await settle(tester);
      expect(
        find.text('Kein Zugriff mehr – Datei neu auswählen'),
        findsOneWidget,
      );

      native.docs['content://vault/Neu.md'] = Uint8List(0);
      native.nextPick = 'content://vault/Neu.md';
      await tester.tap(find.text('Einkaufen'));
      await settle(tester);
      await tester.tap(find.text('Datei wählen'));
      await settle(tester);
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      final now = ProviderScope.containerOf(
        tester.element(find.byType(ListsScreen)),
      ).read(toolRegistryProvider);
      expect(now.info('lists').error, isNull);
      expect(
        find.text('Kein Zugriff mehr – Datei neu auswählen'),
        findsNothing,
      );
      expect(native.released, [list.target], reason: 'alte Datei freigegeben');
    });

    testWidgets('Dateiwechsel und Verwerfen geben ungenutzte Rechte frei', (
      tester,
    ) async {
      final env = TestEnv(startup: StartupSettings(lists: [list]));
      native.docs[list.target] = Uint8List(0);
      await pumpHome(tester, env, const ListEditScreen());
      await tester.enterText(
        find.widgetWithText(TextField, 'Name, z. B. Einkaufen'),
        'Neu',
      );
      for (final uri in ['content://a', 'content://b']) {
        native.docs[uri] = Uint8List(0);
        native.nextPick = uri;
        await tester.tap(find.text('Datei wählen'));
        await settle(tester);
      }
      expect(native.released, ['content://a'], reason: 'erste Wahl ersetzt');
      // Eine bereits benutzte Datei wird nie freigegeben.
      native.nextPick = list.target;
      await tester.tap(find.text('Datei wählen'));
      await settle(tester);
      expect(native.released, ['content://a', 'content://b']);
      native.nextPick = 'content://c';
      native.docs['content://c'] = Uint8List(0);
      await tester.tap(find.text('Datei wählen'));
      await settle(tester);
      expect(native.released, ['content://a', 'content://b']);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      expect(native.released, [
        'content://a',
        'content://b',
        'content://c',
      ], reason: 'verworfen ohne Speichern');
    });
  });

  testWidgets('Gedächtnis: Speichern bei leerem Text deaktiviert', (
    tester,
  ) async {
    final env = TestEnv();
    await env.storage.memory.save(
      'X',
      category: StoredMemoryCategory.fact,
      source: 'u',
    );
    await pumpHome(tester, env, const SettingsScreen());
    await tester.tap(find.text('Gedächtnis'));
    await settle(tester);
    await tester.tap(find.text('X'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Speichern'),
    );
    expect(save().onPressed, isNotNull);
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(save().onPressed, isNull);
    await tester.enterText(field, 'Y');
    await tester.pump();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('Suchdienst-Wechsel löscht den alten Key', (tester) async {
    final env = TestEnv(
      startup: const StartupSettings(
        webSearch: WebSearchConfig(WebSearchKind.brave),
      ),
    );
    await env.secrets.write(WebSearchKind.brave.secretRef, 'brave-key');
    await pumpHome(tester, env, const WebSearchScreen());
    await tester.tap(find.text('Tavily'));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('searchKey')), 'tvly-key');
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(await env.secrets.listKeys(), {WebSearchKind.tavily.secretRef});
  });

  testWidgets(
    '„sensibel“ je Integration umschaltbar, Standard der Integration',
    (tester) async {
      final env = TestEnv(enabled: const {'clipboard'});
      final c = await pumpHome(
        tester,
        env,
        const IntegrationDetailScreen('clipboard'),
      );
      final registry0 = c.read(toolRegistryProvider);
      expect(registry0.info('clipboard').integration.sensitive, isTrue);
      Finder sensitiveSwitch() => find.descendant(
        of: find.widgetWithText(InkWell, 'Sensibel'),
        matching: find.byType(WSwitch),
      );
      await tester.tap(sensitiveSwitch());
      await settle(tester);
      expect(c.read(toolPrefsProvider).sensitive, {'clipboard': false});
      final registry = c.read(toolRegistryProvider);
      await tester.runAsync(registry.refresh);
      expect(registry.info('clipboard').integration.sensitive, isFalse);
      expect(
        registry.status('clipboard'),
        IntegrationStatus.active,
        reason: 'Schalter bleibt',
      );
      registry.sensitiveMinimum = PrivacyLevel.tee;
      expect(
        registry
            .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
            .map((t) => t.name),
        contains('clipboard__read'),
      );

      await tester.tap(sensitiveSwitch());
      await settle(tester);
      expect(
        c.read(toolPrefsProvider).sensitive,
        isEmpty,
        reason: 'zurück zum Standard',
      );
      expect(
        (await env.storage.settings.get(AppSettings.toolPrefs))!.sensitive,
        isEmpty,
      );
    },
  );

  test('Web an, kein Suchdienst → nur web__fetch', () async {
    final env = TestEnv(enabled: const {'web'});
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.status('web'), IntegrationStatus.active);
    expect(
      registry
          .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
          .map((t) => t.name),
      ['web__fetch'],
    );
  });

  group('Aufbewahrung', () {
    test('Standard 30 Tage auf leerer Datenbank', () async {
      final s = await StartupSettings.load(
        openInMemoryStorage().settings,
        const [],
      );
      expect(s.retentionDays, 30);
    });

    test('Ändern löscht ältere Verläufe und Protokolle sofort', () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      final storage = env.storage;
      final old = await storage.conversations.startNew(DateTime(2026, 9, 1));
      await storage.conversations.append(
        old.id,
        Message.user('alt'),
        at: DateTime(2026, 9, 1),
      );
      final recent = await storage.conversations.startNew(DateTime.now());
      await storage.conversations.append(recent.id, Message.user('neu'));
      await c.read(retentionDaysProvider.notifier).set(7);
      expect((await storage.conversations.sessions()).map((s) => s.id), [
        recent.id,
      ]);
      expect(await storage.settings.get(AppSettings.retentionDays), 7);
    });
  });
}
