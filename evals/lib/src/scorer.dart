import 'case_result.dart';
import 'eval_case.dart';
import 'eval_time.dart';
import 'predicates.dart';

/// Compares what the agent did with what a case expects.
final class Scorer {
  /// Creates a scorer for the run's fixed [time].
  const Scorer(this.time);

  /// „Now“ of the run, for relative date predicates.
  final EvalTime time;

  /// Scores [o] against [c]: `passed` without reasons, `failed` with the
  /// unmet expectations, `error` if the agent run failed.
  CaseResult score(EvalCase c, RunObservation o) {
    if (o.failure case final f?) {
      return CaseResult(
        evalCase: c,
        status: CaseStatus.error,
        reasons: ['Agent abgebrochen (${f.error.name}): ${f.message}'],
        observation: o,
      );
    }
    final reasons = check(c.expect, o);
    return CaseResult(
      evalCase: c,
      status: reasons.isEmpty ? CaseStatus.passed : CaseStatus.failed,
      reasons: reasons,
      observation: o,
    );
  }

  /// The unmet parts of [e] (empty = all met).
  List<String> check(Expectation e, RunObservation o) {
    final reasons = <String>[];
    final names = o.calls.map((c) => c.name).toList();
    if (e.noTools && names.isNotEmpty) {
      reasons.add('Kein Tool erwartet, aufgerufen: ${names.join(', ')}');
    }
    for (final expected in e.calls) {
      final why = _unmet(expected, o.calls);
      if (why != null) reasons.add(why);
    }
    for (final f in e.forbid) {
      if (names.contains(f)) reasons.add('Verbotenes Tool aufgerufen: $f');
    }
    if (e.exact) {
      final allowed = e.calls.expand((x) => x.toolNames).toSet();
      final extra = names.where((n) => !allowed.contains(n)).toSet();
      if (extra.isNotEmpty) {
        reasons.add('Zusätzliche Tools aufgerufen: ${extra.join(', ')}');
      }
    }
    if (e.text case final p?) {
      final why = p.check(o.finalText, time);
      if (why != null) reasons.add('Antwort: $why');
    }
    switch (e.confirmed) {
      case true when o.confirmations == 0:
        reasons.add('Bestätigung erwartet, aber nicht angefragt');
      case false when o.confirmations > 0:
        reasons.add('Unerwartete Bestätigung angefragt');
      case _:
        break;
    }
    return reasons;
  }

  /// `null` if some call satisfies [e]; otherwise the closest miss.
  String? _unmet(CallExpectation e, List<ObservedCall> calls) {
    final misses = <String>[];
    for (final option in e.options) {
      for (final call in calls.where((c) => option.tools.contains(c.name))) {
        final why = argumentProblems(option.args, call);
        if (why.isEmpty && (!call.isError || !option.succeeded)) return null;
        misses.add(
          '${call.name}: '
          '${why.isEmpty ? 'Tool meldete Fehler' : why.join('; ')}'
          '${why.isNotEmpty && call.isError ? ' (Tool meldete Fehler)' : ''}',
        );
      }
    }
    if (misses.isNotEmpty) {
      return 'Kein passender erfolgreicher Aufruf für ${e.describe()} – '
          '${misses.join(' | ')}';
    }
    final made = calls.isEmpty ? 'keine' : calls.map((c) => c.name).join(', ');
    return 'Nicht aufgerufen: ${e.describe()} (aufgerufen: $made)';
  }

  /// Problems of [call]'s arguments against [args] (empty = all fine).
  List<String> argumentProblems(
    Map<String, ValuePredicate> args,
    ObservedCall call,
  ) {
    final decoded = call.args;
    if (decoded == null) {
      return args.isEmpty ? const [] : ['ungültiges Argument-JSON'];
    }
    final problems = <String>[];
    for (final MapEntry(key: path, value: p) in args.entries) {
      final (found, value) = lookupPath(decoded, path);
      final why = p.check(value, time, present: found);
      if (why != null) problems.add('$path $why');
    }
    return problems;
  }
}

/// Looks up a dotted [path] in [map]; returns whether it exists and the
/// value.
(bool, Object?) lookupPath(Map<String, Object?> map, String path) {
  Object? current = map;
  for (final key in path.split('.')) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return (false, null);
    }
  }
  return (true, current);
}
