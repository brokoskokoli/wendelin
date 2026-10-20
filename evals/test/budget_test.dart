import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
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

void main() {
  final time = EvalTime.parse('2026-10-14T09:00', defaultTimeZone);

  // FlatCostEstimator: 200 µUSD je Modellaufruf.
  (EvalRunner, List<FakeLlmProvider>) runner(
    List<ScriptedTurn> Function() turns, {
    CostBudget? budget,
    CostEstimator? estimator = const FlatCostEstimator(),
  }) {
    final providers = <FakeLlmProvider>[];
    return (
      EvalRunner(
        target: EvalTarget(
          profileId: 'fake',
          modelId: 'fake-model',
          privacy: PrivacyLevel.local,
          provider: (_) {
            final p = FakeLlmProvider(turns());
            providers.add(p);
            return p;
          },
          costEstimator: estimator,
        ),
        time: time,
        budget: budget,
      ),
      providers,
    );
  }

  group('CostBudget', () {
    test('erreicht heißt: Grenze gilt bei spent >= limit', () {
      final b = CostBudget(0.001); // 1000 µUSD
      expect(b.record(999), isTrue);
      expect(b.exceeded, isFalse);
      expect(b.record(1), isFalse);
      expect(b.exceeded, isTrue);
      expect(b.spentMicros, 1000);
    });

    test('unbekannter Preis stoppt (fail-closed)', () {
      final b = CostBudget(1);
      expect(b.record(null), isFalse);
      expect(b.stopReason, contains('unbekannt'));
    });

    test('Grenze muss positiv sein', () {
      expect(() => CostBudget(0), throwsArgumentError);
      expect(() => CostBudget(-1), throwsArgumentError);
      expect(() => CostBudget(double.nan), throwsArgumentError);
    });
  });

  group('Runner', () {
    test('Abbruch zwischen Fällen: Rest wird übersprungen (budget)', () async {
      final (r, _) = runner(
        () => [ScriptedTurn.text('Ja.')],
        budget: CostBudget(0.0004), // 400 µUSD = zwei Aufrufe
      );
      final results = await r.runAll([_case('a'), _case('b'), _case('c')]);
      expect(results[0].status, CaseStatus.passed);
      expect(results[1].status, CaseStatus.error);
      expect(results[1].reasons.single, startsWith('budget:'));
      expect(results[2].status, CaseStatus.skipped);
      expect(results[2].reasons, ['budget']);
      expect(results[1].observation.costMicros, 200);
    });

    test('Abbruch mitten im Fall: kein weiterer Modellaufruf', () async {
      final (r, providers) = runner(
        () => [
          ScriptedTurn.toolCalls([
            ToolCallBlock(
              id: 'c1',
              name: 'clipboard__read',
              argumentsJson: jsonEncode(<String, Object?>{}),
            ),
          ]),
          ScriptedTurn.toolCalls([
            ToolCallBlock(
              id: 'c2',
              name: 'clipboard__read',
              argumentsJson: jsonEncode(<String, Object?>{}),
            ),
          ]),
          ScriptedTurn.text('Fertig.'),
        ],
        budget: CostBudget(0.0004), // nach dem 2. Aufruf erreicht
      );
      final result = await r.runCase(_case('mid'));
      expect(result.status, CaseStatus.error);
      expect(result.reasons.single, contains('Kostengrenze'));
      expect(providers.single.requests, hasLength(2));
      expect(result.observation.modelCalls, 2);
    });

    test('ohne Budget läuft derselbe Fall bis zum Ende', () async {
      final (r, providers) = runner(() => [ScriptedTurn.text('Ja.')]);
      final results = await r.runAll([_case('a'), _case('b'), _case('c')]);
      expect(results.map((x) => x.status), everyElement(CaseStatus.passed));
      expect(providers, hasLength(3));
    });

    test('Preis eines Aufrufs unbekannt: Abbruch', () async {
      final (r, _) = runner(
        () => [ScriptedTurn.text('Ja.')],
        budget: CostBudget(100),
        estimator: null,
      );
      final results = await r.runAll([_case('a'), _case('b')]);
      expect(results[0].status, CaseStatus.error);
      expect(results[1].reasons, ['budget']);
    });

    test('repeat: jeder Fall n-mal, Wiederholungen unterscheidbar', () async {
      final (r, _) = runner(() => [ScriptedTurn.text('Ja.')]);
      final results = await r.runAll([_case('a'), _case('b')], repeat: 2);
      expect(results.map((x) => '${x.evalCase.id}#${x.repetition}'), [
        'a#1',
        'a#2',
        'b#1',
        'b#2',
      ]);
      final report = EvalReport(meta: const {}, results: results);
      final cases = (report.toJson()['cases']! as List)
          .cast<Map<String, Object?>>();
      expect(cases.map((c) => c['repetition']), [1, 2, 1, 2]);
      expect(report.renderTable(), contains('a#2'));
    });

    test('repeat 1: keine Wiederholungsnummer im Report', () async {
      final (r, _) = runner(() => [ScriptedTurn.text('Ja.')]);
      final results = await r.runAll([_case('a')]);
      expect(results.single.toJson().containsKey('repetition'), isFalse);
    });
  });

  group('Wilson', () {
    test('bekannte Werte', () {
      final w = wilson95(8, 10);
      expect(w[0], closeTo(0.4902, 1e-3));
      expect(w[1], closeTo(0.9433, 1e-3));
      final all = wilson95(10, 10);
      expect(all[0], closeTo(0.7225, 1e-3));
      expect(all[1], closeTo(1.0, 1e-9));
      final none = wilson95(0, 10);
      expect(none[0], closeTo(0.0, 1e-9));
      expect(none[1], closeTo(0.2775, 1e-3));
      expect(wilson95(0, 0), [0, 1]);
    });

    test('Report enthält das Intervall', () async {
      final (r, _) = runner(() => [ScriptedTurn.text('Ja.')]);
      final report = EvalReport(
        meta: const {},
        results: await r.runAll([_case('a')]),
      );
      expect(
        report.toJson()['summary'],
        containsPair('passRateWilson95', [closeTo(0.2065, 1e-3), 1.0]),
      );
      expect(report.renderTable(), contains('Wilson-95-%'));
    });
  });

  group('CLI', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('evals_budget'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<(int, String, String)> run(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        args,
        env: const {},
        out: out,
        err: err,
        today: () => DateTime(2026, 10, 21),
      );
      return (code, '$out', '$err');
    }

    final base = ['-p', 'profiles/fake-demo.json', '--cases', 'de'];

    test(
      '--max-cost bricht ab: Exit 2, Teilreport mit budgetExceeded',
      () async {
        final path = '${tmp.path}/r.json';
        final (code, _, err) = await run([
          ...base,
          '--max-cost',
          '0.0002',
          '--out',
          path,
        ]);
        expect(code, 2);
        expect(err, contains('Kostengrenze'));
        final report =
            jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
        final meta = report['meta']! as Map<String, Object?>;
        expect(meta['budgetExceeded'], isTrue);
        final summary = report['summary']! as Map<String, Object?>;
        expect(summary['errors'], 1);
        expect(summary['skipped'], greaterThan(10));
      },
    );

    test('--max-cost ohne Preis für das Modell: Start verweigert', () async {
      final (code, out, err) = await run([
        ...base,
        '--max-cost',
        '1',
        '--model',
        'unbekanntes-modell',
      ]);
      expect(code, 1);
      expect(err, contains('Start verweigert'));
      expect(out, isNot(contains('Profil ')));
    });

    test('ungültige --max-cost / --repeat Werte', () async {
      expect((await run([...base, '--max-cost', 'abc'])).$1, 64);
      expect((await run([...base, '--max-cost', '0'])).$1, 64);
      expect((await run([...base, '--repeat', '0'])).$1, 64);
    });

    test('--repeat 2 verdoppelt die Läufe', () async {
      final path = '${tmp.path}/r.json';
      final (code, _, err) = await run([
        ...base,
        '--cases',
        'tauchen',
        '--repeat',
        '2',
        '--out',
        path,
      ]);
      expect(code, 0, reason: err);
      final report =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      expect((report['meta']! as Map)['repeat'], 2);
      final cases = (report['cases']! as List).cast<Map<String, Object?>>();
      expect(cases.map((c) => c['repetition']).toSet(), {1, 2});
    });

    test('--ledger hängt Läufe an, Summe je Anbieter, keine Keys', () async {
      final ledger = '${tmp.path}/l/ledger.json';
      final report = '${tmp.path}/r.json';
      for (var i = 0; i < 2; i++) {
        final (code, _, err) = await run([
          ...base,
          '--cases',
          'tauchen',
          '--ledger',
          ledger,
          '--out',
          report,
        ]);
        expect(code, 0, reason: err);
      }
      final entries = readLedger(File(ledger));
      expect(entries, hasLength(2));
      expect(entries.first.provider, 'fake-demo');
      expect(entries.first.model, 'fake-model');
      expect(entries.first.date, '2026-10-21');
      expect(entries.first.cases, 1);
      expect(entries.first.costUsd, greaterThan(0));
      final (code, out, _) = await run([
        '--ledger',
        ledger,
        '--ledger-summary',
      ]);
      expect(code, 0);
      expect(out, contains('fake-demo'));
      expect(out, contains('gesamt'));
      // Weder Ledger noch Report enthalten Header oder Keys.
      for (final f in [ledger, report]) {
        final text = File(f).readAsStringSync().toLowerCase();
        expect(text, isNot(contains('authorization')));
        expect(text, isNot(contains('bearer')));
        expect(text, isNot(contains('api_key')));
      }
    });

    group('--provider-cap', () {
      File seed(String provider, double usd) {
        final f = File('${tmp.path}/cap.json');
        appendLedger(
          f,
          LedgerEntry(
            provider: provider,
            providerType: 'fake',
            model: 'm',
            cases: 1,
            costUsd: usd,
            date: '2026-10-20',
          ),
        );
        return f;
      }

      test('ohne --ledger oder mit ungültigem Wert: Exit 64', () async {
        expect((await run([...base, '--provider-cap', '1'])).$1, 64);
        final f = seed('fake-demo', 0.1).path;
        for (final bad in ['abc', '0', '-1']) {
          expect(
            (await run([...base, '--ledger', f, '--provider-cap', bad])).$1,
            64,
            reason: bad,
          );
        }
      });

      test(
        'ausgeschöpfte Obergrenze: Start verweigert, Ledger bleibt',
        () async {
          final f = seed('fake-demo', 1.0);
          final before = f.readAsStringSync();
          final (code, out, err) = await run([
            ...base,
            '--ledger',
            f.path,
            '--provider-cap',
            '1.0',
          ]);
          expect(code, 1);
          expect(err, contains('Start verweigert'));
          expect(out, isNot(contains('Profil ')));
          expect(f.readAsStringSync(), before);
        },
      );

      test('Rest = Obergrenze minus Ledger-Summe des Anbieters', () async {
        final f = seed('fake-demo', 0.9998); // Rest 0.0002 USD
        final path = '${tmp.path}/r.json';
        final (code, _, err) = await run([
          ...base,
          '--ledger',
          f.path,
          '--provider-cap',
          '1.0',
          '--out',
          path,
        ]);
        expect(code, 2, reason: err);
        final meta =
            (jsonDecode(File(path).readAsStringSync())
                    as Map<String, Object?>)['meta']!
                as Map<String, Object?>;
        expect(meta['maxCostMicros'], 200);
      });

      test('Kosten anderer Anbieter zählen nicht', () async {
        final f = seed('anderer', 50);
        final (code, _, err) = await run([
          ...base,
          '--cases',
          'tauchen',
          '--ledger',
          f.path,
          '--provider-cap',
          '1.0',
        ]);
        expect(code, 0, reason: err);
      });

      test('--max-cost kleiner als der Rest gilt weiter', () async {
        final f = seed('fake-demo', 0.5);
        final path = '${tmp.path}/r.json';
        await run([
          ...base,
          '--ledger',
          f.path,
          '--provider-cap',
          '1.0',
          '--max-cost',
          '0.0002',
          '--out',
          path,
        ]);
        final meta =
            (jsonDecode(File(path).readAsStringSync())
                    as Map<String, Object?>)['meta']!
                as Map<String, Object?>;
        expect(meta['maxCostMicros'], 200);
      });
    });

    test('kaputtes Ledger: Lauf wird verweigert, Datei bleibt', () async {
      final ledger = File('${tmp.path}/l.json')..writeAsStringSync('{kaputt');
      final (code, _, err) = await run([...base, '--ledger', ledger.path]);
      expect(code, 1);
      expect(err, contains('Ledger'));
      expect(ledger.readAsStringSync(), '{kaputt');
    });
  });

  test('Ledger bucht mindestens, was das Budget gezählt hat', () {
    // Ein Fall brach nach Modellaufrufen mit Ausnahme ab: Beobachtung und
    // Kosten fehlen im Report, das Budget kennt sie.
    final lost = CostBudget(1)..record(500);
    final summary = Summary.of(const []);
    expect(summary.costMicros, 0);
    expect(ledgerCostMicros(summary, lost), 500);
    expect(ledgerCostMicros(summary, null), 0);
    final more = CostBudget(1)..record(5);
    final results = [
      CaseResult(
        evalCase: _case('x'),
        status: CaseStatus.passed,
        observation: const RunObservation(costMicros: 200, completed: true),
      ),
    ];
    expect(ledgerCostMicros(Summary.of(results), more), 200);
  });

  test('Ledger-Summe rechnet je Anbieter', () {
    final text = renderLedgerSummary([
      const LedgerEntry(
        provider: 'a',
        providerType: 't',
        model: 'm',
        cases: 5,
        costUsd: 0.5,
        date: 'd',
      ),
      const LedgerEntry(
        provider: 'a',
        providerType: 't',
        model: 'm2',
        cases: 3,
        costUsd: 0.25,
        date: 'd',
      ),
      const LedgerEntry(
        provider: 'b',
        providerType: 't',
        model: 'm',
        cases: 1,
        costUsd: 1,
        date: 'd',
      ),
    ]);
    expect(text, contains('0.7500'));
    expect(text, contains('1.7500'));
  });
}
