import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'budget.dart';
import 'case_result.dart';
import 'eval_case.dart';
import 'eval_profile.dart';
import 'eval_runner.dart';
import 'eval_time.dart';
import 'fake_script.dart';
import 'ledger.dart';
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
  ..addOption(
    'max-cost',
    help:
        'Kostengrenze in USD: der Lauf bricht ab (auch mitten im Fall), '
        'sobald die Summe sie erreicht. Ohne Preis des Modells kein Start.',
  )
  ..addOption(
    'provider-cap',
    help:
        'Obergrenze in USD für den Anbieter (Profil-Id) über alle Läufe im '
        '--ledger: wirksame Grenze = Obergrenze minus bisherige Summe '
        '(≤ 0: kein Start). Nur mit --ledger.',
  )
  ..addOption(
    'repeat',
    defaultsTo: '1',
    help: 'Jeden Fall n-mal laufen lassen (Stabilität).',
  )
  ..addOption(
    'ledger',
    help: 'JSON-Bilanz: hängt je Lauf Anbieter, Modell, Fälle, Kosten an.',
  )
  ..addFlag(
    'ledger-summary',
    negatable: false,
    help: 'Summe je Anbieter aus --ledger zeigen, kein Lauf.',
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
/// 1 = setup error, 2 = stopped by `--max-cost`, 130 = interrupted). [env] supplies the API key,
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
  DateTime Function()? today,
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
  if (args.flag('ledger-summary')) return _ledgerSummary(args, out, err);
  final profilePath = args.option('profile');
  if (profilePath == null) {
    err.writeln('--profile fehlt\n\n${parser.usage}');
    return 64;
  }
  if (_badNumber(args) case final bad?) {
    err.writeln(bad);
    return 64;
  }
  final limit = int.tryParse(args.option('limit') ?? '');
  final repeat = int.parse(args.option('repeat')!);
  var budget = _budget(args.option('max-cost'));
  final cap = double.tryParse(args.option('provider-cap') ?? '');
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
    final p = profile.profile;
    final ledgerFile = _ledger(args.option('ledger'));
    final capped = _capBudget(cap, budget, ledgerFile, profile);
    if (capped.$2 case final msg?) {
      err.writeln(msg);
      return 1;
    }
    budget = capped.$1;
    final priced = profile.catalog.lookup(p.defaultModel) != null;
    if (budget != null && !priced) {
      err.writeln(_noPrice(p.defaultModel));
      return 1;
    }
    if (!priced) err.writeln(_priceWarning(p.defaultModel));
    final provider = buildProvider(profile, profileFile, time, env, client);
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
      budget: budget,
    );
    out.writeln(
      'Profil ${p.id} (${p.type.name}), Modell ${p.defaultModel}, '
      '${cases.length} Fälle${repeat > 1 ? ' × $repeat' : ''}, heute = ${time.now} ${time.timeZone}',
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
        repeat: repeat,
      );
    } finally {
      await subscription?.cancel();
    }
    return _finish(
      args,
      out,
      err,
      p,
      time,
      results,
      budget: budget,
      repeat: repeat,
      interrupted: interrupted,
      ledgerFile: ledgerFile,
      budgetGroup: profile.budgetGroup,
      today: today,
    );
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

