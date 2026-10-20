import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

EvalCase _case(String id) => parseCaseFile('''
language: de
cases:
  - id: $id
    prompt: Wie spät ist es?
    expect:
      no_tools: true
''').single;

const _limit = RateLimitException('trop de requêtes');

/// One model call (200 µUSD), then the rate limit twice (the agent retries a
/// retryable error once itself).
List<ScriptedTurn> _limited() => [
  ScriptedTurn.toolCalls([
    const ToolCallBlock(
      id: 'c1',
      name: 'calendar__list_events',
      argumentsJson: '{}',
    ),
  ]),
  ScriptedTurn.error(_limit),
  ScriptedTurn.error(_limit),
];

void main() {
  final time = EvalTime.parse('2026-10-14T09:00', defaultTimeZone);

  /// Attempt n of every case plays `attempts[n]` (last one repeats).
  (EvalRunner, List<Duration>, List<int>) runner(
    List<List<ScriptedTurn> Function()> attempts, {
    Duration pause = Duration.zero,
    Duration? retry,
    int maxRateLimited = 5,
    CostBudget? budget,
  }) {
    final sleeps = <Duration>[];
    final started = <int>[];
    return (
      EvalRunner(
        target: EvalTarget(
          profileId: 'fake',
          modelId: 'fake-model',
          privacy: PrivacyLevel.local,
          provider: (_) {
            final i = started.length < attempts.length
                ? started.length
                : attempts.length - 1;
            started.add(started.length);
            return FakeLlmProvider(attempts[i]());
          },
          costEstimator: const FlatCostEstimator(),
        ),
        time: time,
        pause: pause,
        retryRateLimit: retry,
        maxRateLimited: maxRateLimited,
        budget: budget,
        sleep: (d) async => sleeps.add(d),
      ),
      sleeps,
      started,
    );
  }

  test('Pause vor jedem Fall außer dem ersten', () async {
    final (r, sleeps, _) = runner([
      () => [ScriptedTurn.text('Zehn Uhr.')],
    ], pause: const Duration(seconds: 3));
    await r.runAll([_case('a'), _case('b'), _case('c')]);
    expect(sleeps, [const Duration(seconds: 3), const Duration(seconds: 3)]);
  });

  test(
    'Rate-Limit: eine Wiederholung, Kosten beider Versuche, retried',
    () async {
      final budget = CostBudget(1);
      var n = 0;
      final (r, sleeps, _) = runner(
        [
          () => n++ == 0 ? _limited() : [ScriptedTurn.text('Zehn Uhr.')],
        ],
        retry: const Duration(seconds: 30),
        budget: budget,
      );
      final res = (await r.runAll([_case('a')])).single;
      expect(sleeps, [const Duration(seconds: 30)]);
      expect(res.status, CaseStatus.passed, reason: '${res.reasons}');
      final o = res.observation;
      expect(o.retried, isTrue);
      expect(o.costMicros, 400);
      expect(o.modelCalls, 2);
      expect(budget.spentMicros, 400);
      expect(res.toJson()['retried'], isTrue);
    },
  );

  test('zweiter Versuch ebenfalls Rate-Limit: kein dritter Versuch', () async {
    final (r, sleeps, started) = runner([
      _limited,
    ], retry: const Duration(seconds: 30));
    final res = (await r.runAll([_case('a')])).single;
    expect(started, hasLength(2));
    expect(sleeps, hasLength(1));
    expect(res.status, CaseStatus.error);
    expect(res.observation.retried, isTrue);
    expect(res.observation.costMicros, 400);
  });

  test('ohne --retry-rate-limit keine Wiederholung', () async {
    final (r, sleeps, started) = runner([_limited]);
    final res = (await r.runAll([_case('a')])).single;
    expect(started, hasLength(1));
    expect(sleeps, isEmpty);
    expect(res.observation.retried, isFalse);
    expect(res.toJson().containsKey('retried'), isFalse);
  });

  test('anderer Fehler (kein Rate-Limit): keine Wiederholung', () async {
    final (r, sleeps, started) = runner([
      () => [ScriptedTurn.error(const AuthException('nein'))],
    ], retry: const Duration(seconds: 30));
    await r.runAll([_case('a')]);
    expect(started, hasLength(1));
    expect(sleeps, isEmpty);
  });

  test(
    'mehr als maxRateLimited Fälle bleiben limitiert: Rest übersprungen',
    () async {
      final (r, _, _) = runner(
        [_limited],
        retry: const Duration(seconds: 1),
        maxRateLimited: 1,
      );
      final res = await r.runAll([
        _case('a'),
        _case('b'),
        _case('c'),
        _case('d'),
      ]);
      expect(
        [for (final x in res) x.status],
        [
          CaseStatus.error,
          CaseStatus.error,
          CaseStatus.skipped,
          CaseStatus.skipped,
        ],
      );
      expect(res.last.reasons, ['rate-limit']);
    },
  );
}
