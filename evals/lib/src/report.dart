import 'dart:convert';

import 'case_result.dart';
import 'summary.dart';

/// Result of an eval run: metadata, per-case results and summaries.
final class EvalReport {
  /// Creates a report.
  EvalReport({required this.meta, required this.results})
    : summary = Summary.of(results),
      byLanguage = summariesByLanguage(results);

  /// Run metadata (profile, model, „now“ …; never secrets).
  final Map<String, Object?> meta;

  /// Per-case results in run order.
  final List<CaseResult> results;

  /// Overall summary.
  final Summary summary;

  /// Summary per language.
  final Map<String, Summary> byLanguage;

  /// JSON for `--out`.
  Map<String, Object?> toJson() => {
    'meta': meta,
    'summary': summary.toJson(),
    'byLanguage': {for (final e in byLanguage.entries) e.key: e.value.toJson()},
    'cases': [for (final r in results) r.toJson()],
  };

  /// Pretty-printed JSON.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Plain-text table: one line per case, then the summaries.
  String renderTable() {
    final b = StringBuffer();
    final idWidth = results.fold(
      4,
      (w, r) => r.evalCase.id.length > w ? r.evalCase.id.length : w,
    );
    b.writeln(
      '${'Fall'.padRight(idWidth)}  Status   ms      Tokens  Kosten µ\$  Hinweis',
    );
    for (final r in results) {
      final o = r.observation;
      final flags = [
        if (o.gaveUp) 'aufgegeben',
        if (o.escalations.isNotEmpty)
          'eskaliert(${o.escalations.map((e) => e.reason.name).join(',')})',
        if (r.reasons.isNotEmpty) r.reasons.first,
      ].join('; ');
      b.writeln(
        [
          r.evalCase.id.padRight(idWidth),
          _status(r.status).padRight(7),
          (r.ran ? '${o.latency.inMilliseconds}' : '-').padLeft(6),
          (r.ran ? '${o.usage.totalTokens}' : '-').padLeft(9),
          (r.ran ? (o.costMicros?.toString() ?? '?') : '-').padLeft(10),
          ' ${_short(flags)}',
        ].join(' '),
      );
    }
    b
      ..writeln()
      ..writeln(
        'Sprache  Treffer        Quote   p50 ms  p90 ms     Tokens    Kosten \$'
        '  aufgegeben  eskaliert  bestätigt',
      );
    for (final e in [...byLanguage.entries, MapEntry('gesamt', summary)]) {
      final s = e.value;
      b.writeln(
        [
          e.key.padRight(7),
          '${s.passed}/${s.total}'.padLeft(8),
          '${(s.passRate * 100).toStringAsFixed(1)} %'.padLeft(12),
          '${s.latencyP50?.inMilliseconds ?? '-'}'.padLeft(8),
          '${s.latencyP90?.inMilliseconds ?? '-'}'.padLeft(7),
          '${s.usage.totalTokens}'.padLeft(10),
          '${(s.costMicros / 1e6).toStringAsFixed(4)}'
                  '${s.unpricedCases > 0 ? '+?' : '  '}'
              .padLeft(11),
          '${s.gaveUp}'.padLeft(11),
          '${s.escalated}'.padLeft(10),
          '${s.confirmations}'
                  '${s.escalationConfirmations > 0 ? '+${s.escalationConfirmations}E' : ''}'
              .padLeft(10),
        ].join(' '),
      );
    }
    if (summary.skipped > 0) {
      b.writeln('Übersprungen: ${summary.skipped}');
    }
    return b.toString();
  }

  static String _status(CaseStatus s) => switch (s) {
    CaseStatus.passed => 'ok',
    CaseStatus.failed => 'FEHL',
    CaseStatus.error => 'ABBRUCH',
    CaseStatus.skipped => 'skip',
  };

  static String _short(String s) =>
      s.length <= 100 ? s : '${s.substring(0, 97)}...';
}
