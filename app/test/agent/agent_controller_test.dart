import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/session_manager.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';

const _create =
    '{"title":"Tauchen","start":"2026-10-14T10:00","end":"2026-10-14T11:00"}';

/// Waits until [test] holds for the conversation state.
Future<ConversationState> waitFor(
  ProviderContainer c,
  bool Function(ConversationState s) test,
) async {
  final now = c.read(agentControllerProvider);
  if (test(now)) return now;
  final done = Completer<ConversationState>();
  final sub = c.listen(agentControllerProvider, (_, next) {
    if (test(next) && !done.isCompleted) done.complete(next);
  });
  try {
    return await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

Future<ConversationState> sendAndWait(ProviderContainer c, String text) async {
  final controller = c.read(agentControllerProvider.notifier);
  await controller.send(text);
  await controller.idle;
  await c.read(auditRecorderProvider).flush();
  return c.read(agentControllerProvider);
}

void main() {
  late TestEnv env;
  late ProviderContainer c;

  ProviderContainer start(List<ScriptedTurn> turns, {TestEnv? custom}) {
    env = custom ?? TestEnv(providerConfig: scripted(FakeLlmProvider(turns)));
    return c = env.container();
  }

  tearDown(() => c.dispose());

  test(
    'Text → Tool-Call → Tool-Karte mit Undo → Antwort; Undo ruft den Port',
    () async {
      start([
        ScriptedTurn.toolCalls([call('c1', 'calendar__create_event', _create)]),
        ScriptedTurn.text('Erledigt, Tauchen steht morgen um 10.'),
      ]);
      final s = await sendAndWait(c, 'Trag mir morgen um 10 Tauchen ein');
      expect(s.running, isFalse);
      final tool = s.entries.whereType<ToolEntry>().single;
      expect(tool.phase, ToolPhase.done);
      expect(tool.undo, UndoPhase.pending);
      expect(tool.summary, startsWith('Termin angelegt: Tauchen'));
      expect(
        s.entries.whereType<AssistantTextEntry>().last.text,
        'Erledigt, Tauchen steht morgen um 10.',
      );
      expect(env.calendar.events, hasLength(1));

      expect(await c.read(agentControllerProvider.notifier).undo('c1'), isTrue);
      expect(env.calendar.events, isEmpty);
      expect(env.calendar.methodCalls, contains('deleteEvent'));
      final after = await waitFor(
        c,
        (s) => s.tool('c1')?.undo == UndoPhase.undone,
      );
      expect(after.tool('c1')!.undo, UndoPhase.undone);
      // Rückgängig ändert das Gerät und steht deshalb im Audit-Log.
      await c.read(auditRecorderProvider).flush();
      final undone = (await env.storage.audit.query()).where(
        (e) => e.kind == AuditKind.toolCall && e.payload['undo'] == true,
      );
      expect(undone.single.payload, {
        'callId': 'c1',
        'tool': 'calendar__create_event',
        'undo': true,
        'status': 'ok',
      });
      // Zweites Undo gibt es nicht.
      expect(
        await c.read(agentControllerProvider.notifier).undo('c1'),
        isFalse,
      );
    },
  );

  test('Rückgängig schlägt im Port fehl → Audit „failed“, Hinweis', () async {
    start([
      ScriptedTurn.toolCalls([call('c1', 'calendar__create_event', _create)]),
      ScriptedTurn.text('Erledigt.'),
    ]);
    await sendAndWait(c, 'Trag mir morgen um 10 Tauchen ein');
    env.calendar.failNext('deleteEvent');

    expect(await c.read(agentControllerProvider.notifier).undo('c1'), isFalse);
    expect(env.calendar.events, hasLength(1), reason: 'Termin bleibt');
    await c.read(auditRecorderProvider).flush();
    final undone = (await env.storage.audit.query()).where(
      (e) => e.kind == AuditKind.toolCall && e.payload['undo'] == true,
    );
    expect(undone.single.payload, {
      'callId': 'c1',
      'tool': 'calendar__create_event',
      'undo': true,
      'status': 'failed',
    });
    expect(
      c
          .read(agentControllerProvider)
          .entries
          .whereType<NoticeEntry>()
          .map((n) => n.text),
      contains(startsWith('Rückgängig hat nicht geklappt')),
    );
  });

  test(
    'Rückgängig ohne Angebot (zweites Mal) schreibt nichts ins Audit',
    () async {
      start([
        ScriptedTurn.toolCalls([call('c1', 'calendar__create_event', _create)]),
        ScriptedTurn.text('Erledigt.'),
      ]);
      await sendAndWait(c, 'Trag mir morgen um 10 Tauchen ein');
      final controller = c.read(agentControllerProvider.notifier);
      final both = await Future.wait([
        controller.undo('c1'),
        controller.undo('c1'),
      ]);
      expect(both, [isTrue, isFalse]);
      await c.read(auditRecorderProvider).flush();
      final undone = (await env.storage.audit.query()).where(
        (e) => e.payload['undo'] == true,
      );
      expect(undone.map((e) => e.payload['status']), ['ok']);
    },
  );

  test('external-Tool: „Nein“ → Tool wird nicht ausgeführt', () async {
    start([
      ScriptedTurn.toolCalls([
        call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
      ]),
      ScriptedTurn.text('Gut, ich lasse ihn stehen.'),
    ]);
    await env.calendar.createEvent(zahnarztDraft());
    env.calendar.methodCalls.clear();
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Lösch den Zahnarzttermin');
    final asking = await waitFor(c, (s) => s.pending != null);
    final question = asking.pending! as ToolQuestion;
    expect(question.event.call.name, 'calendar__delete_event');
    expect(question.request, 'Lösch den Zahnarzttermin');

    controller.answer(approved: false);
    expect(c.read(agentControllerProvider).pending, isNull);
    await controller.idle;
    final s = c.read(agentControllerProvider);
    expect(s.tool('c1')!.phase, ToolPhase.declined);
    expect(env.calendar.methodCalls, isNot(contains('deleteEvent')));
    expect(env.calendar.events, hasLength(1));
  });

  test('external-Tool: „Ja“ → Tool läuft', () async {
    start([
      ScriptedTurn.toolCalls([
        call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
      ]),
      ScriptedTurn.text('Gelöscht.'),
    ]);
    await env.calendar.createEvent(zahnarztDraft());
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Lösch den Zahnarzttermin');
    await waitFor(c, (s) => s.pending != null);
    controller.answer(approved: true);
    await controller.idle;
    expect(env.calendar.events, isEmpty);
    expect(c.read(agentControllerProvider).tool('c1')!.phase, ToolPhase.done);
  });

  test('Audit-Log: Anfrage, Routing, Tool-Call, Bestätigung, Usage', () async {
    start([
      ScriptedTurn.toolCalls([
        call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
      ]),
      ScriptedTurn.text('Gelöscht.'),
    ]);
    await env.calendar.createEvent(zahnarztDraft());
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Lösch den Zahnarzttermin');
    await waitFor(c, (s) => s.pending != null);
    controller.answer(approved: true);
    await controller.idle;
    await c.read(auditRecorderProvider).flush();

    final entries = (await env.storage.audit.query()).reversed.toList();
    final kinds = entries.map((e) => e.kind).toList();
    expect(
      kinds,
      containsAllInOrder([
        AuditKind.request,
        AuditKind.routing,
        AuditKind.usage,
        AuditKind.confirmation,
        AuditKind.toolCall,
        AuditKind.usage,
      ]),
    );
    final sessionIds = entries.map((e) => e.sessionId).toSet();
    expect(sessionIds, hasLength(1));
    expect(sessionIds.single, isNotNull);

    AuditEntry of(AuditKind k) => entries.firstWhere((e) => e.kind == k);
    expect(of(AuditKind.request).payload['text'], 'Lösch den Zahnarzttermin');
    expect(of(AuditKind.routing).payload, {
      'profileId': 'claude',
      'modelId': 'claude-haiku-4-5',
      'reason': 'Standard',
    });
    expect(of(AuditKind.toolCall).payload, {
      'callId': 'c1',
      'tool': 'calendar__delete_event',
      'arguments': '{"event_id":"e1"}',
      'decision': 'confirmed',
      'status': 'ok',
      'durationMs': 0,
    });
    expect(of(AuditKind.confirmation).payload, {
      'type': 'tool',
      'callId': 'c1',
      'tool': 'calendar__delete_event',
      'description': contains('löschen'),
      'approved': true,
    });
    expect(of(AuditKind.usage).payload['inputTokens'], 100);
    expect(of(AuditKind.usage).payload['outputTokens'], 20);
    expect(of(AuditKind.usage).payload['costMicros'], isA<int>());
  });

  test('Usage landet in der Kostentabelle (heute)', () async {
    start([ScriptedTurn.text('Hallo!')]);
    await sendAndWait(c, 'Hallo');
    await pumpEventQueue();
    final today = await c.read(todayCostProvider.future);
    final days = await env.storage.usage.totalsByDay();
    expect(days.single.usage.inputTokens, 100);
    expect(today, days.single.costMicros);
    expect(today, greaterThan(0), reason: 'Haiku hat Preise im Katalog');
  });

  test('ohne Provider: Hinweis statt Lauf', () async {
    env = TestEnv();
    c = env.container();
    final s = await sendAndWait(c, 'Hallo');
    expect(s.running, isFalse);
    final notice = s.entries.whereType<NoticeEntry>().single;
    expect(notice.text, contains('Provider einrichten'));
    expect(s.entries.whereType<UserEntry>(), isEmpty);
  });

  test('fehlerhaftes Provider-Profil: Fehlerhinweis', () async {
    env = TestEnv(providerConfigError: ArgumentError('Base-URL fehlt'));
    c = env.container();
    final s = await sendAndWait(c, 'Hallo');
    expect(s.running, isFalse);
    expect(s.entries.whereType<NoticeEntry>().single.kind, NoticeKind.error);
  });

  test('erste Anfrage zeigt die Sitzungsmarke, die zweite nicht', () async {
    start([ScriptedTurn.text('Eins'), ScriptedTurn.text('Zwei')]);
    await sendAndWait(c, 'A');
    final s = await sendAndWait(c, 'B');
    expect(s.entries.whereType<SessionStartEntry>(), hasLength(1));
    expect(s.entries.whereType<UserEntry>().map((e) => e.text), ['A', 'B']);
  });

  test('Verlauf geht an den nächsten Lauf (gleiche Sitzung)', () async {
    final provider = FakeLlmProvider([
      ScriptedTurn.text('Eins'),
      ScriptedTurn.text('Zwei'),
    ]);
    start(const [], custom: TestEnv(providerConfig: scripted(provider)));
    await sendAndWait(c, 'A');
    await sendAndWait(c, 'B');
    final second = provider.requests.last.messages;
    expect(second.map((m) => m.text), ['A', 'Eins', 'B']);
  });

  test(
    '„neues Thema“ startet eine neue Sitzung und beendet die alte',
    () async {
      final ended = <String>[];
      final provider = FakeLlmProvider([
        ScriptedTurn.text('Eins'),
        ScriptedTurn.text('Zwei'),
      ]);
      env = TestEnv(providerConfig: scripted(provider));
      c = ProviderContainer(
        overrides: [
          ...env.overrides,
          integrationSpecsProvider.overrideWithValue([
            ...builtInIntegrationSpecs,
            IntegrationSpec(
              id: 'spy',
              create: (_) => FakeIntegration(id: 'spy', tools: const []),
              onSessionEnd: (i) => ended.add(i.id),
            ),
          ]),
        ],
        retry: (_, _) => null,
      );
      await sendAndWait(c, 'A');
      final first = c.read(sessionManagerProvider).currentId;
      await c.read(agentControllerProvider.notifier).send('Neues Thema!');
      final s = c.read(agentControllerProvider);
      expect(ended, ['spy']);
      expect(s.entries.single, isA<SessionStartEntry>());
      expect(c.read(sessionManagerProvider).currentId, isNot(first));
      await sendAndWait(c, 'B');
      expect(provider.requests.last.messages.map((m) => m.text), ['B']);
    },
  );

  test('Abbrechen beendet den Lauf mit Hinweis', () async {
    start([ScriptedTurn.hang(partialText: 'Moment')]);
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Hallo');
    await waitFor(
      c,
      (s) => s.entries.whereType<AssistantTextEntry>().isNotEmpty,
    );
    controller.cancel();
    await controller.idle;
    final s = c.read(agentControllerProvider);
    expect(s.running, isFalse);
    expect(s.entries.whereType<NoticeEntry>().single.text, 'Abgebrochen.');
  });

  test('während eines Laufs wird keine zweite Anfrage gestartet', () async {
    final provider = FakeLlmProvider([ScriptedTurn.hang()]);
    start(const [], custom: TestEnv(providerConfig: scripted(provider)));
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('A');
    while (provider.requests.isEmpty) {
      await pumpEventQueue();
    }
    await controller.send('B');
    expect(
      c.read(agentControllerProvider).entries.whereType<UserEntry>(),
      hasLength(1),
    );
    controller.cancel();
    await controller.idle;
    expect(provider.requests, hasLength(1));
  });

  test(
    'Anbieter fällt aus: Meldung mit Grund, nie ein Wechsel (K28)',
    () async {
      final private = FakeLlmProvider([
        ScriptedTurn.error(const RateLimitException('voll')),
        ScriptedTurn.error(const RateLimitException('voll')),
      ]);
      final cloud = FakeLlmProvider([ScriptedTurn.text('nie')]);
      final config = scripted(
        private,
        id: 'local',
        name: 'Ollama',
        privacy: PrivacyLevel.local,
        others: [
          ProviderTarget(
            profileId: 'sonnet',
            modelId: 'claude-sonnet',
            provider: cloud,
            privacy: PrivacyLevel.standard,
          ),
        ],
        names: {'sonnet': 'Claude Sonnet'},
        isPrivate: (_) => true,
      );
      env = TestEnv(providerConfig: config);
      c = env.container();
      final controller = c.read(agentControllerProvider.notifier);
      await controller.send('privat: wie spät ist es');
      await controller.idle;
      await c.read(auditRecorderProvider).flush();
      expect(private.requests, hasLength(2));
      expect(cloud.requests, isEmpty);
      final s = c.read(agentControllerProvider);
      expect(s.pending, isNull);
      expect(s.entries.whereType<EscalationEntry>(), isEmpty);
      final notice = s.entries.whereType<NoticeEntry>().single;
      expect(notice.kind, NoticeKind.error);
      expect(
        notice.text,
        'Ollama hat das Kontingent erreicht (zu viele Anfragen).',
      );
      final audit = await env.storage.audit.query(
        const AuditFilter(
          kinds: {AuditKind.confirmation, AuditKind.escalation},
        ),
      );
      expect(audit, isEmpty);
    },
  );

  test('restore zeigt die offene Sitzung nach dem Neustart', () async {
    start([ScriptedTurn.text('Eins')]);
    await sendAndWait(c, 'A');
    final storage = env.storage;
    c.dispose();

    c = env.container();
    expect(env.storage, same(storage));
    await c.read(agentControllerProvider.notifier).restore();
    final s = c.read(agentControllerProvider);
    expect(s.entries.first, isA<SessionStartEntry>());
    expect(s.entries.whereType<UserEntry>().single.text, 'A');
    expect(s.entries.whereType<AssistantTextEntry>().single.text, 'Eins');
  });

  test('restore lässt eine abgelaufene Sitzung weg', () async {
    start([ScriptedTurn.text('Eins')]);
    await sendAndWait(c, 'A');
    env.clock.advance(const Duration(minutes: 6));
    final fresh = ProviderContainer(
      overrides: env.overrides,
      retry: (_, _) => null,
    );
    addTearDown(fresh.dispose);
    await fresh.read(agentControllerProvider.notifier).restore();
    expect(fresh.read(agentControllerProvider).entries, isEmpty);
  });

  group('Review WP08', () {
    test(
      'Sitzungsende vergisst per tools__search freigeschaltete Tools',
      () async {
        final provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
        env = TestEnv(
          providerConfig: scripted(provider),
          enabled: const {'spy'},
        );
        c = ProviderContainer(
          overrides: [
            ...env.overrides,
            integrationSpecsProvider.overrideWithValue([
              ...builtInIntegrationSpecs,
              IntegrationSpec(
                id: 'spy',
                create: (_) => FakeIntegration(
                  id: 'spy',
                  tools: [
                    for (var i = 0; i < 30; i++)
                      FakeTool(
                        name: 'spy__werkzeug$i',
                        description: 'Spion $i',
                      ),
                  ],
                ),
              ),
            ]),
          ],
          retry: (_, _) => null,
        );
        await sendAndWait(c, 'A');
        final old = c.read(sessionManagerProvider).currentId!;
        final registry = c.read(toolRegistryProvider);
        final search = registry
            .catalogFor(PrivacyLevel.standard, sessionId: old)
            .lookup('tools__search');
        expect(search, isNotNull, reason: 'ab 30 Tools gibt es das Meta-Tool');
        await search!.execute(
          {'query': 'spy werkzeug'},
          ToolContext(
            sessionId: old,
            clock: env.clock,
            locale: 'de-DE',
            timeZone: 'Europe/Berlin',
          ),
        );
        expect(registry.unlockedTools(old), isNotEmpty);

        await c.read(agentControllerProvider.notifier).newTopic();
        expect(registry.unlockedTools(old), isEmpty);
        expect(c.read(sessionManagerProvider).currentId, isNot(old));
      },
    );

    test('Sitzung lässt sich nicht öffnen: Lauf endet sauber', () async {
      final provider = FakeLlmProvider([ScriptedTurn.text('nie')]);
      env = TestEnv(providerConfig: scripted(provider));
      c = ProviderContainer(
        overrides: [
          ...env.overrides,
          sessionManagerProvider.overrideWithValue(
            SessionManager(
              conversations: _BrokenConversations(),
              clock: env.clock,
              onSessionEnd: (_) {},
            ),
          ),
        ],
        retry: (_, _) => null,
      );
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final s = await sendAndWait(c, 'Hallo');
      expect(s.running, isFalse);
      expect(s.entries.whereType<NoticeEntry>().single.kind, NoticeKind.error);
      expect(errors.single.exception, isA<StateError>());
      expect(provider.requests, isEmpty);
      // Danach geht es wieder.
      expect(c.read(agentControllerProvider.notifier).idle, completes);
    });

    test('Fehler im Agent-Stream beendet den Lauf mit Hinweis', () async {
      env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      c = ProviderContainer(
        overrides: [
          ...env.overrides,
          agentFactoryProvider.overrideWithValue(_BrokenFactory()),
        ],
        retry: (_, _) => null,
      );
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final s = await sendAndWait(c, 'Hallo');
      expect(s.running, isFalse);
      expect(
        s.entries.whereType<NoticeEntry>().single.text,
        contains('Interner Fehler'),
      );
      expect(errors, hasLength(1));
      final audit = await env.storage.audit.query(
        const AuditFilter(kinds: {AuditKind.error}),
      );
      expect(audit.single.payload['error'], 'internal');
    });

    test('erste Anfrage wartet, bis alle Integrationen geprüft sind', () async {
      final gate = Completer<void>();
      final provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
      env = TestEnv(
        providerConfig: scripted(provider),
        enabled: const {'slow'},
      );
      c = ProviderContainer(
        overrides: [
          ...env.overrides,
          integrationSpecsProvider.overrideWithValue([
            IntegrationSpec(id: 'slow', create: (_) => _SlowIntegration(gate)),
          ]),
        ],
        retry: (_, _) => null,
      );
      final controller = c.read(agentControllerProvider.notifier);
      final sent = controller.send('Hallo');
      await pumpEventQueue();
      expect(provider.requests, isEmpty, reason: 'wartet auf die Prüfung');
      gate.complete();
      await sent;
      await controller.idle;
      expect(provider.requests.single.tools.map((t) => t.name), ['slow__tool']);
    });
  });

  group('Datenschutz in der Verdrahtung', () {
    test(
      'Gedächtnis kommt nur in den Prompt, wenn die Integration aktiv ist',
      () async {
        for (final enabled in [true, false]) {
          final provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
          env = TestEnv(
            providerConfig: scripted(provider),
            enabled: enabled ? const {'memory'} : const {},
          );
          c = env.container();
          await c.read(toolRegistryProvider).refresh();
          await env.storage.memory.save(
            'Taucht gern im Mittelmeer',
            category: StoredMemoryCategory.preference,
            source: 'user',
          );
          await sendAndWait(c, 'Wo taucht man gut?');
          expect(
            provider.requests.single.systemPrompt,
            enabled
                ? contains('Taucht gern im Mittelmeer')
                : isNot(contains('Taucht gern im Mittelmeer')),
            reason: 'memory aktiv: $enabled',
          );
          c.dispose();
        }
        c = env.container();
      },
    );

    test('Gedächtnis je Ziel: das TEE-Ziel bekommt es auch in gemischter '
        'Kette, der Lauf wird dafür vertraulich (WP14, Review WP26)', () async {
      for (final mixed in [true, false]) {
        final provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
        env = TestEnv(
          providerConfig: scripted(
            provider,
            privacy: PrivacyLevel.tee,
            others: [
              if (mixed)
                ProviderTarget(
                  profileId: 'cloud',
                  modelId: 'm',
                  provider: FakeLlmProvider(const []),
                  privacy: PrivacyLevel.standard,
                ),
            ],
          ),
          enabled: const {'memory'},
        );
        c = env.container();
        final registry = c.read(toolRegistryProvider)
          ..sensitiveMinimum = PrivacyLevel.tee;
        await registry.refresh();
        await env.storage.memory.save(
          'Taucht gern im Mittelmeer',
          category: StoredMemoryCategory.preference,
          source: 'user',
        );
        await sendAndWait(c, 'Wo taucht man gut?');
        expect(
          provider.requests.single.systemPrompt,
          contains('Taucht gern im Mittelmeer'),
          reason: 'Kette mit Standard-Ziel: $mixed',
        );
        final sessionId = c.read(sessionManagerProvider).currentId!;
        final stored = await env.storage.conversations.messages(sessionId);
        expect(
          stored.map((m) => m.message.privacyFloor),
          everyElement(PrivacyLevel.tee),
          reason: 'Gedächtnis gesehen: Eskalation darunter fragt nach',
        );
        c.dispose();
      }
      c = env.container();
    });

    test('TEE-Ziel in gemischter Kette führt sensibles Tool aus, Standard-Ziel '
        'wird abgelehnt und auditiert (WP14)', () async {
      final tee = FakeLlmProvider([
        ScriptedTurn.toolCalls([call('c1', 'calendar__create_event', _create)]),
        ScriptedTurn.text('Eingetragen.'),
      ]);
      env = TestEnv(
        providerConfig: scripted(
          tee,
          privacy: PrivacyLevel.tee,
          others: [
            ProviderTarget(
              profileId: 'cloud',
              modelId: 'm',
              provider: FakeLlmProvider(const []),
              privacy: PrivacyLevel.standard,
            ),
          ],
        ),
        enabled: const {'calendar'},
      );
      c = env.container();
      c.read(toolRegistryProvider).sensitiveMinimum = PrivacyLevel.tee;
      await c.read(toolRegistryProvider).refresh();
      await sendAndWait(c, 'Trag Tauchen ein');
      expect(env.calendar.methodCalls, contains('createEvent'));
      c.dispose();

      final cloud = FakeLlmProvider([
        ScriptedTurn.toolCalls([call('c2', 'calendar__create_event', _create)]),
        ScriptedTurn.text('Geht nicht.'),
      ]);
      env = TestEnv(
        providerConfig: scripted(cloud),
        enabled: const {'calendar'},
      );
      c = env.container();
      c.read(toolRegistryProvider).sensitiveMinimum = PrivacyLevel.tee;
      await c.read(toolRegistryProvider).refresh();
      await sendAndWait(c, 'Trag Tauchen ein');
      expect(env.calendar.methodCalls, isNot(contains('createEvent')));
      await c.read(auditRecorderProvider).flush();
      final audit = await env.storage.audit.query(
        const AuditFilter(kinds: {AuditKind.toolCall}),
      );
      expect(audit.single.payload['tool'], 'calendar__create_event');
      expect(audit.single.payload['status'], 'denied');
    });

    test('Werkzeuge nach der Stufe des aktuellen Ziels (WP14)', () async {
      final provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
      final cloud = FakeLlmProvider(const []);
      env = TestEnv(
        providerConfig: scripted(
          provider,
          privacy: PrivacyLevel.tee,
          others: [
            ProviderTarget(
              profileId: 'cloud',
              modelId: 'm',
              provider: cloud,
              privacy: PrivacyLevel.standard,
            ),
          ],
        ),
        enabled: const {'calendar', 'alarms'},
      );
      c = env.container();
      final registry = c.read(toolRegistryProvider)
        ..sensitiveMinimum = PrivacyLevel.tee;
      await registry.refresh();
      await sendAndWait(c, 'Hallo');
      // Das TEE-Ziel sieht den sensiblen Kalender …
      final teeTools = provider.requests.first.tools.map((t) => t.name);
      expect(teeTools, contains('calendar__create_event'));
      expect(teeTools, contains('alarms__set_timer'));
      // … und das Standard-Ziel wird nie angefragt (kein Wechsel, K28).
      expect(cloud.requests, isEmpty);
    });
  });

  test('isNewTopicCommand erkennt nur den Befehl', () {
    expect(AgentController.isNewTopicCommand('Neues Thema'), isTrue);
    expect(AgentController.isNewTopicCommand('neues thema.'), isTrue);
    expect(AgentController.isNewTopicCommand('ein neues Thema bitte'), isFalse);
  });
}

final class _BrokenConversations implements ConversationRepository {
  @override
  Future<Session> currentOrNew(
    DateTime now, {
    Duration inactivity = ConversationRepository.defaultInactivity,
  }) => Future.error(StateError('Datenbank gesperrt'));

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An agent whose stream breaks its contract with an error.
final class _BrokenFactory implements AgentRunFactory {
  @override
  AgentRun create(ProviderConfig providers, String sessionId) => _BrokenRun();
}

final class _BrokenRun implements AgentRun {
  @override
  Stream<AgentEvent> run(UserInput input) => Stream.error(StateError('kaputt'));

  @override
  void cancel() {}
}

/// Integration whose availability check waits for [gate].
final class _SlowIntegration implements Integration {
  _SlowIntegration(this.gate);

  final Completer<void> gate;

  @override
  String get id => 'slow';

  @override
  String get displayName => 'Langsam';

  @override
  String get iconId => 'slow';

  @override
  Set<AppPlatform> get platforms => AppPlatform.values.toSet();

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async {
    await gate.future;
    return Availability.yes;
  }

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState();

  @override
  late final List<Tool> tools = [FakeTool(name: 'slow__tool')];
}
