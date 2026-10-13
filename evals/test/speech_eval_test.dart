import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  group('speechIssues', () {
    final table = <(String, String, List<String>)>[
      ('sauberer Satz', 'Du hast heute drei Termine, um zehn Uhr.', []),
      ('Markdown', '**Termine** heute.', ['markdown']),
      (
        'Liste',
        'Heute:\n- Zahnarzt\n- Chor',
        ['markdown', 'doppelpunkt', 'zeilen'],
      ),
      ('Uhrzeit mit Doppelpunkt', 'Um 10:30 Uhr.', ['doppelpunkt']),
      ('Abkürzung', 'Das kostet ca. fünf Euro.', ['abkürzung']),
      ('Emoji und Pfeil', 'Fertig 🎉 → weiter.', ['symbol']),
      ('URL', 'Siehe https://example.org.', ['doppelpunkt', 'url']),
      ('Block-Rest', '<spoken>Hallo.</spoken>', ['tag']),
      ('zu lang', 'Eins. Zwei. Drei. Vier.', ['lang']),
    ];
    for (final (name, text, issues) in table) {
      test(name, () => expect(speechIssues(text), issues));
    }
  });

  test('die zehn Sprach-Befehle sind gültige Fälle', () {
    final cases = loadCases(Directory('speech'));
    expect(cases, hasLength(10));
    expect(cases.map((c) => c.language).toSet(), {'de', 'fr', 'en'});
  });

  test('Sprech-Eval offline: Varianten, Block und Rückfall', () async {
    final time = EvalTime.parse(defaultNow, defaultTimeZone);
    final cases = loadCases(Directory('speech')).take(2).toList();
    // Reply per variant: baseline = markdown list, hint = clean sentence,
    // two = block + written; second command of "two" has no block.
    final answers = <String>[];
    final target = EvalTarget(
      profileId: 'fake',
      modelId: 'fake-model',
      privacy: PrivacyLevel.local,
      provider: (_) =>
          FakeLlmProvider([ScriptedTurn.text(answers.removeAt(0))]),
      costEstimator: const FlatCostEstimator(),
    );
    answers.addAll([
      'Termine:\n- 09:30 Zahnarzt\n- 14:00 Teammeeting',
      'Heute:\n- Joggen',
      'Du hast zwei Termine, um halb zehn und um zwei.',
      'Nur Joggen.',
      '<spoken>Zwei Termine heute.</spoken>\n**Termine**\n- 09:30 Zahnarzt',
      'Nur Joggen, ohne Block: 07:15.',
    ]);
    final runs = await runSpeechEval(target: target, time: time, cases: cases);
    expect(runs, hasLength(6));
    final byVariant = {
      for (final v in SpeechVariant.values)
        v: runs.where((r) => r.variant == v).toList(),
    };
    expect(
      byVariant[SpeechVariant.text]!.every((r) => r.issues.isNotEmpty),
      isTrue,
    );
    expect(
      byVariant[SpeechVariant.hint]!.every((r) => r.issues.isEmpty),
      isTrue,
    );
    final two = byVariant[SpeechVariant.two]!;
    expect(two[0].block, isTrue);
    expect(two[0].spoken, 'Zwei Termine heute.');
    expect(two[0].issues, isEmpty);
    expect(two[1].block, isFalse); // fallback to the written text
    expect(two[1].issues, ['doppelpunkt']);
    final summary = summarizeSpeech(runs);
    expect((summary['two']! as Map)['withBlock'], 1);
    expect((summary['hint']! as Map)['clean'], 2);
  });
}
