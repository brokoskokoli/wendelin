import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart' show SpokenVersion;

import 'cli.dart';
import 'eval_case.dart';
import 'eval_profile.dart';
import 'eval_runner.dart';
import 'eval_time.dart';
import 'speech_check.dart';

/// The variants compared by the speech eval (WP41).
enum SpeechVariant {
  /// Typed request: the answer is read aloud as it is (baseline).
  text,

  /// Voice request, stage 1: style hint in the system prompt.
  hint,

  /// Voice request, stage 2: `<spoken>` block first.
  two,
}

/// Result of one command in one [SpeechVariant].
typedef SpeechRun = ({
  String id,
  SpeechVariant variant,
  String raw,
  String spoken,
  bool block,
  List<String> issues,
  int inputTokens,
  int outputTokens,
  int cachedTokens,
  int? costMicros,
  int ms,
  String? failure,
});

/// Runs [cases] in every [variants] and returns one result each. Stage 2
/// counts the `<spoken>` block as the speech text, or – without a block –
/// the written answer (the app's fallback).
Future<List<SpeechRun>> runSpeechEval({
  required EvalTarget target,
  required EvalTime time,
  required List<EvalCase> cases,
  List<SpeechVariant> variants = SpeechVariant.values,
  void Function(SpeechRun run)? onRun,
}) async {
  final out = <SpeechRun>[];
  for (final variant in variants) {
    final runner = EvalRunner(
      target: target,
      time: time,
      voice: variant != SpeechVariant.text,
      config: AgentConfig(
        spokenVersion: variant == SpeechVariant.two
            ? SpokenVersion.protected
            : SpokenVersion.off,
      ),
    );
    for (final c in cases) {
      final o = await runner.observe(c);
      final block = o.spokenText;
      final spoken = (block ?? o.finalText).trim();
      final run = (
        id: c.id,
        variant: variant,
        raw: o.finalText,
        spoken: spoken,
        block: block != null,
        issues: o.failure != null ? ['fehler'] : speechIssues(spoken),
        inputTokens: o.usage.inputTokens,
        outputTokens: o.usage.outputTokens,
        cachedTokens: o.usage.cachedInputTokens,
        costMicros: o.costMicros,
        ms: o.latency.inMilliseconds,
        failure: o.failure?.message,
      );
      out.add(run);
      onRun?.call(run);
    }
  }
  return out;
}

/// Per-variant numbers of [runs].
Map<String, Object?> summarizeSpeech(List<SpeechRun> runs) {
  final result = <String, Object?>{};
  for (final v in SpeechVariant.values) {
    final rs = runs.where((r) => r.variant == v).toList();
    if (rs.isEmpty) continue;
    int sum(int Function(SpeechRun) f) => rs.fold(0, (a, r) => a + f(r));
    final costs = rs.map((r) => r.costMicros).toList();
    result[v.name] = {
      'commands': rs.length,
      'clean': rs.where((r) => r.issues.isEmpty).length,
      'withBlock': rs.where((r) => r.block).length,
      'inputTokens': sum((r) => r.inputTokens),
      'outputTokens': sum((r) => r.outputTokens),
      'cachedTokens': sum((r) => r.cachedTokens),
      'costMicros': costs.contains(null)
          ? null
          : costs.fold<int>(0, (a, c) => a + c!),
      'issues': {
        for (final i in rs.expand((r) => r.issues).toSet())
          i: rs.where((r) => r.issues.contains(i)).length,
      },
    };
  }
  return result;
}

/// `dart run wendelin_evals:speech --profile PROFIL.json [--model m]
/// [--out report.json]`: the 10 speech commands of `speech/cases.yaml`
/// in every variant; prints the share of clean speech texts and the cost.
Future<int> runSpeechCli(
  List<String> arguments, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  http.Client? client,
}) async {
  final parser = ArgParser()
    ..addOption('profile', abbr: 'p')
    ..addOption('model', abbr: 'm')
    ..addOption('cases-dir', defaultsTo: 'speech')
    ..addOption('variants', defaultsTo: 'text,hint,two')
    ..addOption('out', abbr: 'o');
  try {
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
    final cases = loadCases(Directory(args.option('cases-dir')!));
    final variants = [
      for (final n in args.option('variants')!.split(','))
        SpeechVariant.values.byName(n.trim()),
    ];
    final p = profile.profile;
    final target = EvalTarget(
      profileId: p.id,
      modelId: p.defaultModel,
      privacy: p.privacy,
      provider: buildProvider(profile, profileFile, time, env, client),
      costEstimator: profile.costEstimator,
    );
    out.writeln(
      'Profil ${p.id}, Modell ${p.defaultModel}, ${cases.length} Befehle',
    );
    final runs = await runSpeechEval(
      target: target,
      time: time,
      cases: cases,
      variants: variants,
      onRun: (r) => out.writeln(
        '  ${r.variant.name} ${r.id}: '
        '${r.issues.isEmpty ? 'sauber' : r.issues.join(',')}'
        '${r.block ? ' [Block]' : ''}',
      ),
    );
    final summary = summarizeSpeech(runs);
    out
      ..writeln()
      ..writeln(const JsonEncoder.withIndent('  ').convert(summary));
    if (args.option('out') case final path?) {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'meta': {
            'profileId': p.id,
            'model': p.defaultModel,
            'now': time.now.toIso(),
          },
          'summary': summary,
          'runs': [
            for (final r in runs)
              {
                'id': r.id,
                'variant': r.variant.name,
                'issues': r.issues,
                'block': r.block,
                'spoken': r.spoken,
                'written': r.raw,
                'input': r.inputTokens,
                'output': r.outputTokens,
                'cacheRead': r.cachedTokens,
                'costMicros': r.costMicros,
                'ms': r.ms,
                'failure': ?r.failure,
              },
          ],
        }),
      );
      out.writeln('Report: $path');
    }
    return 0;
  } on FormatException catch (e) {
    err.writeln('Fehler: ${e.message}');
    return 1;
  } on FileSystemException catch (e) {
    err.writeln('Fehler: ${e.message} (${e.path})');
    return 1;
  }
}
