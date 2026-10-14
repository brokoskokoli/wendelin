import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  test('die zehn Prüf-Paare sind gültig: fünf passend, fünf manipuliert', () {
    final cases = loadCheckCases(File('spoken-check/cases.yaml'));
    expect(cases, hasLength(10));
    expect(cases.where((c) => c.match), hasLength(5));
    expect(cases.map((c) => c.language).toSet(), {'de', 'fr', 'en'});
  });

  test('lokal erkennbare Manipulationen fängt die Vorprüfung', () {
    for (final c in loadCheckCases(File('spoken-check/cases.yaml'))) {
      final local = SpokenPrecheck.mismatch(c.spoken, c.written);
      expect(local != null, c.local, reason: c.id);
      if (c.match) expect(local, isNull, reason: c.id);
    }
  });

  test('Eval offline: Trefferquoten und Kosten', () async {
    final cases = loadCheckCases(File('spoken-check/cases.yaml'));
    final provider = FakeLlmProvider([
      for (final c in cases)
        ScriptedTurn.text('{"match": ${c.match}, "reason": "x"}'),
    ]);
    final runs = await runSpokenCheckEval(
      provider: provider,
      model: 'm',
      cases: cases,
      profileId: 'p',
      costEstimator: const FlatCostEstimator(),
    );
    final s = summarizeSpokenCheck(runs);
    expect(s['matchingAccepted'], '5/5');
    expect(s['manipulatedRejected'], '5/5');
    expect(s['costMicros'], isNotNull);
    // The check request carries only the two texts.
    expect(provider.requests.first.tools, isEmpty);
  });
}
