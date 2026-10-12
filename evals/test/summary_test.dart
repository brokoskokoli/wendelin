import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

EvalCase _c(String id, String lang) => EvalCase(
  id: id,
  language: lang,
  prompt: 'p',
  expect: const Expectation(noTools: true),
);

CaseResult _r(
  String id,
  String lang,
  CaseStatus status, {
  int ms = 0,
  int? cost = 10,
  bool gaveUp = false,
  bool escalated = false,
}) => CaseResult(
  evalCase: _c(id, lang),
  status: status,
  observation: RunObservation(
    latency: Duration(milliseconds: ms),
    completed: true,
    usage: const Usage(
      inputTokens: 100,
      outputTokens: 10,
      cachedInputTokens: 5,
      cacheWriteTokens: 1,
    ),
    costMicros: cost,
    gaveUp: gaveUp,
    escalations: escalated
        ? [(to: 'x', reason: EscalationReason.modelGaveUp)]
        : const [],
  ),
);

void main() {
  group('percentile (nearest rank)', () {
    List<Duration> ms(List<int> v) => [
      for (final x in v) Duration(milliseconds: x),
    ];
    test('Tabelle', () {
      expect(percentile(const [], 50), isNull);
      expect(percentile(ms([7]), 50), const Duration(milliseconds: 7));
      expect(percentile(ms([4, 1, 3, 2]), 50), const Duration(milliseconds: 2));
      expect(
        percentile(ms([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 50),
        const Duration(milliseconds: 5),
      );
      expect(
        percentile(ms([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 90),
        const Duration(milliseconds: 9),
      );
      expect(
        percentile(ms([10, 1, 2, 3, 4, 5, 6, 7, 8, 9]), 100),
        const Duration(milliseconds: 10),
      );
      expect(percentile(ms([1, 2, 3]), 90), const Duration(milliseconds: 3));
    });
    test('ungültiges p', () {
      expect(() => percentile(ms([1]), 0), throwsArgumentError);
      expect(() => percentile(ms([1]), 101), throwsArgumentError);
    });
  });

  test('Summary.of zählt, summiert und lässt Übersprungene aus', () {
    final results = [
      _r('a', 'de', CaseStatus.passed, ms: 100),
      _r('b', 'de', CaseStatus.failed, ms: 300, gaveUp: true, escalated: true),
      _r('c', 'fr', CaseStatus.error, ms: 200, cost: null),
      _r('d', 'fr', CaseStatus.passed, ms: 400),
      CaseResult.skipped(_c('e', 'de'), 'pending'),
    ];
    final s = Summary.of(results);
    expect((s.total, s.passed, s.failed, s.errors, s.skipped), (4, 2, 1, 1, 1));
    expect(s.passRate, 0.5);
    expect(s.latencyP50, const Duration(milliseconds: 200));
    expect(s.latencyP90, const Duration(milliseconds: 400));
    expect(s.usage.inputTokens, 400);
    expect(s.usage.totalTokens, 4 * 116);
    expect((s.costMicros, s.unpricedCases), (30, 1));
    expect((s.gaveUp, s.escalated), (1, 1));
    final json = s.toJson();
    expect(json['passRate'], 0.5);
    expect(json['latencyMs'], {'p50': 200, 'p90': 400});
    expect((json['usage']! as Map)['total'], 464);
    expect(json['costUsd'], 0.00003);

    final byLang = summariesByLanguage(results);
    expect(byLang.keys, ['de', 'fr']);
    expect(
      (byLang['de']!.total, byLang['de']!.passed, byLang['de']!.skipped),
      (2, 1, 1),
    );
    expect(byLang['fr']!.passRate, 0.5);
  });

  test('Perzentil mit gebrochenem Rang (Review #3)', () {
    final seven = [for (var i = 1; i <= 7; i++) Duration(milliseconds: i)];
    // p90: Rang ceil(6,3) = 7, p50: Rang ceil(3,5) = 4.
    expect(percentile(seven, 90), const Duration(milliseconds: 7));
    expect(percentile(seven, 50), const Duration(milliseconds: 4));
  });

  test('Latenz nur über Fälle, die wirklich liefen (Review #9)', () {
    final s = Summary.of([
      _r('a', 'de', CaseStatus.passed, ms: 500),
      // Aufbau fehlgeschlagen: zählt als Fall, aber nicht für die Latenz.
      CaseResult(evalCase: _c('b', 'de'), status: CaseStatus.error),
    ]);
    expect(s.total, 2);
    expect(s.latencyP50, const Duration(milliseconds: 500));
  });

  test('Bestätigungen werden summiert (Review #8)', () {
    final s = Summary.of([
      CaseResult(
        evalCase: _c('a', 'de'),
        status: CaseStatus.passed,
        observation: const RunObservation(
          confirmations: 2,
          escalationConfirmations: 1,
        ),
      ),
      CaseResult(
        evalCase: _c('b', 'de'),
        status: CaseStatus.passed,
        observation: const RunObservation(confirmations: 1),
      ),
    ]);
    expect((s.confirmations, s.escalationConfirmations), (3, 1));
    expect(s.toJson()['confirmations'], 3);
    expect(s.toJson()['escalationConfirmations'], 1);
  });

  test('leere Menge', () {
    final s = Summary.of(const []);
    expect((s.total, s.passRate, s.latencyP50), (0, 0.0, null));
    expect((s.toJson()['latencyMs']! as Map)['p50'], isNull);
  });
}
