/// Wendelin model evals: eval cases (YAML) with predicates on tool calls
/// and answers, a runner that drives the real agent loop with fake ports,
/// aggregation (pass rate, latency p50/p90, tokens, cost per language) and
/// the CLI behind `dart run wendelin_evals:run`.
library;

export 'src/case_backends.dart';
export 'src/case_result.dart';
export 'src/cli.dart' show buildProvider, defaultNow, defaultTimeZone, runCli;
export 'src/eval_case.dart';
export 'src/eval_profile.dart';
export 'src/eval_runner.dart';
export 'src/eval_time.dart';
export 'src/fake_script.dart';
export 'src/predicates.dart';
export 'src/report.dart';
export 'src/routing_table.dart';
export 'src/scorer.dart';
export 'src/speech_check.dart';
export 'src/speech_eval.dart';
export 'src/spoken_check_eval.dart';
export 'src/summary.dart';
