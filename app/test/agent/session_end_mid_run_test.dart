import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// WP157 review round 1, finding 1: the session ends (absence timer, new
/// topic) while a run of it is still going. The lock of that session id must
/// hold until the run is over, else the next round of the same run would
/// execute an `external` tool of a conversation whose answer failed.

/// A TEE-like provider whose receipts follow [statuses]; [onReport] runs when
/// the n-th receipt is asked for (the run is then in the middle of a round).
final class _Tee implements LlmProvider, AttestationAware {
  _Tee(this.inner, this.statuses, {this.onReport});

  final FakeLlmProvider inner;
  final List<AttestationStatus> statuses;
  final void Function(int n)? onReport;
  var _n = 0;

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
  Future<AttestationReport?> reportFor(ChatRequest request) async {
    final n = ++_n;
    onReport?.call(n);
    return AttestationReport(
      logId: 'att',
      status: statuses[n - 1],
      detail: 'x',
    );
  }
}

final class _MemStore implements SessionLockStore {
  Map<String, String> saved = {};
  var saves = 0;

  @override
  Future<Map<String, String>> load() async => Map.of(saved);

  @override
  Future<void> save(Map<String, String> locks) async {
    saves++;
    saved = Map.of(locks);
  }
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

void main() {
  const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');

  /// Round 1 red (locks), round 2 green; the session ends when the receipt
  /// of round 2 is asked for, i.e. while the run is going.
  Future<(FakeTool, RiskPolicy, _MemStore)> run({
    required bool endMidRun,
  }) async {
    final tool = FakeTool(name: 'sms__send', risk: RiskLevel.external);
    final store = _MemStore();
    final policy = RiskPolicy(lockStore: store);
    final provider = _Tee(
      FakeLlmProvider([
        ScriptedTurn.toolCalls([
          ToolCallBlock(id: 'c1', name: tool.name, argumentsJson: '{}'),
        ]),
        ScriptedTurn.toolCalls([
          ToolCallBlock(id: 'c2', name: tool.name, argumentsJson: '{}'),
        ]),
        ScriptedTurn.text('Fertig.'),
      ]),
      [AttestationStatus.red, AttestationStatus.green, AttestationStatus.green],
      onReport: (n) {
        if (endMidRun && n == 2) policy.endSession('s1');
      },
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
      invoker: ToolExecutor(catalog: catalog, policy: policy),
      clock: clock,
      sessionId: 's1',
    );
    await for (final e in runner.run(UserInput(text: 'Sende'))) {
      if (e is ConfirmationRequired) e.respond(true);
    }
    await pumpEventQueue();
    return (tool, policy, store);
  }

  test(
    'Kontrolle: ohne Sitzungsende bleibt das external-Tool gesperrt',
    () async {
      final (tool, policy, _) = await run(endMidRun: false);
      expect(tool.callCount, 0);
      expect(policy.isExternalLocked('s1'), isTrue);
    },
  );

  test('Sitzungsende mitten im Lauf gibt die Sperre nicht frei', () async {
    final (tool, _, _) = await run(endMidRun: true);
    expect(tool.callCount, 0, reason: 'Sperre hält bis der Lauf zu Ende ist');
  });

  test('nach dem Lauf wirkt das aufgeschobene Sitzungsende', () async {
    final (_, policy, store) = await run(endMidRun: true);
    expect(policy.isExternalLocked('s1'), isFalse);
    expect(store.saved, isEmpty, reason: 'auch aus dem Speicher entfernt');
  });
}
