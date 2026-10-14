import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/settings/assistant_screen.dart';
import 'package:wendelin/ui/settings/audit_log_screen.dart';
import 'package:wendelin/ui/settings/costs_screen.dart';
import 'package:wendelin/ui/settings/export.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin/ui/settings/memory_screen.dart';
import 'package:wendelin/ui/settings/privacy_screen.dart';
import 'package:wendelin/ui/settings/providers_screen.dart';
import 'package:wendelin/ui/settings/routing/routing_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart' show WakeTemplates;

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

/// Records exports instead of opening the share sheet.
final class ExportLog {
  final files = <(String, String, String)>[];

  Future<void> call(String name, String mime, String content) async =>
      files.add((name, mime, content));
}

Future<ProviderContainer> pumpPage(
  WidgetTester tester,
  TestEnv env,
  Widget page,
) async {
  setView(tester, const Size(390, 1600));
  await tester.pumpWidget(env.app(home: page));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byWidget(page)));
}

/// Environment whose exports land in [log].
TestEnv exportingEnv(ExportLog log) =>
    TestEnv(extraOverrides: [exporterProvider.overrideWithValue(log.call)]);

ProviderProfile profile(String id, {int? budget}) => ProviderProfile(
  id: id,
  name: 'Profil $id',
  type: ProviderType.anthropic,
  defaultModel: 'claude-haiku-4-5',
  privacy: PrivacyLevel.standard,
  authMethod: const NoAuth(),
  budgetMonthly: budget,
);