/// Prints and writes the report, books the ledger and returns the exit code.
int _finish(
  ArgResults args,
  StringSink out,
  StringSink err,
  ProviderProfile p,
  EvalTime time,
  List<CaseResult> results, {
  required CostBudget? budget,
  required int repeat,
  required bool interrupted,
  required File? ledgerFile,
  required String? budgetGroup,
  required DateTime Function()? today,
}) {
  final limit = args.option('limit');
  final report = EvalReport(
    meta: {
      'profileId': p.id,
      'providerType': p.type.name,
      'model': p.defaultModel,
      'privacy': p.privacy.name,
      'now': time.now.toIso(),
      'timeZone': time.timeZone,
      'filter': ?args.option('cases'),
      'limit': ?(limit == null ? null : int.tryParse(limit)),
      'cases': results
          .where((r) => r.repetition == null || r.repetition == 1)
          .length,
      if (repeat > 1) 'repeat': repeat,
      if (budget != null) 'maxCostMicros': budget.limitMicros,
      if (budget?.exceeded ?? false) ...{
        'budgetExceeded': true,
        'budgetReason': budget!.stopReason,
      },
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
  if (ledgerFile != null) {
    appendLedger(
      ledgerFile,
      ledgerEntryOf(
        p,
        budgetGroup,
        report.summary,
        budget,
        (today ?? DateTime.now)(),
      ),
    );
    out.writeln('Bilanz ergänzt: ${ledgerFile.path}');
  }
  if (budget?.exceeded ?? false) {
    err.writeln('Abbruch: ${budget!.stopReason}');
    return 2;
  }
  return interrupted ? 130 : 0;
}

/// The ledger file, read now: a broken ledger must stop the run before it
/// costs money.
File? _ledger(String? path) {
  if (path == null) return null;
  final file = File(path);
  readLedger(file);
  return file;
}

/// Why a numeric option is invalid; `null` if all are fine.
String? _badNumber(ArgResults a) {
  final limit = a.option('limit');
  if (limit != null && (int.tryParse(limit) ?? 0) < 1) {
    return '--limit braucht eine Zahl ≥ 1';
  }
  if ((int.tryParse(a.option('repeat')!) ?? 0) < 1) {
    return '--repeat braucht eine Zahl ≥ 1';
  }
  if (a.option('max-cost') != null && _budget(a.option('max-cost')) == null) {
    return '--max-cost braucht eine Zahl > 0 (USD)';
  }
  final capText = a.option('provider-cap');
  if (capText == null) return null;
  final cap = double.tryParse(capText);
  if (cap == null || !cap.isFinite || cap <= 0) {
    return '--provider-cap braucht eine Zahl > 0 (USD)';
  }
  return a.option('ledger') == null
      ? '--provider-cap braucht --ledger <datei>'
      : null;
}

/// The budget after applying [cap] for [provider] (cap minus what the
/// ledger booked, the smaller of that and [own]); or an error message when
/// nothing is left.
(CostBudget?, String?) _capBudget(
  double? cap,
  CostBudget? own,
  File? ledgerFile,
  EvalProfile profile,
) {
  if (cap == null) return (own, null);
  final group = profile.budgetGroup;
  final profileId = profile.profile.id;
  if (group == null) {
    return (
      own,
      'Fehler: --provider-cap, aber das Profil $profileId hat keine '
          '"budgetGroup" (Konto-Gruppe, z. B. anthropic) – Start verweigert',
    );
  }
  final spent = groupSpentUsd(readLedger(ledgerFile!), group);
  final remaining = cap - spent;
  if ((remaining * 1e6).round() < 1) {
    return (
      own,
      'Fehler: Obergrenze für $group ausgeschöpft '
          '(${spent.toStringAsFixed(4)} von ${cap.toStringAsFixed(4)} USD im '
          'Ledger) – Start verweigert',
    );
  }
  final mine = own?.limitMicros;
  return (
    mine == null || remaining * 1e6 < mine ? CostBudget(remaining) : own,
    null,
  );
}

String _priceWarning(String model) =>
    'Warnung: kein Preis für Modell $model im Katalog – Kosten '
    'unvollständig (Preise über "catalog" im Profil ergänzen)';

String _noPrice(String model) =>
    'Fehler: --max-cost, aber kein Preis für Modell $model (Preise über '
    '"catalog" im Profil ergänzen) – Start verweigert';

CostBudget? _budget(String? text) {
  if (text == null) return null;
  final usd = double.tryParse(text);
  return usd == null || !usd.isFinite || usd <= 0 ? null : CostBudget(usd);
}

int _ledgerSummary(ArgResults args, StringSink out, StringSink err) {
  final path = args.option('ledger');
  if (path == null) {
    err.writeln('--ledger-summary braucht --ledger <datei>');
    return 64;
  }
  try {
    out.write(renderLedgerSummary(readLedger(File(path))));
    return 0;
  } on FormatException catch (e) {
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
          if (attestationKind(p) == AttestationKind.phala)
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
