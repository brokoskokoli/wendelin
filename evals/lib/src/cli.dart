import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'eval_case.dart';
import 'eval_profile.dart';
import 'eval_runner.dart';
import 'eval_time.dart';
import 'fake_script.dart';
import 'report.dart';

/// Default „now“ of a run: Wednesday, 14 October 2026, 09:00.
const defaultNow = '2026-10-14T09:00';

/// Default time zone of a run.
const defaultTimeZone = 'Europe/Berlin';

ArgParser _parser() => ArgParser()
  ..addOption('profile', abbr: 'p', help: 'Profil-JSON (ohne Keys).')
  ..addOption('model', abbr: 'm', help: 'Modell statt defaultModel.')
  ..addOption(
    'cases',
    abbr: 'c',
    help: 'Filter: Id-Teil, Sprache oder Kategorie, kommagetrennt.',
  )
  ..addOption('cases-dir', help: 'Verzeichnis mit *.yaml (Standard: cases).')
  ..addOption('limit', abbr: 'n', help: 'Höchstens n Fälle laufen lassen.')
  ..addOption('out', abbr: 'o', help: 'JSON-Report schreiben.')
  ..addOption('now', defaultsTo: defaultNow, help: 'Fester „heute“-Zeitpunkt.')
  ..addOption('time-zone', defaultsTo: defaultTimeZone, help: 'IANA-Zone.')
  ..addFlag(
    'include-pending',
    negatable: false,
    help: 'Auch Fälle mit pending: true laufen lassen.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Hilfe anzeigen.');

/// Runs the eval CLI; returns the exit code (0 = ran, 64 = usage error,
/// 1 = setup error). [env] supplies the API key, [client] the HTTP client
/// for real providers.
Future<int> runCli(
  List<String> arguments, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  http.Client? client,
}) async {
  final parser = _parser();
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${parser.usage}');
    return 64;
  }
  if (args.flag('help')) {
    out.writeln(
      'dart run wendelin_evals:run --profile <profil.json> [Optionen]\n\n'
      '${parser.usage}',
    );
    return 0;
  }
  final profilePath = args.option('profile');
  if (profilePath == null) {
    err.writeln('--profile fehlt\n\n${parser.usage}');
    return 64;
  }
  final limitText = args.option('limit');
  final limit = limitText == null ? null : int.tryParse(limitText);
  if (limitText != null && (limit == null || limit < 1)) {
    err.writeln('--limit braucht eine Zahl ≥ 1');
    return 64;
  }

  try {
    final profileFile = File(profilePath);
    var profile = EvalProfile.parse(profileFile.readAsStringSync());
    if (args.option('model') case final model?) {
      profile = profile.withModel(model);
    }
    final time = EvalTime.parse(args.option('now')!, args.option('time-zone')!);

    final casesDir = _casesDir(args.option('cases-dir'));
    final filter = args.option('cases');
    var cases = loadCases(casesDir).where((c) => c.matches(filter)).toList();
    if (limit != null && cases.length > limit) {
      cases = cases.take(limit).toList();
    }
    if (cases.isEmpty) {
      err.writeln('Keine Fälle ausgewählt');
      return 1;
    }

    final provider = _provider(profile, profileFile, time, env, client);
    final p = profile.profile;
    final runner = EvalRunner(
      target: EvalTarget(
        profileId: p.id,
        modelId: p.defaultModel,
        privacy: p.privacy,
        provider: provider,
        escalationModels: profile.escalationModels,
        costEstimator: profile.costEstimator,
      ),
      time: time,
    );
    out.writeln(
      'Profil ${p.id} (${p.type.name}), Modell ${p.defaultModel}, '
      '${cases.length} Fälle, heute = ${time.now} ${time.timeZone}',
    );
    final results = await runner.runAll(
      cases,
      includePending: args.flag('include-pending'),
      onResult: (r) => out.writeln('  ${r.evalCase.id}: ${r.status.name}'),
    );
    final report = EvalReport(
      meta: {
        'profileId': p.id,
        'providerType': p.type.name,
        'model': p.defaultModel,
        'escalationModels': profile.escalationModels,
        'privacy': p.privacy.name,
        'now': time.now.toIso(),
        'timeZone': time.timeZone,
        'filter': ?filter,
        'limit': ?limit,
        'cases': cases.length,
      },
      results: results,
    );
    out
      ..writeln()
      ..write(report.renderTable());
    if (args.option('out') case final path?) {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(report.encode());
      out.writeln('Report: $path');
    }
    return 0;
  } on FormatException catch (e) {
    err.writeln('Fehler: ${e.message}');
    return 1;
  } on FileSystemException catch (e) {
    err.writeln('Fehler: ${e.message} (${e.path})');
    return 1;
  } on ArgumentError catch (e) {
    err.writeln('Fehler: ${e.message}');
    return 1;
  }
}

Directory _casesDir(String? option) {
  if (option != null) return Directory(option);
  for (final candidate in ['cases', 'evals/cases']) {
    final d = Directory(candidate);
    if (d.existsSync()) return d;
  }
  return Directory('cases');
}

ProviderForCase _provider(
  EvalProfile profile,
  File profileFile,
  EvalTime time,
  Map<String, String> env,
  http.Client? client,
) {
  final p = profile.profile;
  if (p.type == ProviderType.fake) {
    final scriptPath = profile.script;
    if (scriptPath == null) {
      throw const FormatException('Fake-Profil braucht "script"');
    }
    final file = File.fromUri(profileFile.absolute.uri.resolve(scriptPath));
    final script = FakeScript.parse(file.readAsStringSync());
    return (c) => script.providerFor(c, time);
  }
  final variable = profile.apiKeyVariable;
  if (variable != null && (env[variable]?.trim().isEmpty ?? true)) {
    throw FormatException(
      'Umgebungsvariable $variable fehlt (API-Key für ${p.id})',
    );
  }
  final adapter = ProviderFactory.create(
    p,
    (_) async => variable == null ? null : env[variable],
    client: client,
    catalog: profile.catalog,
  );
  return (_) => adapter;
}
