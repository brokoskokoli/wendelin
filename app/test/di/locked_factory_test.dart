import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/audit_recorder.dart';
import 'package:wendelin/di/locked_scope.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin_agent/testing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// WP154 L2: a request on a locked device runs with the tools the policy
/// allows only. Every context source is checked: tool specs, history,
/// recording, memory, prompt sections, user name, audit mark.
void main() {
  late FakeTool allowed;
  late FakeTool refused;
  late FakeTool memoryTool;
  late FakeLlmProvider provider;
  late WendelinStorage storage;
  late AuditRecorder audit;
  late AgentFactory factory;
  late String session;

  const lockedA = LockedScope(
    access: AccessContext.lockedUnknownVoice,
    tools: {'a__read'},
  );

  setUp(() async {
    storage = openInMemoryStorage();
    addTearDown(storage.close);
    session = (await storage.conversations.startNew(DateTime(2026, 10, 21))).id;
    allowed = FakeTool(name: 'a__read', section: 'Abschnitt A');
    refused = FakeTool(name: 'b__read', section: 'Abschnitt B');
    memoryTool = FakeTool(name: 'memory__search');
    final registry = ToolRegistry(sensitiveMinimum: PrivacyLevel.tee);
    for (final (id, tool) in [
      ('a', allowed),
      ('b', refused),
      ('memory', memoryTool),
    ]) {
      await registry.registerIntegration(
        FakeIntegration(id: id, tools: [tool]),
        enabled: true,
      );
    }
    addTearDown(registry.dispose);
    final policy = RiskPolicy()
      ..setLevel('a__read', SecurityLevel.a)
      ..setLevel('b__read', SecurityLevel.c)
      ..setLevel('memory__search', SecurityLevel.c);
    audit = AuditRecorder(storage.audit, clock: const SystemClock());
    factory = AgentFactory(
      registry: registry,
      storage: storage,
      policy: policy,
      audit: audit,
      clock: const SystemClock(),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      costEstimator: const FlatCostEstimator(),
      budgetGuard: FixedBudgetGuard(),
      config: const AgentConfig(userName: 'Erfundener Name'),
    );
  });

  Future<List<AgentEvent>> run(
    List<ScriptedTurn> turns, {
    LockedScope? locked,
    String text = 'Mach das',
  }) async {
    provider = FakeLlmProvider(turns);
    final events = await factory
        .create(
          ProviderConfig(
            primary: ProviderTarget(
              profileId: 'p',
              modelId: 'm',
              provider: provider,
              privacy: PrivacyLevel.tee,
            ),
          ),
          session,
          locked: locked,
        )
        .run(UserInput(text: text, language: 'de'))
        .toList();
    expect(events.last, isA<AgentDone>(), reason: '$events');
    return events;
  }

  List<String> toolNames() => [
    for (final t in provider.requests.first.tools) t.name,
  ];
  String prompt() => provider.requests.first.systemPrompt ?? '';

  test('entsperrt: alle Tools, Name, Verlauf, Abschnitte', () async {
    await run([ScriptedTurn.text('ok')]);
    expect(toolNames(), containsAll(['a__read', 'b__read']));
    expect(prompt(), contains('Erfundener Name'));
    expect(prompt(), contains('Abschnitt B'));
  });

  test('gesperrt: nur erlaubte Tool-Specs und Promptabschnitte', () async {
    await run([ScriptedTurn.text('ok')], locked: lockedA);
    expect(toolNames(), ['a__read']);
    expect(prompt(), contains('Abschnitt A'));
    expect(prompt(), isNot(contains('Abschnitt B')));
    expect(allowed.sectionAccess.single, AccessContext.lockedUnknownVoice);
  });

  test('gesperrt: Nutzername nicht im Prompt (an den Anbieter)', () async {
    await run([ScriptedTurn.text('ok')], locked: lockedA);
    expect(prompt(), isNot(contains('Erfundener Name')));
  });

  test('gesperrt: nicht erlaubter Aufruf wird nie ausgeführt', () async {
    final events = await run([
      ScriptedTurn.toolCalls([
        ToolCallBlock(id: '1', name: 'b__read', argumentsJson: '{}'),
        ToolCallBlock(id: '2', name: 'nicht_da', argumentsJson: '{}'),
      ]),
      ScriptedTurn.text('Bitte entsperren.'),
    ], locked: lockedA);
    expect(refused.callCount, 0);
    final finished = {
      for (final e in events.whereType<ToolCallFinished>()) e.call.name: e,
    };
    expect(finished['b__read']!.outcome.isError, isTrue);
    expect(finished['b__read']!.outcome.summary, 'Entsperren nötig');
    // Auch ein erfundener Name führt nichts aus (Fehler, kein Treffer).
    expect(finished['nicht_da']!.outcome.isError, isTrue);
    await audit.flush();
    final log = await storage.audit.query();
    expect(
      log
          .where((e) => e.kind == AuditKind.toolCall)
          .every((e) => e.payload['whileLocked'] == true),
      isTrue,
    );
  });

  test('gesperrt: erlaubter Aufruf läuft, Audit markiert bei Sperre', () async {
    await run([
      ScriptedTurn.toolCalls([
        ToolCallBlock(id: '1', name: 'a__read', argumentsJson: '{}'),
      ]),
      ScriptedTurn.text('Erledigt.'),
    ], locked: lockedA);
    expect(allowed.callCount, 1);
    await audit.flush();
    final call = (await storage.audit.query()).singleWhere(
      (e) => e.kind == AuditKind.toolCall,
    );
    expect(call.payload['whileLocked'], isTrue);
  });

  test('gesperrt: Verlauf nicht gelesen, nichts gespeichert', () async {
    await run([ScriptedTurn.text('Geheime Antwort')], text: 'Geheimwort');
    final stored = await storage.conversations.messages(session);
    expect(stored, isNotEmpty);
    await run([ScriptedTurn.text('ok')], locked: lockedA, text: 'Neu');
    final sent = provider.requests.first.messages;
    expect(sent, hasLength(1));
    expect(sent.single.toString(), isNot(contains('Geheim')));
    expect(
      await storage.conversations.messages(session),
      hasLength(stored.length),
      reason: 'gesperrte Anfrage wird nicht aufgezeichnet',
    );
  });

  group('Gedächtnis', () {
    setUp(
      () => storage.memory.save(
        'Lieblingsfarbe ist Tannengrün',
        category: StoredMemoryCategory.preference,
        source: 'user',
      ),
    );

    test('gesperrt ohne memory__search: nicht im Prompt', () async {
      await run(
        [ScriptedTurn.text('ok')],
        locked: lockedA,
        text: 'Lieblingsfarbe',
      );
      expect(prompt(), isNot(contains('Tannengrün')));
    });

    test('gesperrt mit erlaubtem memory__search: im Prompt', () async {
      await run(
        [ScriptedTurn.text('ok')],
        locked: const LockedScope(
          access: AccessContext.lockedUnknownVoice,
          tools: {'a__read', 'memory__search'},
        ),
        text: 'Lieblingsfarbe',
      );
      expect(prompt(), contains('Tannengrün'));
    });

    test('entsperrt: im Prompt', () async {
      await run([ScriptedTurn.text('ok')], text: 'Lieblingsfarbe');
      expect(prompt(), contains('Tannengrün'));
    });
  });

  test('LockedCatalog: listet nur Angebotenes, lookup findet alles', () {
    final inner = FakeToolCatalog([allowed, refused]);
    final catalog = LockedCatalog(inner, [allowed]);
    expect([for (final s in catalog.activeSpecs()) s.name], ['a__read']);
    expect(catalog.lookup('b__read'), same(refused));
    expect(catalog.lookup('x'), isNull);
  });
}