void main() {
  testWidgets('Übersicht: alle Bereiche, Tippen öffnet die Seite', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const SettingsScreen());
    for (final (title, _, _) in SettingsScreen.areas) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('Integrationen'));
    await settle(tester);
    expect(find.byType(IntegrationsScreen), findsOneWidget);
  });

  testWidgets('Hauptmenü ohne Obsidian, Listen, Web-Suche, Gedächtnis', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const SettingsScreen());
    for (final name in ['Obsidian', 'Listen', 'Web-Suche', 'Gedächtnis']) {
      expect(find.text(name), findsNothing, reason: name);
    }
  });

  testWidgets('Integrationen führen zu Listen, Web, Obsidian, Gedächtnis', (
    tester,
  ) async {
    for (final (id, row) in [
      ('lists', 'Listen verwalten'),
      ('web', 'Suchdienst einrichten'),
      ('obsidian', 'Vault und Tagesnotizen'),
      ('memory', 'Gedächtnis ansehen'),
    ]) {
      await pumpPage(
        tester,
        TestEnv(enabled: {id}),
        IntegrationDetailScreen(id),
      );
      expect(find.text(row), findsOneWidget, reason: id);
    }
  });

  group('Provider', () {
    testWidgets('Profile, Standard wechseln, Link zum Routing, Löschen', (
      tester,
    ) async {
      final env = TestEnv(
        storedProfiles: true,
        llmFactory: (p, s) => FakeLlmProvider(const []),
      );
      for (final id in ['a', 'b']) {
        await env.storage.providerProfiles.save(profile(id, budget: 5000000));
      }
      await env.storage.providerProfiles.setDefault('a');
      final c = await pumpPage(tester, env, const ProvidersScreen());
      expect(find.text('Profil a'), findsWidgets);
      expect(
        find.textContaining('Budget 5,00 \$/Monat · Standard'),
        findsOneWidget,
      );

      // Keine Eskalationsketten mehr (K28); die Anbieterwahl steht im Routing.
      expect(find.textContaining('Eskalation'), findsNothing);
      expect(find.text('Anbieterwahl'), findsOneWidget);
      await tester.tap(find.text('Routing'));
      await settle(tester);
      expect(find.byType(RoutingScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(tester);

      await tester.tap(find.text('Als Standard'));
      await settle(tester);
      final state = await c.read(profilesProvider.future);
      expect(state.defaultId, 'b');

      await tester.tap(find.text('Löschen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await settle(tester);
      expect((await c.read(profilesProvider.future)).profiles, hasLength(1));
    });

    testWidgets('ohne Profile: Hinweis und „+ Provider“', (tester) async {
      await pumpPage(
        tester,
        TestEnv(storedProfiles: true),
        const ProvidersScreen(),
      );
      expect(find.text('Noch kein Provider eingerichtet.'), findsOneWidget);
      expect(find.text('+ Provider'), findsOneWidget);
    });
  });

  group('Gedächtnis', () {
    testWidgets('anzeigen, ändern, vergessen, exportieren', (tester) async {
      final exports = ExportLog();
      final env = exportingEnv(exports);
      await env.storage.memory.save(
        'Taucht gern im Mittelmeer',
        category: StoredMemoryCategory.preference,
        source: 'user',
      );
      await env.storage.memory.save(
        'Schwester heißt Anna',
        category: StoredMemoryCategory.person,
        source: 'user',
      );
      await pumpPage(tester, env, const MemoryScreen());
      expect(find.text('Taucht gern im Mittelmeer'), findsOneWidget);
      expect(find.text('Vorliebe'), findsOneWidget);

      await tester.tap(find.text('Taucht gern im Mittelmeer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Taucht gern in der Ostsee',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fakt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Taucht gern in der Ostsee'), findsOneWidget);
      final edited = (await env.storage.memory.list()).firstWhere(
        (e) => e.text.contains('Ostsee'),
      );
      expect(edited.category, StoredMemoryCategory.fact);

      await tester.tap(find.byTooltip('Löschen: Schwester heißt Anna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vergessen'));
      await settle(tester);
      expect(find.text('Schwester heißt Anna'), findsNothing);
      expect(await env.storage.memory.list(), hasLength(1));

      await tester.tap(find.text('Als Markdown exportieren'));
      await settle(tester);
      expect(exports.files.single.$1, 'wendelin-gedaechtnis.md');
      expect(exports.files.single.$3, contains('Ostsee'));
    });

    testWidgets('sensible Änderung wird abgewiesen', (tester) async {
      final env = TestEnv();
      await env.storage.memory.save(
        'Lieblingszahl',
        category: StoredMemoryCategory.fact,
        source: 'user',
      );
      await pumpPage(tester, env, const MemoryScreen());
      await tester.tap(find.text('Lieblingszahl'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Meine PIN: 4711',
      );
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.textContaining('nicht gespeichert'), findsOneWidget);
      expect((await env.storage.memory.list()).single.text, 'Lieblingszahl');
    });
  });

  group('Datenschutz und Logs', () {
    test('auditSummary: Rückgängig ist als solches erkennbar', () {
      AuditEntry tool(Map<String, Object?> p) =>
          AuditEntry(at: testNow, kind: AuditKind.toolCall, payload: p);
      expect(
        auditSummary(tool({'tool': 'calendar__create_event', 'status': 'ok'})),
        'calendar__create_event · ok',
      );
      expect(
        auditSummary(
          tool({
            'callId': 'c1',
            'tool': 'calendar__create_event',
            'undo': true,
            'status': 'ok',
          }),
        ),
        'calendar__create_event · rückgängig · ok',
      );
      expect(
        auditSummary(
          tool({
            'tool': 'calendar__create_event',
            'undo': true,
            'status': 'failed',
          }),
        ),
        'calendar__create_event · rückgängig · failed',
      );
    });

    Future<TestEnv> withAudit([ExportLog? log]) async {
      final env = log == null ? TestEnv() : exportingEnv(log);
      await env.storage.audit.record(
        AuditEntry(
          at: testNow,
          kind: AuditKind.request,
          sessionId: 's',
          payload: const {'text': 'Wie wird das Meer?'},
        ),
      );
      await env.storage.audit.record(
        AuditEntry(
          at: testNow,
          kind: AuditKind.toolCall,
          sessionId: 's',
          payload: const {'tool': 'calendar__create_event', 'status': 'ok'},
        ),
      );
      final s = await env.storage.conversations.startNew(testNow);
      await env.storage.conversations.append(s.id, Message.user('Hallo'));
      return env;
    }

    testWidgets('Prüfprotokoll nur hinter dem Button, Aufbewahrung', (
      tester,
    ) async {
      final env = await withAudit();
      final c = await pumpPage(tester, env, const PrivacyScreen());
      // WP65: nothing of the log inline, only status and the button.
      expect(find.text('Wie wird das Meer?'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Als JSON exportieren'), findsNothing);
      expect(find.text('2 Einträge'), findsOneWidget);
      expect(find.text('Prüfprotokoll ansehen'), findsOneWidget);

      await tester.tap(find.text('90 Tage'));
      await settle(tester);
      expect(c.read(retentionDaysProvider), 90);
      expect(await env.storage.settings.get(AppSettings.retentionDays), 90);
    });

    testWidgets('Prüfprotokoll-Seite: Filter und Export', (tester) async {
      final exports = ExportLog();
      final env = await withAudit(exports);
      await pumpPage(tester, env, const AuditLogScreen());
      expect(find.text('Wie wird das Meer?'), findsOneWidget);
      expect(find.text('calendar__create_event · ok'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tool'));
      await settle(tester);
      expect(find.text('Wie wird das Meer?'), findsNothing);
      expect(find.text('calendar__create_event · ok'), findsOneWidget);

      await tester.tap(find.text('Als JSON exportieren'));
      await settle(tester);
      expect(exports.files.single.$2, 'application/json');
      expect(exports.files.single.$3, contains('calendar__create_event'));
    });

    testWidgets('alles löschen nur nach Bestätigung', (tester) async {
      final env = await withAudit();
      await env.storage.attestations.add(_attestation(DateTime.now()));
      // WP60: eingelernte Stimmen gehören zu „Alles löschen“.
      final wake = SecretWakeTemplateStore(env.secrets);
      await wake.save(
        WakeTemplates(
          speakerId: 'a',
          featureVersion: 'v1',
          threshold: 0.9,
          embeddings: [Float32List(4)],
        ),
      );
      await wake.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
      await pumpPage(tester, env, const PrivacyScreen());
      await tester.tap(find.text('Verläufe und Protokoll löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(await wake.load('a'), isNotNull);
      expect(await env.storage.audit.query(), hasLength(2));
      expect(await env.storage.attestations.latest(), hasLength(1));

      await tester.tap(find.text('Verläufe und Protokoll löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alles löschen'));
      await settle(tester);
      expect(await env.storage.audit.query(), isEmpty);
      expect(await env.storage.attestations.latest(), isEmpty);
      expect(await env.storage.conversations.sessions(), isEmpty);
      expect(await wake.load('a'), isNull);
      expect(await wake.speakers(), isEmpty);
      expect(await env.secrets.listKeys(), isNot(contains('wake.speakers')));
    });

    test('purgeExpired löscht nur Älteres', () async {
      final env = TestEnv();
      await env.storage.audit.record(
        AuditEntry(at: DateTime(2020), kind: AuditKind.error),
      );
      await env.storage.audit.record(
        AuditEntry(at: DateTime.now(), kind: AuditKind.error),
      );
      await env.storage.attestations.add(_attestation(DateTime(2020), 'old'));
      await env.storage.attestations.add(_attestation(DateTime.now(), 'new'));
      await purgeExpired(env.storage, 30);
      expect(await env.storage.audit.query(), hasLength(1));
      expect(
        [for (final a in await env.storage.attestations.latest()) a.logId],
        ['new'],
      );
    });
  });

  testWidgets('Kosten: heute und Monat je Provider', (tester) async {
    final env = TestEnv(
      storedProfiles: true,
      llmFactory: (p, s) => FakeLlmProvider(const []),
    );
    await env.storage.providerProfiles.save(profile('a', budget: 5000000));
    Future<void> rec(DateTime at, int micros) => env.storage.usage.record(
      sessionId: 's',
      profileId: 'a',
      modelId: 'm',
      usage: Usage.zero,
      costMicros: micros,
      at: at,
    );
    await rec(DateTime(2026, 10, 2), 1000000);
    await rec(DateTime(2026, 10, 13, 7), 30000);
    await pumpPage(tester, env, const CostsScreen());
    expect(
      find.text('heute 0,03 \$ · Monat 1,03 \$ · von 5,00 \$'),
      findsOneWidget,
    );
  });

  testWidgets('Assistent: Name und Persönlichkeit gehen in die Agent-Konfig', (
    tester,
  ) async {
    final env = TestEnv();
    final c = await pumpPage(tester, env, const AssistantScreen());
    await tester.enterText(
      find.widgetWithText(TextField, 'Wie soll Wendelin dich nennen?'),
      'Stefan',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Persönlichkeit, z. B. „antworte knapp und locker“',
      ),
      'Antworte knapp.',
    );
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(
      c.read(assistantPrefsProvider),
      isA<AssistantPrefs>()
          .having((p) => p.userName, 'userName', 'Stefan')
          .having((p) => p.persona, 'persona', 'Antworte knapp.'),
    );
    expect(await env.storage.settings.get(AppSettings.userName), 'Stefan');
    final factory = c.read(agentFactoryProvider) as AgentFactory;
    expect(factory.config.userName, 'Stefan');
    expect(factory.config.personaAddon, 'Antworte knapp.');

    await c
        .read(assistantPrefsProvider.notifier)
        .set(const AssistantPrefs(userName: ' '));
    expect(await env.storage.settings.get(AppSettings.userName), isNull);
  });

  test('ToolPrefs: JSON und Änderungen', () {
    const p = ToolPrefs();
    final q = p
        .withEnabled('a__b', enabled: false)
        .withConfirm('a__c', confirm: true)
        .withSensitiveMinimum(PrivacyLevel.tee);
    final back = ToolPrefs.fromJson(q.toJson());
    expect(back.disabled, {'a__b'});
    expect(back.alwaysConfirm, {'a__c'});
    expect(back.sensitiveMinimum, PrivacyLevel.tee);
    expect(q.withEnabled('a__b', enabled: true).disabled, isEmpty);
    expect(q.withConfirm('a__c', confirm: false).alwaysConfirm, isEmpty);
    expect(ToolPrefs.fromJson({'disabled': 3}).disabled, isEmpty);
  });
}

AttestationRecord _attestation(DateTime at, [String id = 'l1']) =>
    AttestationRecord(
      logId: id,
      at: at,
      profileId: 'near',
      kind: AttestationRecordKind.receipt,
      status: AttestationStatus.green,
    );
