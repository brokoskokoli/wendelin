import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

/// M3 cases (WP29): Bring!, HTTP tool and MCP in de/fr/en, answered by the
/// scripted fake provider against fake backends.
void main() {
  final cases = loadCases(Directory('cases-m3'));

  test('Fälle je Sprache und je Backend', () {
    for (final l in ['de', 'fr', 'en']) {
      expect(cases.where((c) => c.language == l), hasLength(4), reason: l);
    }
    for (final b in caseBackends) {
      expect(
        cases.where((c) => c.setup.backends.contains(b)),
        hasLength(greaterThanOrEqualTo(3)),
        reason: b,
      );
    }
    expect(
      cases.any((c) => c.expect.confirmed == true),
      isTrue,
      reason: 'destruktiver MCP-Aufruf wird bestätigt',
    );
  });

  test('alle Fälle bestehen mit dem Fake-Skript', () async {
    final out = StringBuffer();
    final code = await runCli(
      ['-p', 'profiles/fake-m3.json', '--cases-dir', 'cases-m3'],
      env: const {},
      out: out,
      err: out,
    );
    expect(code, 0, reason: '$out');
    expect(out.toString(), contains('gesamt     12/12'));
  });

  test('Routing-Tabelle: jede Regel greift wie erwartet', () {
    final outcomes = runRoutingTable();
    expect(outcomes.length, greaterThan(15));
    expect(
      outcomes.where((o) => !o.ok).map((o) => o.row.text),
      isEmpty,
      reason: formatRoutingTable(outcomes),
    );
    final out = StringBuffer();
    expect(
      runCli(['--routing-table'], env: const {}, out: out, err: out),
      completion(0),
    );
  });

  test('Routing-Tabelle: eine falsche Zeile wird als FALSCH gemeldet', () {
    final outcomes = runRoutingTable(const [
      RoutingRow('Wie spät ist es?', 'Starkes Modell'),
      RoutingRow('Claude, wie spät ist es?', 'Starkes Modell'),
    ]);
    expect(outcomes.map((o) => o.ok), [false, true]);
    expect(formatRoutingTable(outcomes), contains('FALSCH'));
    expect(formatRoutingTable(outcomes), contains('1/2 wie erwartet'));
  });
}
