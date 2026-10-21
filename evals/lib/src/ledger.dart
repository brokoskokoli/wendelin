import 'dart:convert';
import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';

import 'budget.dart';
import 'summary.dart';

/// One run in the cost ledger (`--ledger`). Holds no keys or headers.
final class LedgerEntry {
  /// Creates an entry.
  const LedgerEntry({
    required this.provider,
    required this.providerType,
    required this.model,
    required this.cases,
    required this.costUsd,
    required this.date,
    this.budgetGroup,
    this.unpricedCases = 0,
    this.budgetExceeded = false,
  });

  /// Reads an entry; throws [FormatException].
  factory LedgerEntry.fromJson(Object? v) {
    if (v is! Map<String, Object?> ||
        v['provider'] is! String ||
        v['model'] is! String ||
        v['cases'] is! int ||
        v['costUsd'] is! num ||
        v['date'] is! String) {
      throw const FormatException('Ledger: ungültiger Eintrag');
    }
    return LedgerEntry(
      provider: v['provider']! as String,
      providerType: v['providerType'] as String? ?? '',
      model: v['model']! as String,
      cases: v['cases']! as int,
      costUsd: (v['costUsd']! as num).toDouble(),
      date: v['date']! as String,
      budgetGroup: v['budgetGroup'] as String?,
      unpricedCases: v['unpricedCases'] as int? ?? 0,
      budgetExceeded: v['budgetExceeded'] == true,
    );
  }

  /// Profile id (the provider of the run).
  final String provider;

  /// Provider type (`anthropic`, `openaiCompatible` …).
  final String providerType;

  /// Group of `--provider-cap` (billing account, e.g. `anthropic`), if any.
  final String? budgetGroup;

  /// Model id.
  final String model;

  /// Cases (incl. repetitions) that ran.
  final int cases;

  /// Cost in USD.
  final double costUsd;

  /// Date of the run (`YYYY-MM-DD`).
  final String date;

  /// Cases without a known price (cost incomplete).
  final int unpricedCases;

  /// Whether `--max-cost` stopped the run.
  final bool budgetExceeded;

  /// JSON of the entry.
  Map<String, Object?> toJson() => {
    'provider': provider,
    'providerType': providerType,
    'model': model,
    'cases': cases,
    'costUsd': costUsd,
    'date': date,
    'budgetGroup': ?budgetGroup,
    if (unpricedCases > 0) 'unpricedCases': unpricedCases,
    if (budgetExceeded) 'budgetExceeded': true,
  };
}

/// Cost in micro-USD to book for a run: the higher of the report sum and
/// what the [budget] counted. If a case aborts with an exception after model
/// calls, its observation (and cost) is lost, but the budget still counted
/// the calls.
int ledgerCostMicros(Summary summary, CostBudget? budget) {
  final counted = budget?.spentMicros ?? 0;
  return counted > summary.costMicros ? counted : summary.costMicros;
}

/// The ledger entry of one finished run of [p] (booked cost: see
/// [ledgerCostMicros]).
LedgerEntry ledgerEntryOf(
  ProviderProfile p,
  String? budgetGroup,
  Summary summary,
  CostBudget? budget,
  DateTime now,
) => LedgerEntry(
  provider: p.id,
  providerType: p.type.name,
  budgetGroup: budgetGroup,
  model: p.defaultModel,
  cases: summary.total,
  costUsd: ledgerCostMicros(summary, budget) / 1e6,
  unpricedCases: summary.unpricedCases,
  budgetExceeded: budget?.exceeded ?? false,
  date: _date(now),
);

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Cost in USD already booked for the budget [group] in [entries] (all
/// profiles of one billing account together).
double groupSpentUsd(List<LedgerEntry> entries, String group) => entries
    .where((e) => e.budgetGroup == group)
    .fold(0.0, (sum, e) => sum + e.costUsd);

/// Reads the ledger [file] (missing = empty); throws [FormatException] if it
/// is not a valid ledger, so a broken file is never overwritten.
List<LedgerEntry> readLedger(File file) {
  if (!file.existsSync()) return [];
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw FormatException('Ledger ist kein gültiges JSON: ${e.message}');
  }
  if (decoded is! List) {
    throw const FormatException('Ledger: Liste erwartet');
  }
  return [for (final e in decoded) LedgerEntry.fromJson(e)];
}

/// Appends [entry] to the ledger [file].
void appendLedger(File file, LedgerEntry entry) {
  final entries = [...readLedger(file), entry];
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert([for (final e in entries) e.toJson()])}\n',
  );
}

/// Text table: runs and cost per provider, then the total.
String renderLedgerSummary(List<LedgerEntry> entries) {
  final byProvider = <String, (int, int, double)>{};
  for (final e in entries) {
    final (runs, cases, cost) = byProvider[e.provider] ?? (0, 0, 0.0);
    byProvider[e.provider] = (runs + 1, cases + e.cases, cost + e.costUsd);
  }
  final names = byProvider.keys.toList()..sort();
  final w = names.fold(8, (m, n) => n.length > m ? n.length : m);
  final b = StringBuffer()
    ..writeln('${'Anbieter'.padRight(w)}  Läufe  Fälle   Kosten \$');
  var total = 0.0;
  for (final n in names) {
    final (runs, cases, cost) = byProvider[n]!;
    total += cost;
    b.writeln(
      '${n.padRight(w)}  ${'$runs'.padLeft(5)}  ${'$cases'.padLeft(5)}  '
      '${cost.toStringAsFixed(4).padLeft(9)}',
    );
  }
  b.writeln(
    '${'gesamt'.padRight(w)}  ${' ' * 13}${total.toStringAsFixed(4).padLeft(9)}',
  );
  return b.toString();
}
