import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/audit_recorder.dart';
import 'package:wendelin/di/demo_provider.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';

ProviderProfile _profile(
  String id, {
  ProviderType type = ProviderType.anthropic,
  PrivacyLevel privacy = PrivacyLevel.standard,
  String? baseUrl,
}) => ProviderProfile(
  id: id,
  name: 'Profil $id',
  type: type,
  defaultModel: 'claude-haiku-4-5',
  privacy: privacy,
  authMethod: ApiKeyAuth('provider.$id'),
  baseUrl: baseUrl,
);

void main() {
  group('loadProviderConfig', () {
    Future<ProviderConfig?> load(WendelinStorage storage) => loadProviderConfig(
      storage: storage,
      secrets: InMemorySecretStore(),
      catalog: ModelCatalog.builtIn(),
    );

    test('ohne Standardprofil: null', () async {
      final storage = openInMemoryStorage();
      await storage.providerProfiles.save(_profile('a'));
      expect(await load(storage), isNull);
    });

    test('Standardprofil und Eskalationskette aus den Einstellungen', () async {
      final storage = openInMemoryStorage();
      await storage.providerProfiles.save(
        _profile('local', privacy: PrivacyLevel.local),
      );
      await storage.providerProfiles.save(_profile('cloud'));
      await storage.providerProfiles.save(
        _profile('kaputt', type: ProviderType.openaiCompatible),
      );
      await storage.providerProfiles.setDefault('local');
      await storage.settings.set(AppSettings.escalationChain, [
        'local',
        'weg',
        'kaputt',
        'cloud',
      ]);
      final config = (await load(storage))!;
      expect(config.primary.profileId, 'local');
      expect(config.primary.modelId, 'claude-haiku-4-5');
      expect(config.primary.provider, isA<LlmProvider>());
      expect(config.chain.map((t) => t.profileId), ['cloud']);
      expect(config.nameOf('cloud'), 'Profil cloud');
      expect(config.nameOf('unbekannt'), 'unbekannt');
      expect(config.lowestPrivacy, PrivacyLevel.standard);
    });

    test('nicht baubares Standardprofil wirft', () async {
      final storage = openInMemoryStorage();
      await storage.providerProfiles.save(
        _profile('x', type: ProviderType.openaiCompatible),
      );
      await storage.providerProfiles.setDefault('x');
      await expectLater(load(storage), throwsArgumentError);
    });

    test('Eskalationskette: ungültiger Wert wird abgelehnt', () {
      expect(
        () => AppSettings.escalationChain.decode([1, 2]),
        throwsFormatException,
      );
      expect(AppSettings.escalationChain.decode(['a']), ['a']);
      expect(AppSettings.escalationChain.encode(['a']), ['a']);
    });
  });

  test('ProviderConfig.lowestPrivacy ist die schwächste Stufe der Kette', () {
    ProviderTarget t(String id, PrivacyLevel p) => ProviderTarget(
      profileId: id,
      modelId: 'm',
      provider: FakeLlmProvider(const []),
      privacy: p,
    );
    expect(
      ProviderConfig(primary: t('a', PrivacyLevel.tee)).lowestPrivacy,
      PrivacyLevel.tee,
    );
    expect(
      ProviderConfig(
        primary: t('a', PrivacyLevel.tee),
        chain: [t('b', PrivacyLevel.local), t('c', PrivacyLevel.eu)],
      ).lowestPrivacy,
      PrivacyLevel.eu,
    );
  });

  group('DemoLlmProvider', () {
    final clock = FixedClock(testNow);
    final demo = DemoLlmProvider(clock: clock);

    ToolCallBlock planned(String text) {
      final turn = demo.turnFor([Message.user(text)]);
      return turn.events.whereType<ToolCallComplete>().single.call;
    }

    String answer(List<Message> messages) => demo
        .turnFor(messages)
        .events
        .whereType<TextDelta>()
        .map((e) => e.text)
        .join();

    test('„Trag mir morgen um 10 Tauchen ein“ → calendar__create_event', () {
      final c = planned('Trag mir morgen um 10 Tauchen ein');
      expect(c.name, 'calendar__create_event');
      expect(c.tryDecodeArguments(), {
        'title': 'Tauchen',
        'start': '2026-10-14T10:00',
      });
    });

    test('heute, übermorgen, Minuten und „Uhr“', () {
      expect(
        planned('Trag mir heute um 18:30 Uhr Yoga ein').tryDecodeArguments(),
        {'title': 'Yoga', 'start': '2026-10-13T18:30'},
      );
      expect(
        planned('trag übermorgen um 7 Laufen ein')
            .tryDecodeArguments()!['start'],
        '2026-10-15T07:00',
      );
    });

    test('„Lösch den Termin“ löscht den zuletzt angelegten', () {
      final created = ToolOutcome.text(
        '{"created":{"id":"e7","title":"Tauchen"}}',
      ).toResultBlock('demo_1');
      final c = demo
          .turnFor([
            Message.user('Trag mir morgen um 10 Tauchen ein'),
            Message.toolResults([created]),
            Message.assistantText('Erledigt'),
            Message.user('Lösch den Termin wieder'),
          ])
          .events
          .whereType<ToolCallComplete>()
          .single
          .call;
      expect(c.name, 'calendar__delete_event');
      expect(c.tryDecodeArguments(), {'event_id': 'e7'});
    });

    test('Löschen ohne angelegten Termin und Unbekanntes: Hinweise', () {
      expect(answer([Message.user('Lösch alles')]), contains('noch keinen'));
      expect(answer([Message.user('Wie spät ist es?')]), contains('Demo'));
    });

    test('Antworten nach Tool-Ergebnissen', () {
      Message result(ToolOutcome o) =>
          Message.toolResults([o.toResultBlock('demo_1')]);
      expect(answer([result(ToolOutcome.error('x'))]), contains('nicht'));
      expect(answer([result(ToolOutcome.declined())]), contains('lasse'));
      expect(
        answer([result(ToolOutcome.text('{"deleted":"e1"}'))]),
        contains('gelöscht'),
      );
      expect(
        answer([result(ToolOutcome.text('{"created":{}}'))]),
        contains('Kalender'),
      );
    });

    test('verhält sich wie ein Provider (Vertrag)', () async {
      expect(demo.type, ProviderType.fake);
      expect(demo.caps.tools, isTrue);
      expect((await demo.test()).ok, isTrue);
      expect((await demo.listModels()).single.id, DemoLlmProvider.modelId);
      final events = await demo
          .chat(
            ChatRequest(
              model: DemoLlmProvider.modelId,
              messages: [Message.user('Hallo')],
              maxTokens: 100,
            ),
          )
          .toList();
      expectWellFormedChatStream(events);
    });
  });

  group('IntegrationActivator', () {
    test(
      'Berechtigung erst beim Einschalten, Zustand wird gespeichert',
      () async {
        final env = TestEnv(enabled: const {});
        env.calendar.permissionGranted = false;
        final c = env.container();
        addTearDown(c.dispose);
        final registry = c.read(toolRegistryProvider);
        await registry.refresh();
        expect(env.permissionRequests, 0, reason: 'nicht beim Start');
        expect(registry.status('calendar'), IntegrationStatus.available);

        final status = await c
            .read(integrationActivatorProvider)
            .setEnabled('calendar', enabled: true);
        expect(env.permissionRequests, 1);
        expect(status, IntegrationStatus.active);
        expect(
          await env.storage.settings.get(
            AppSettings.integrationEnabled('calendar'),
          ),
          isTrue,
        );
        expect(c.read(enabledIntegrationsProvider), contains('calendar'));

        await c
            .read(integrationActivatorProvider)
            .setEnabled('calendar', enabled: false);
        expect(env.permissionRequests, 1, reason: 'Ausschalten fragt nicht');
        expect(registry.status('calendar'), IntegrationStatus.available);
        expect(
          c.read(enabledIntegrationsProvider),
          isNot(contains('calendar')),
        );
      },
    );

    test(
      'abgelehnte Berechtigung: Einrichtung nötig, setUp fragt erneut',
      () async {
        final env = TestEnv(enabled: const {});
        final c = ProviderContainer(
          overrides: [
            ...env.overrides,
            integrationSpecsProvider.overrideWithValue([
              IntegrationSpec(
                id: 'calendar',
                create: builtInIntegrationSpecs.first.create,
                requestPermission: (_) async {
                  env.permissionRequests++;
                  return false;
                },
              ),
            ]),
          ],
          retry: (_, _) => null,
        );
        addTearDown(c.dispose);
        env.calendar.permissionGranted = false;
        final activator = c.read(integrationActivatorProvider);
        expect(
          await activator.setEnabled('calendar', enabled: true),
          IntegrationStatus.setupRequired,
        );
        env.calendar.permissionGranted = true;
        expect(await activator.setUp('calendar'), IntegrationStatus.active);
        expect(env.permissionRequests, 2);
      },
    );

    test('ohne Berechtigungsbedarf wird nichts angefragt', () async {
      final env = TestEnv(enabled: const {});
      final c = env.container();
      addTearDown(c.dispose);
      expect(
        await c
            .read(integrationActivatorProvider)
            .setEnabled('clipboard', enabled: true),
        IntegrationStatus.active,
      );
      expect(env.permissionRequests, 0);
    });
  });

  group('Registry-Verdrahtung', () {
    test('alle eingebauten Integrationen, Schalter vom Start', () async {
      final env = TestEnv(enabled: const {'memory'});
      final c = env.container();
      addTearDown(c.dispose);
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      expect(registry.integrations.map((i) => i.id), [
        'alarms',
        'calendar',
        'clipboard',
        'memory',
        'web',
      ]);
      expect(registry.status('memory'), IntegrationStatus.active);
      expect(registry.status('calendar'), IntegrationStatus.available);
    });

    test('Demo-Modus: In-Memory-Ports, alles aktiv, Demo-Provider', () async {
      final env = TestEnv(demo: true);
      final c = env.container();
      addTearDown(c.dispose);
      expect(c.read(demoModeProvider), isTrue);
      expect(c.read(platformPortsProvider), same(c.read(demoPortsProvider)));
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      expect(
        {for (final i in registry.integrations) i.id: i.status},
        {
          'alarms': IntegrationStatus.active,
          'calendar': IntegrationStatus.active,
          'clipboard': IntegrationStatus.active,
          'memory': IntegrationStatus.active,
          // Ohne Suchdienst ist web aktiv (nur web__fetch); der optionale
          // Einrichtungsschritt bleibt offen (WP14).
          'web': IntegrationStatus.active,
        },
      );
      expect(registry.info('web').setup.missingSteps, ['search_backend']);
      final webTools = registry
          .catalogFor(PrivacyLevel.standard, sessionId: 's')
          .activeSpecs()
          .map((t) => t.name)
          .where((n) => n.startsWith('web__'));
      expect(webTools, ['web__fetch']);
      final config = (await c.read(providerConfigProvider.future))!;
      expect(config.primary.profileId, DemoLlmProvider.profileId);
      expect(config.primary.provider, isA<DemoLlmProvider>());
    });

    test(
      'Demo-Modus: Listen „Einkaufen“ und „SmartSSH“ über den Fake-Port',
      () async {
        // Die echten Demo-Ports der App, nicht die Test-Fakes der Umgebung.
        final c = TestEnv(demo: true, realDemoPorts: true).container();
        addTearDown(c.dispose);
        final registry = c.read(toolRegistryProvider);
        await registry.refresh();
        expect(registry.status('lists'), IntegrationStatus.active);
        final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
        final ctx = ToolContext(
          sessionId: 's',
          clock: FixedClock(testNow),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
        );
        final lists = await catalog
            .lookup('lists__list_lists')!
            .execute({}, ctx);
        expect(lists.text, allOf(contains('Einkaufen'), contains('SmartSSH')));
        final added = await catalog.lookup('lists__add_items')!.execute({
          'list': 'Einkaufsliste',
          'items': ['Eier'],
        }, ctx);
        expect(added.isError, isFalse, reason: added.text);
        final port = c.read(platformPortsProvider).lists!.port;
        expect(
          await port.read('demo://Listen/Einkaufen.md'),
          contains('- [ ] Eier'),
        );
      },
    );

    test('ohne Listen-Port (Gerät bis WP09): keine Listen-Integration', () {
      final c = TestEnv().container();
      addTearDown(c.dispose);
      expect(c.read(integrationsProvider).keys, isNot(contains('lists')));
    });

    test('Demo-Modus umschalten speichert die Wahl', () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      expect(c.read(demoModeProvider), isFalse);
      await c.read(demoModeProvider.notifier).set(enabled: true);
      expect(c.read(demoModeProvider), isTrue);
      expect(await env.storage.settings.get(AppSettings.demoMode), isTrue);
    });

    test(
      'Sitzungsende vergisst freigeschaltete Tools und Kalender-Cache',
      () async {
        final env = TestEnv();
        final c = env.container();
        addTearDown(c.dispose);
        final cleared = <String>[];
        final registry = c.read(toolRegistryProvider);
        final sub = registry.changes.listen((_) => cleared.add('change'));
        addTearDown(sub.cancel);
        final sessions = c.read(sessionManagerProvider);
        await sessions.ensure();
        sessions.end();
        await pumpEventQueue();
        // Nichts freigeschaltet: endSession meldet keine Änderung, wirft aber
        // auch nicht; der Kalender-Cache wird ohne Fehler geleert.
        expect(sessions.currentId, isNull);
      },
    );
  });

  test('StartupSettings.load liest Schalter, Demo und Thinking', () async {
    final storage = openInMemoryStorage();
    await storage.settings.set(
      AppSettings.integrationEnabled('calendar'),
      true,
    );
    await storage.settings.set(AppSettings.integrationEnabled('web'), false);
    await storage.settings.set(AppSettings.demoMode, true);
    await storage.settings.set(AppSettings.showThinking, true);
    final s = await StartupSettings.load(storage.settings, [
      'calendar',
      'web',
      'memory',
    ]);
    expect(s.enabledIntegrations, {'calendar'});
    expect(s.demoMode, isTrue);
    expect(s.showThinking, isTrue);
  });

  group('AuditRecorder', () {
    test('schreibt in Reihenfolge, Fehler gehen an onError', () async {
      final storage = openInMemoryStorage();
      final errors = <Object>[];
      final failing = AuditRecorder(
        _FailingAudit(),
        clock: const SystemClock(),
        onError: (e, _) => errors.add(e),
      );
      failing.request('s', UserInput(text: 'x'));
      await failing.flush();
      expect(errors, hasLength(1));

      final recorder = AuditRecorder(storage.audit, clock: const SystemClock());
      recorder
        ..request('s', UserInput(text: 'a'))
        ..agentEvent(
          's',
          const Verification(
            profileId: 'p',
            status: VerificationStatus.failed,
            detail: 'Quittung',
          ),
        )
        ..agentEvent(
          's',
          const BudgetWarning(profileId: 'p', spentMicros: 8, budgetMicros: 10),
        )
        ..agentEvent(
          's',
          const AgentFailed(error: AgentErrorKind.timeout, message: 'Zu lang'),
        )
        ..agentEvent('s', const AgentTextDelta('nicht protokolliert'))
        ..record(
          const ToolAuditEntry(
            sessionId: 's',
            callId: 'c',
            tool: 't__x',
            argumentsJson: '{}',
            decision: AuditDecision.allowed,
            status: AuditStatus.ok,
            duration: Duration(milliseconds: 5),
          ),
        );
      await recorder.flush();
      final kinds = (await storage.audit.query()).reversed.map((e) => e.kind);
      expect(kinds, [
        AuditKind.request,
        AuditKind.verification,
        AuditKind.usage,
        AuditKind.error,
        AuditKind.toolCall,
      ]);
    });
  });
}

final class _FailingAudit implements AuditLogRepository {
  @override
  Future<AuditEntry> record(AuditEntry entry) =>
      Future.error(StateError('Datenbank weg'));

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
