import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:yaml/yaml.dart';

import 'cli.dart';
import 'eval_case.dart';
import 'eval_profile.dart';
import 'eval_time.dart';

/// One pair of spoken and written text with the expected verdict (WP55).
typedef CheckCase = ({
  String id,
  String language,
  bool match,
  bool local,
  String written,
  String spoken,
});

/// Result of one case: the model alone and the full check (with the local
/// pre-check).
typedef CheckRun = ({
  CheckCase c,
  bool modelMatch,
  String modelReason,
  int ms,
  bool fullMatch,
  int inputTokens,
  int outputTokens,
  int? costMicros,
});

const _probe = EvalCase(
  id: 'spoken-check',
  language: 'de',
  prompt: '',
  expect: Expectation(),
);

/// Reads the cases of [file].
List<CheckCase> loadCheckCases(File file) {
  final doc = loadYaml(file.readAsStringSync()) as YamlMap;
  return [
    for (final raw in (doc['cases'] as YamlList).cast<YamlMap>())
      (
        id: raw['id'] as String,
        language: raw['language'] as String,
        match: raw['match'] as bool,
        local: raw['local'] == true,
        written: raw['written'] as String,
        spoken: raw['spoken'] as String,
      ),
  ];
}

/// Runs [cases] against [target]: once with the model only (precheck off),
/// then the full check. Returns one run per case.
Future<List<CheckRun>> runSpokenCheckEval({
  required LlmProvider provider,
  required String model,
  required List<CheckCase> cases,
  CostEstimator? costEstimator,
  required String profileId,
  Duration timeout = const Duration(seconds: 30),
  void Function(CheckRun run)? onRun,
}) async {
  final check = SpokenCheck(timeout);
  final out = <CheckRun>[];
  for (final c in cases) {
    final watch = Stopwatch()..start();
    final model0 = await check.run(
      provider,
      model,
      spoken: c.spoken,
      written: c.written,
      parent: CancelToken(),
      language: c.language,
      precheck: false,
    );
    watch.stop();
    final full =
        SpokenPrecheck.mismatch(c.spoken, c.written) == null && model0.match;
    final usage = model0.usage ?? Usage.zero;
    final run = (
      c: c,
      modelMatch: model0.match,
      modelReason: model0.reason,
      ms: watch.elapsedMilliseconds,
      fullMatch: full,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      costMicros: costEstimator?.estimateMicros(
        profileId: profileId,
        modelId: model,
        usage: usage,
      ),
    );
    out.add(run);
    onRun?.call(run);
  }
  return out;
}

/// Summary of [runs]: hit rates for matching and manipulated pairs (model
/// alone and with the pre-check), latency of the check and cost.
Map<String, Object?> summarizeSpokenCheck(List<CheckRun> runs) {
  final good = runs.where((r) => r.c.match).toList();
  final bad = runs.where((r) => !r.c.match).toList();
  final ms = [for (final r in runs) r.ms]..sort();
  final costs = runs.map((r) => r.costMicros).toList();
  return {
    'cases': runs.length,
    'matchingAccepted':
        '${good.where((r) => r.fullMatch).length}/${good.length}',
    'manipulatedRejected':
        '${bad.where((r) => !r.fullMatch).length}/${bad.length}',
    'modelOnlyMatchingAccepted':
        '${good.where((r) => r.modelMatch).length}/${good.length}',
    'modelOnlyManipulatedRejected':
        '${bad.where((r) => !r.modelMatch).length}/${bad.length}',
    'latencyMsP50': ms[ms.length ~/ 2],
    'latencyMsMax': ms.last,
    'inputTokens': runs.fold<int>(0, (a, r) => a + r.inputTokens),
    'outputTokens': runs.fold<int>(0, (a, r) => a + r.outputTokens),
    'costMicros': costs.contains(null)
        ? null
        : costs.fold<int>(0, (a, c) => a + c!),
  };
}

/// `dart run wendelin_evals:spoken_check --profile PROFIL.json [--model m]
/// [--out report.json]` (WP55).
Future<int> runSpokenCheckCli(
  List<String> arguments, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  http.Client? client,
}) async {
  final parser = ArgParser()
    ..addOption('profile', abbr: 'p')
    ..addOption('model', abbr: 'm')
    ..addOption('cases', defaultsTo: 'spoken-check/cases.yaml')
    ..addOption('out', abbr: 'o');
  final args = parser.parse(arguments);
  final profilePath = args.option('profile');
  if (profilePath == null) {
    err.writeln('--profile fehlt\n\n${parser.usage}');
    return 64;
  }
  final profileFile = File(profilePath);
  var profile = EvalProfile.parse(profileFile.readAsStringSync());
  if (args.option('model') case final model?) {
    profile = profile.withModel(model);
  }
  final time = EvalTime.parse(defaultNow, defaultTimeZone);
  final p = profile.profile;
  final cases = loadCheckCases(File(args.option('cases')!));
  out.writeln(
    'Profil ${p.id}, Modell ${p.defaultModel}, ${cases.length} Paare',
  );
  final runs = await runSpokenCheckEval(
    provider: buildProvider(profile, profileFile, time, env, client)(_probe),
    model: p.defaultModel,
    cases: cases,
    costEstimator: profile.costEstimator,
    profileId: p.id,
    onRun: (r) => out.writeln(
      '  ${r.c.id}: erwartet ${r.c.match ? 'passt' : 'passt nicht'}, '
      'Modell ${r.modelMatch ? 'passt' : 'passt nicht'}, ${r.ms} ms',
    ),
  );
  final summary = summarizeSpokenCheck(runs);
  out
    ..writeln()
    ..writeln(const JsonEncoder.withIndent('  ').convert(summary));
  if (args.option('out') case final path?) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'meta': {'profileId': p.id, 'model': p.defaultModel},
        'summary': summary,
        'runs': [
          for (final r in runs)
            {
              'id': r.c.id,
              'expectedMatch': r.c.match,
              'modelMatch': r.modelMatch,
              'fullMatch': r.fullMatch,
              'reason': r.modelReason,
              'ms': r.ms,
              'input': r.inputTokens,
              'output': r.outputTokens,
              'costMicros': r.costMicros,
            },
        ],
      }),
    );
  }
  return 0;
}
