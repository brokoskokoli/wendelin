// Ratsche für `// ignore:` und `// ignore_for_file:` (WP109): je Regel ein
// Budget in `tool/ignore_budget.yaml`. Neue Regel oder mehr Treffer sind rot,
// weniger ebenfalls (Budget senken). Erzeugter Code ist ausgenommen.
//
//   dart run tool/check_ignores.dart                    prüfen
//   dart run tool/check_ignores.dart --update-baseline  senkt/entfernt, erhöht nie
import 'dart:io';

import 'src/ignore_scan.dart';
import 'src/ratchet.dart';

const budgetPath = 'tool/ignore_budget.yaml';

void main(List<String> args) {
  final current = scanIgnores();
  final file = File(budgetPath);
  final text = file.existsSync() ? file.readAsStringSync() : '';
  final budget = parseBaseline(text);
  final errors = ratchetErrors(
    current,
    budget,
    what: 'ignore-Budget',
    file: budgetPath,
    fix: 'dart run tool/check_ignores.dart --update-baseline',
  );
  if (args.contains('--update-baseline')) {
    final lowered = lowerBaseline(current, budget);
    file.writeAsStringSync(renderBaseline(headerOf(text), lowered));
    stdout.writeln(
      'check_ignores: Budget ${budget.length} -> ${lowered.length} Einträge '
      '(nur gesenkt/entfernt).',
    );
    errors.removeWhere((e) => e.contains('senken') || e.contains('entfernen'));
  }
  if (errors.isEmpty) {
    final n = current.values.fold(0, (a, b) => a + b);
    stdout.writeln(
      'check_ignores: ok ($n ignore-Kommentare, ${budget.length} Regeln)',
    );
    return;
  }
  errors.forEach(stderr.writeln);
  stderr.writeln('check_ignores: ROT (${errors.length})');
  exitCode = 1;
}
