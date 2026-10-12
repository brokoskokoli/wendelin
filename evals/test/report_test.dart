import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  EvalCase c(String id, String lang) => EvalCase(
    id: id,
    language: lang,
    prompt: 'p',
    expect: const Expectation(noTools: true),
  );

  final results = [
    CaseResult(
      evalCase: c('de-a', 'de'),
      status: CaseStatus.passed,
      observation: const RunObservation(
        latency: Duration(milliseconds: 120),
        usage: Usage(inputTokens: 100, outputTokens: 20),
        costMicros: 30,
        finalText: 'ok',
      ),
    ),
    CaseResult(
      evalCase: c('fr-b', 'fr'),
      status: CaseStatus.failed,
      reasons: ['x' * 150],
      observation: const RunObservation(
        gaveUp: true,
        escalations: [(to: 's', reason: EscalationReason.modelGaveUp)],
      ),
    ),
    CaseResult(
      evalCase: c('en-c', 'en'),
      status: CaseStatus.error,
      reasons: const ['Abbruch'],
    ),
    CaseResult.skipped(c('de-d', 'de'), 'pending'),
  ];
  final report = EvalReport(meta: const {'model': 'm'}, results: results);

  test('JSON enthält Meta, Summen pro Sprache und Fälle', () {
    final json = jsonDecode(report.encode()) as Map<String, Object?>;
    expect(json['meta'], {'model': 'm'});
    expect((json['summary']! as Map)['total'], 3);
    expect((json['byLanguage']! as Map).keys, ['de', 'en', 'fr']);
    final cases = json['cases']! as List;
    expect(cases, hasLength(4));
    final first = cases.first as Map;
    expect(first['latencyMs'], 120);
    expect(first['usage'], {
      'input': 100,
      'output': 20,
      'cacheRead': 0,
      'cacheWrite': 0,
    });
    expect((cases[1] as Map)['gaveUp'], isTrue);
    expect((cases[1] as Map)['costMicros'], isNull);
  });

  test('Tabelle zeigt Bestätigungen inkl. Eskalation', () {
    final r = EvalReport(
      meta: const {},
      results: [
        CaseResult(
          evalCase: c('de-x', 'de'),
          status: CaseStatus.passed,
          observation: const RunObservation(
            confirmations: 2,
            escalationConfirmations: 1,
            completed: true,
          ),
        ),
      ],
    );
    expect(r.renderTable(), contains('2+1E'));
    expect(
      (r.toJson()['cases']! as List).single,
      containsPair('escalationConfirmations', 1),
    );
  });

  test('Tabelle zeigt Fälle, Hinweise und Summen', () {
    final t = report.renderTable();
    expect(t, contains('de-a'));
    expect(t, contains('ok'));
    expect(t, contains('FEHL'));
    expect(t, contains('ABBRUCH'));
    expect(t, contains('skip'));
    expect(t, contains('aufgegeben; eskaliert(modelGaveUp)'));
    expect(t, contains('...'));
    expect(t, contains('gesamt'));
    expect(t, contains('0.0000+?'));
    expect(t, contains('Übersprungen: 1'));
    expect(RegExp(r'gesamt\s+1/3\s+33\.3 %').hasMatch(t), isTrue, reason: t);
  });
}
