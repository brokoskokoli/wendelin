// WP57: wertet Eval-Reports (evals/reports/*.json) nach Sprache und
// einfach/komplex aus. Aufruf: dart run tool/local_llm_report.dart <report>...
import 'dart:convert';
import 'dart:io';

/// Komplex: Bestätigung (Löschen), Web, Verschieben, freie Zeiten,
/// Wiederholungen, ganztägig. Alles andere ist einfach.
final _complex = RegExp(
  r'(cal-loeschen|cal-delete|cal-supprimer|web-|cal-verschieben|cal-frei|'
  r'alarm-mo-mi-fr|cal-ganztag)',
);

typedef _Case = Map<String, dynamic>;

String _pct(int p, int n) => n == 0 ? '-' : '$p/$n (${(100 * p / n).round()}%)';

List<String> _reasons(_Case c) =>
    ((c['reasons'] as List<dynamic>?) ?? <dynamic>[]).cast<String>();

int _tokens(_Case c) {
  final u = c['usage'] as Map<String, dynamic>;
  return ((u['input'] ?? 0) as int) + ((u['cacheRead'] ?? 0) as int);
}

void main(List<String> files) {
  for (final f in files) {
    final d = jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>;
    final cases = (d['cases'] as List<dynamic>)
        .cast<_Case>()
        .where((c) => c['status'] != 'skipped')
        .toList();
    bool isComplex(_Case c) => _complex.hasMatch(c['id'] as String);
    final groups = <String, List<_Case>>{
      'gesamt': cases,
      'einfach': cases.where((c) => !isComplex(c)).toList(),
      'komplex': cases.where(isComplex).toList(),
      for (final l in ['de', 'fr', 'en'])
        l: cases.where((c) => c['language'] == l).toList(),
    };
    final lat = cases.map((c) => (c['latencyMs'] as num).toInt()).toList()
      ..sort();
    // „Behauptet ohne Tool“: Erwartung verlangt einen Aufruf, keiner erfolgte.
    final noCall = cases.where(
      (c) =>
          c['status'] != 'passed' &&
          ((c['toolCalls'] as List<dynamic>?) ?? <dynamic>[]).isEmpty &&
          _reasons(c).any((r) => r.startsWith('Nicht aufgerufen')),
    );
    final extra = cases.where(
      (c) => _reasons(c).any((r) => r.startsWith('Kein Tool erwartet')),
    );
    final inTok = cases.fold<int>(0, (s, c) => s + _tokens(c));
    final model = (d['meta'] as Map<String, dynamic>)['model'];
    final quotes = groups.entries
        .map(
          (e) =>
              '${e.key} ${_pct(e.value.where((c) => c['status'] == 'passed').length, e.value.length)}',
        )
        .join(' | ');
    stdout.writeln('$model: $quotes');
    stdout.writeln(
      '  Latenz p50 ${lat[lat.length ~/ 2]} ms, '
      'p90 ${lat[(lat.length * 0.9).floor()]} ms; '
      'ohne Tool trotz Erwartung: ${noCall.length}; '
      'unerwartetes Tool: ${extra.length}; '
      'Eingabetokens/Fall ${inTok ~/ cases.length}',
    );
  }
}
