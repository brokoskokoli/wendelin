import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'case_result.dart';
import 'eval_case.dart';
import 'eval_profile.dart';
import 'eval_runner.dart';
import 'eval_time.dart';
import 'fake_script.dart';
import 'report.dart';
import 'routing_table.dart';

/// Default „now“ of a run: Wednesday, 18 November 2026, 09:00. Chosen so
/// that relative dates („morgen“ = 2026-11-19) differ from the example dates
/// in the tool descriptions (2026-10-15), which a model could copy.
const defaultNow = '2026-11-18T09:00';

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
  ..addOption(
    'integrations',
    help: 'Nur diese Integrationen (kommagetrennt, z. B. calendar,alarms).',
  )
  ..addOption('now', defaultsTo: defaultNow, help: 'Fester „heute“-Zeitpunkt.')
  ..addOption('time-zone', defaultsTo: defaultTimeZone, help: 'IANA-Zone.')
  ..addFlag(
    'include-pending',
    negatable: false,
    help: 'Auch Fälle mit pending: true laufen lassen.',
  )
  ..addFlag(
    'routing-table',
    negatable: false,
    help: 'Routing-Tabelle (Satz → greifende Regel) ausgeben, kein Modell.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Hilfe anzeigen.');

/// Runs the eval CLI; returns the exit code (0 = ran, 64 = usage error,
/// 1 = setup error, 130 = interrupted). [env] supplies the API key,
/// [client] the HTTP client for real providers. An event on [interrupt]
/// (Ctrl+C) stops after the running case; the partial report is still
/// printed and written.
Future<int> runCli(
  List<String> arguments, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  http.Client? client,
  Stream<void>? interrupt,
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
  if (args.flag('routing-table')) {
    final outcomes = runRoutingTable();
    out.write(formatRoutingTable(outcomes));
    return outcomes.every((o) => o.ok) ? 0 : 1;
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

    final provider = buildProvider(profile, profileFile, time, env, client);
    final p = profile.profile;
    for (final model in [p.defaultModel]) {
      if (profile.catalog.lookup(model) == null) {
        err.writeln(
          'Warnung: kein Preis für Modell $model im Katalog – Kosten '
          'unvollständig (Preise über "catalog" im Profil ergänzen)',
        );
      }
    }
    final runner = EvalRunner(
      target: EvalTarget(
        profileId: p.id,
        modelId: p.defaultModel,
        privacy: p.privacy,
        provider: provider,
        costEstimator: profile.costEstimator,
      ),
      time: time,
      onlyIntegrations: args.option('integrations')?.split(',').toSet(),
    );
    out.writeln(
      'Profil ${p.id} (${p.type.name}), Modell ${p.defaultModel}, '
      '${cases.length} Fälle, heute = ${time.now} ${time.timeZone}',
    );
    var interrupted = false;
    final subscription = interrupt?.listen((_) {
      if (!interrupted) {
        err.writeln('Abbruch angefordert – Teilreport nach dem laufenden Fall');
      }
      interrupted = true;
    });
    final List<CaseResult> results;
    try {
      results = await runner.runAll(
        cases,
        includePending: args.flag('include-pending'),
        onResult: (r) => out.writeln('  ${r.evalCase.id}: ${r.status.name}'),
        shouldStop: () => interrupted,
      );
    } finally {
      await subscription?.cancel();
    }
    final report = EvalReport(
      meta: {
        'profileId': p.id,
        'providerType': p.type.name,
        'model': p.defaultModel,
        'privacy': p.privacy.name,
        'now': time.now.toIso(),
        'timeZone': time.timeZone,
        'filter': ?filter,
        'limit': ?limit,
        'cases': cases.length,
        if (interrupted) 'interrupted': true,
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
    return interrupted ? 130 : 0;
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

/// The provider of [profile] (fake script or real adapter with the key from
/// [env]); throws [FormatException] if the key variable is missing.
ProviderForCase buildProvider(
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
  Future<String?> secrets(_) async => variable == null ? null : env[variable];
  if (needsAttestation(p)) {
    // The evals measure the model, not the attestation (that needs the
    // native crypto of the app and is covered by the TEE suites). The
    // adapter is built like the factory builds the attested one, including
    // `aci_verified`, so requests and costs match the app.
    final extra = p.options['extraBody'];
    final body = extra is Map<String, Object?> ? extra : <String, Object?>{};
    final adapter = OpenAiChatAdapter(
      baseUrl: Uri.parse(p.baseUrl!),
      credentials: Credentials(
        p.authMethod,
        secrets,
        style: ApiKeyStyle.bearer,
      ),
      defaultModel: p.defaultModel,
      label: p.name,
      client: client,
      extraHeaders: p.extraHeaders,
      options: OpenAiOptions.fromMap({
        ...p.options,
        'extraBody': {
          ...body,
          'provider': {'aci_verified': true},
        },
      }),
    );
    return (_) => adapter;
  }
  final adapter = ProviderFactory.create(
    p,
    secrets,
    client: client,
    catalog: profile.catalog,
  );
  return (_) => adapter;
}
