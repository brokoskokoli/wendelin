import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// WP157: the lock after a red receipt belongs to the conversation (session
/// id), not to one provider instance or one engine. Each "engine" below has
/// its own provider, its own [RiskPolicy] and runner, like an overlay or app
/// rebuild; only the session id and the (shared) lock storage survive.

/// A TEE-like provider whose receipt has the fixed [status].
final class _Tee implements LlmProvider, AttestationAware {
  _Tee(this.inner, this.status);

  final FakeLlmProvider inner;
  final AttestationStatus status;

  @override
  ProviderType get type => inner.type;
  @override
  ProviderCapabilities get caps => inner.caps;
  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      inner.chat(req, cancel: cancel);
  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();
  @override
  Future<HealthCheck> test() => inner.test();
  @override
  Stream<AttestationReport> get reports => const Stream.empty();
  @override
  Future<AttestationReport?> reportFor(ChatRequest request) async =>
      AttestationReport(logId: 'att', status: status, detail: 'x');
}

void main() {
  const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');

  /// One engine: new provider, new policy, new runner for session [id].
  Future<List<AgentEvent>> engineRun({
    required String session,
    required AttestationStatus status,
    required FakeTool tool,
    RiskPolicy? policy,
  }) async {
    final provider = _Tee(
      FakeLlmProvider([
        ScriptedTurn.toolCalls([
          ToolCallBlock(id: 'c1', name: tool.name, argumentsJson: '{}'),
        ]),
        ScriptedTurn.text('Fertig.'),
      ]),
      status,
    );
    final catalog = FakeToolCatalog([tool]);
    final clock = FixedClock(DateTime.utc(2026, 10, 26, 9));
    final runner = AgentRunner(
      resolver: _Fixed(
        ProviderTarget(
          profileId: 'tee',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
      ),
      contextBuilder: ContextBuilder(
        config: const AgentConfig(),
        clock: clock,
        device: device,
        catalog: catalog,
      ),
      invoker: ToolExecutor(catalog: catalog, policy: policy ?? RiskPolicy()),
      clock: clock,
      sessionId: session,
    );
    final events = <AgentEvent>[];
    await for (final e in runner.run(UserInput(text: 'Sende'))) {
      events.add(e);
      if (e is ConfirmationRequired) e.respond(true);
    }
    return events;
  }

  late _MemStore store;
  setUp(() => store = _MemStore());

  Future<void> run(
    String session,
    AttestationStatus status,
    FakeTool tool, {
    SessionLockStore? lockStore,
  }) => engineRun(
    session: session,
    status: status,
    tool: tool,
    policy: RiskPolicy(lockStore: lockStore ?? store),
  );

  FakeTool sms() => FakeTool(name: 'sms__send', risk: RiskLevel.external);

  test('rote Quittung: external-Tool läuft in derselben Unterhaltung nach '
      'Neuaufbau der Engine nicht wieder', () async {
    final tool = sms();
    await run('s1', AttestationStatus.red, tool);
    expect(tool.callCount, 0, reason: 'Rot: nicht ausgeführt');
    // New engine (overlay or app rebuild): new provider, new policy, same
    // conversation, green receipt.
    await run('s1', AttestationStatus.green, tool);
    expect(tool.callCount, 0, reason: 'Sitzung bleibt gesperrt');
    expect(store.saved.keys, ['s1'], reason: 'für den Neustart gespeichert');
    expect(store.saved['s1'], 'tee', reason: 'mit dem Profil der Antwort');
  });

  test('ohne Speicher (alter Aufbau) ginge die Sperre verloren', () async {
    // Documents the defect of WP157: lock only in the memory of one engine.
    final tool = sms();
    await engineRun(
      session: 's1',
      status: AttestationStatus.red,
      tool: tool,
      policy: RiskPolicy(),
    );
    await engineRun(
      session: 's1',
      status: AttestationStatus.green,
      tool: tool,
      policy: RiskPolicy(),
    );
    expect(tool.callCount, 1);
  });

  test('neue Unterhaltung (neue Sitzungs-Id) ist nicht gesperrt', () async {
    final tool = sms();
    await run('s1', AttestationStatus.red, tool);
    await run('s2', AttestationStatus.green, tool);
    expect(tool.callCount, 1);
  });

  test('nicht prüfbar (unconfirmed) sperrt nicht', () async {
    final tool = sms();
    await run('s1', AttestationStatus.unconfirmed, tool);
    await run('s1', AttestationStatus.green, tool);
    expect(tool.callCount, 1);
    expect(store.saved, isEmpty);
  });

  test('read-Tools laufen in der gesperrten Unterhaltung weiter', () async {
    final notes = FakeTool(name: 'notes__read', risk: RiskLevel.read);
    await run('s1', AttestationStatus.red, sms());
    await run('s1', AttestationStatus.green, notes);
    expect(notes.callCount, 1);
  });

  test('grüne Neuprüfung des Profils hebt die Sperre auf', () async {
    final tool = sms();
    await run('s1', AttestationStatus.red, tool);
    final policy = RiskPolicy(lockStore: store);
    await policy.ready;
    expect(policy.isExternalLocked('s1'), isTrue);
    policy.unlockProfile('other');
    expect(policy.isExternalLocked('s1'), isTrue, reason: 'anderes Profil');
    policy.unlockProfile('tee');
    expect(policy.isExternalLocked('s1'), isFalse);
    await pumpEventQueue();
    await run('s1', AttestationStatus.green, tool);
    expect(tool.callCount, 1);
  });

  test(
    'Neuprüfung entsperrt nur das eigene Profil, das andere bleibt',
    () async {
      final policy = RiskPolicy(lockStore: store);
      await policy.ready;
      policy.lockExternal('s1', profileId: 'tee');
      policy.lockExternal('s2', profileId: 'other');
      policy.lockExternal('s3', profileId: 'tee');
      policy.unlockProfile('tee');
      expect(policy.isExternalLocked('s1'), isFalse);
      expect(policy.isExternalLocked('s3'), isFalse);
      expect(policy.isExternalLocked('s2'), isTrue, reason: 'zweites Profil');
      await pumpEventQueue();
      final reloaded = RiskPolicy(lockStore: store);
      await reloaded.ready;
      expect(reloaded.isExternalLocked('s2'), isTrue, reason: 'persistiert');
      expect(reloaded.isExternalLocked('s1'), isFalse);
    },
  );

  test(
    'Ende der Unterhaltung hebt die Sperre auf und räumt den Speicher',
    () async {
      final tool = sms();
      await run('s1', AttestationStatus.red, tool);
      final policy = RiskPolicy(lockStore: store);
      await policy.ready;
      policy.endSession('s1');
      await Future<void>.delayed(Duration.zero);
      expect(policy.isExternalLocked('s1'), isFalse);
      expect(store.saved, isEmpty);
    },
  );

  test('Speicher unlesbar: fail-closed, kein external-Tool', () async {
    final tool = sms();
    await run('s9', AttestationStatus.green, tool, lockStore: _BrokenStore());
    expect(tool.callCount, 0);
  });

  test('Speichern scheitert: Sperre gilt im Speicher weiter', () async {
    final tool = sms();
    final policy = RiskPolicy(lockStore: _BrokenStore(failLoad: false));
    await engineRun(
      session: 's1',
      status: AttestationStatus.red,
      tool: tool,
      policy: policy,
    );
    expect(policy.isExternalLocked('s1'), isTrue);
  });

  test('mehr als 50 Sperren: die ältesten fallen heraus', () {
    final policy = RiskPolicy(lockStore: store);
    for (var i = 0; i < RiskPolicy.maxLockedSessions + 3; i++) {
      policy.lockExternal('s$i');
    }
    expect(policy.isExternalLocked('s0'), isFalse);
    expect(
      policy.isExternalLocked('s${RiskPolicy.maxLockedSessions + 2}'),
      isTrue,
    );
  });
}

final class _MemStore implements SessionLockStore {
  Map<String, String> saved = {};

  @override
  Future<Map<String, String>> load() async => Map.of(saved);

  @override
  Future<void> save(Map<String, String> locks) async => saved = Map.of(locks);
}

final class _BrokenStore implements SessionLockStore {
  _BrokenStore({this.failLoad = true});

  final bool failLoad;

  @override
  Future<Map<String, String>> load() async =>
      failLoad ? throw const FormatException('kaputt') : {};

  @override
  Future<void> save(Map<String, String> locks) async =>
      throw StateError('Platte voll');
}

final class _Fixed implements ProviderResolver {
  _Fixed(this.target);

  final ProviderTarget target;

  @override
  Resolution resolve(UserInput input) =>
      Resolution(target: target, reason: 'Standard');

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) => null;
}
