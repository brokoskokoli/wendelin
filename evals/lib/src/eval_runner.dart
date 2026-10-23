import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'budget.dart';
import 'case_backends.dart';
import 'case_result.dart';
import 'eval_case.dart';
import 'eval_time.dart';
import 'scorer.dart';

/// Supplies the provider for one case. Real providers return the same
/// adapter every time; the fake provider plays a script per case.
typedef ProviderForCase = LlmProvider Function(EvalCase c);

/// The provider profile and model under test.
final class EvalTarget {
  /// Creates a target.
  const EvalTarget({
    required this.profileId,
    required this.modelId,
    required this.privacy,
    required this.provider,
    this.costEstimator,
  });

  /// Provider profile id.
  final String profileId;

  /// Model id.
  final String modelId;

  /// Privacy level of the profile.
  final PrivacyLevel privacy;

  /// Provider per case.
  final ProviderForCase provider;

  /// Prices the model calls; `null` = cost unknown.
  final CostEstimator? costEstimator;
}

/// Default search hits of the fake web search backend.
const defaultSearchResults = [
  SeedSearchResult(
    title: 'Wendelin Testseite',
    url: 'https://example.org/wendelin',
    snippet: 'Beispieltreffer der Eval-Suche.',
  ),
];

/// Runs eval cases through the real agent loop with fake ports.
///
/// Per case: fresh fake ports (calendar, clipboard, alarms, memory, web
/// search and fetch without network) filled from the case setup, a
/// [ToolRegistry] with all built-in integrations, the [ToolExecutor] and an
/// [AgentRunner] whose clock stands at [time]. As in the app, relevant
/// memory entries reach the system prompt through a [MemoryRetriever] on the
/// memory store. The device locale follows the case language
/// ([localeFor]). Confirmations are answered „ja“ automatically (also for
/// escalations below the privacy floor) and counted.
final class EvalRunner {
  /// Creates a runner.
  EvalRunner({
    required this.target,
    required this.time,
    this.config = const AgentConfig(),
    this.voice = false,
    this.fastPath = false,
    this.onlyIntegrations,
    this.budget,
    GiveUpClassifier? giveUpClassifier,
    this.pause = Duration.zero,
    this.retryRateLimit,
    this.maxRateLimited = 5,
    this.sleep = _realSleep,
  }) : giveUpClassifier = giveUpClassifier ?? GiveUpClassifier(),
       scorer = Scorer(time);

  /// Profile and model under test.
  final EvalTarget target;

  /// Fixed „now“ of the run.
  final EvalTime time;

  /// Agent limits.
  final AgentConfig config;

  /// Integration ids to register (reduced catalog, WP57); `null` = all.
  final Set<String>? onlyIntegrations;

  /// Cost limit of the run (`--max-cost`); `null` = none.
  final CostBudget? budget;

  /// Whether the request counts as spoken (WP41: speech hint, stage 2).
  final bool voice;

  /// Wire the fast path of the Home Assistant integration like the app
  /// does (WP135 D); off = every request goes to the model.
  final bool fastPath;

  /// Detects „kann ich nicht“ answers (the agent's own classifier).
  final GiveUpClassifier giveUpClassifier;

  /// Evaluates observations.
  final Scorer scorer;

  /// Wait before every case that really runs, except the first (`--pause-ms`).
  /// Not part of the latency.
  final Duration pause;

  /// Wait before the single second attempt of a case that ended with a rate
  /// limit (`--retry-rate-limit`); `null` = no second attempt.
  final Duration? retryRateLimit;

  /// Once more than this many cases still end with a rate limit after the
  /// second attempt, the remaining cases are skipped as `rate-limit`.
  final int maxRateLimited;

  /// Waits for [pause] and [retryRateLimit]; replaceable in tests.
  final Future<void> Function(Duration) sleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// Device locale for a case language (`de` → `de-DE`, `fr` → `fr-FR`,
  /// `en` → `en-US`; others `<lang>-<LANG>`).
  static String localeFor(String language) => switch (language) {
    'en' => 'en-US',
    _ => '$language-${language.toUpperCase()}',
  };

  /// Runs [cases] one after another; pending cases are skipped unless
  /// [includePending]. [onResult] is called after each case. Once
  /// [shouldStop] returns `true` (e.g. after Ctrl+C) the remaining cases are
  /// skipped as „abgebrochen“, so a partial report can still be written.
  Future<List<CaseResult>> runAll(
    List<EvalCase> cases, {
    bool includePending = false,
    void Function(CaseResult result)? onResult,
    bool Function()? shouldStop,
    int repeat = 1,
  }) async {
    if (repeat < 1) {
      throw ArgumentError.value(repeat, 'repeat', 'muss ≥ 1 sein');
    }
    final results = <CaseResult>[];
    var rateLimited = 0;
    var ranAny = false;
    for (final c in cases) {
      for (var n = 1; n <= repeat; n++) {
        final rep = repeat > 1 ? n : null;
        final r = (shouldStop?.call() ?? false)
            ? CaseResult.skipped(c, 'abgebrochen', repetition: rep)
            : (budget?.exceeded ?? false)
            ? CaseResult.skipped(c, 'budget', repetition: rep)
            : rateLimited > maxRateLimited
            ? CaseResult.skipped(c, 'rate-limit', repetition: rep)
            : c.pending && !includePending
            ? CaseResult.skipped(
                c,
                'pending: Integration fehlt noch',
                repetition: rep,
              )
            : (await _runPaced(c, first: !ranAny)).withRepetition(rep);
        if (r.ran) ranAny = true;
        if (_isRateLimited(r)) rateLimited++;
        results.add(r);
        onResult?.call(r);
      }
    }
    return results;
  }

  Future<CaseResult> _runPaced(EvalCase c, {required bool first}) async {
    if (!first && pause > Duration.zero) await sleep(pause);
    final attempt = await runCase(c);
    final wait = retryRateLimit;
    if (wait == null ||
        !_isRateLimited(attempt) ||
        (budget?.exceeded ?? false)) {
      return attempt;
    }
    await sleep(wait);
    final second = await runCase(c);
    return _merge(attempt, second);
  }

  static bool _isRateLimited(CaseResult r) =>
      r.observation.failure?.cause is RateLimitException;

  /// The second attempt, with usage, cost and model calls of both and
  /// `retried`; latency and failure stay those of the second attempt.
  static CaseResult _merge(CaseResult a, CaseResult b) {
    final x = a.observation;
    final y = b.observation;
    int? cost(RunObservation o) => o.modelCalls == 0 ? 0 : o.costMicros;
    final cx = cost(x);
    final cy = cost(y);
    final merged = RunObservation(
      calls: y.calls,
      finalText: y.finalText,
      failure: y.failure,
      latency: y.latency,
      usage: x.usage + y.usage,
      costMicros: x.modelCalls + y.modelCalls == 0
          ? null
          : (cx == null || cy == null ? null : cx + cy),
      modelCalls: x.modelCalls + y.modelCalls,
      confirmations: y.confirmations,
      escalationConfirmations: y.escalationConfirmations,
      completed: y.completed,
      escalations: y.escalations,
      gaveUp: y.gaveUp,
      spokenText: y.spokenText,
      retried: true,
    );
    return CaseResult(
      evalCase: b.evalCase,
      status: b.status,
      reasons: b.reasons,
      observation: merged,
    );
  }

  /// Runs one case and scores it.
  Future<CaseResult> runCase(EvalCase c) async {
    try {
      final observation = await observe(c);
      if (budget?.stopReason case final why?) {
        return CaseResult(
          evalCase: c,
          status: CaseStatus.error,
          reasons: ['budget: $why'],
          observation: observation,
        );
      }
      return scorer.score(c, observation);
    } on Object catch (e) {
      return CaseResult(
        evalCase: c,
        status: CaseStatus.error,
        reasons: ['Fall konnte nicht laufen: $e'],
      );
    }
  }

  /// Runs [c] through the agent and records what happened.
  Future<RunObservation> observe(EvalCase c) async {
    final clock = FixedClock(time.instant);
    final sessionId = 'eval-${c.id}';
    final registry = ToolRegistry();
    final (integrations, memory) = await _integrations(c, clock);
    final backends = await CaseBackends.start(c.setup.backends, clock);
    try {
      return await _observe(c, clock, sessionId, registry, memory, [
        ...integrations,
        ...backends.integrations,
      ]);
    } finally {
      await backends.close();
    }
  }

  Future<RunObservation> _observe(
    EvalCase c,
    Clock clock,
    String sessionId,
    ToolRegistry registry,
    MemoryStorePort memory,
    List<Integration> integrations,
  ) async {
    await _register(registry, integrations);
    final catalog = registry.catalogFor(target.privacy, sessionId: sessionId);
    final provider = target.provider(c);
    final agent = AgentRunner(
      resolver: DefaultProviderResolver(
        ProviderTarget(
          profileId: target.profileId,
          modelId: target.modelId,
          provider: provider,
          privacy: target.privacy,
        ),
      ),
      contextBuilder: ContextBuilder(
        config: config,
        clock: clock,
        device: DeviceInfo(
          locale: localeFor(c.language),
          timeZone: time.timeZone,
        ),
        catalog: catalog,
        memory: StoreMemoryRetriever(memory),
      ),
      invoker: ToolExecutor(catalog: catalog),
      clock: clock,
      sessionId: sessionId,
      costEstimator: target.costEstimator,
      fastPath: _fastPathOf(integrations),
    );

    final calls = <ObservedCall>[];
    final escalations = <ObservedEscalation>[];
    var usage = Usage.zero;
    int? cost = 0;
    var modelCalls = 0;
    var confirmations = 0;
    var escalationConfirmations = 0;
    var finalText = '';
    String? spokenText;
    AgentFailed? failure;
    final watch = Stopwatch()..start();
    loop:
    await for (final event in agent.run(
      UserInput(
        text: c.prompt,
        language: c.language,
        source: voice ? InputSource.voice : InputSource.text,
      ),
    )) {
      switch (event) {
        case ConfirmationRequired():
          confirmations++;
          event.respond(true);
        case EscalationConfirmationRequired():
          escalationConfirmations++;
          event.respond(true);
        case ToolCallFinished(:final call, :final outcome):
          calls.add(_observedCall(call, outcome));
        case Escalated(:final toProfile, :final reason):
          escalations.add((to: toProfile, reason: reason));
        case UsageReported(usage: final u, :final costMicros):
          modelCalls++;
          usage = usage + u;
          cost = cost == null || costMicros == null ? null : cost + costMicros;
          if (budget case final b? when !b.record(costMicros)) {
            // Stop right here, mid-case: leaving the loop cancels the agent.
            break loop;
          }
        case AgentSpokenText(:final text):
          spokenText ??= text;
        case AgentDone(finalText: final text):
          finalText = text;
        case AgentFailed():
          failure = event;
        case _:
          break;
      }
    }
    watch.stop();
    final gaveUp = giveUpClassifier.isGiveUp(finalText);
    return RunObservation(
      calls: calls,
      finalText: finalText,
      failure: failure,
      latency: watch.elapsed,
      usage: usage,
      costMicros: modelCalls == 0 ? null : cost,
      modelCalls: modelCalls,
      confirmations: confirmations,
      escalationConfirmations: escalationConfirmations,
      completed: true,
      escalations: escalations,
      gaveUp: gaveUp,
      spokenText: spokenText,
    );
  }

  Future<void> _register(
    ToolRegistry registry,
    List<Integration> integrations,
  ) async {
    for (final integration in integrations) {
      if (onlyIntegrations != null &&
          !onlyIntegrations!.contains(integration.id)) {
        continue;
      }
      await registry.registerIntegration(integration, enabled: true);
    }
  }

  FastPath? _fastPathOf(List<Integration> integrations) => fastPath
      ? integrations.whereType<HaIntegration>().firstOrNull?.fastPath
      : null;

  static ObservedCall _observedCall(ToolCallBlock call, ToolOutcome outcome) =>
      ObservedCall(
        name: call.name,
        args: call.tryDecodeArguments(),
        rawArguments: call.argumentsJson,
        isError: outcome.isError,
        summary: outcome.summary,
      );

  Future<(List<Integration>, MemoryStorePort)> _integrations(
    EvalCase c,
    Clock clock,
  ) async {
    final setup = c.setup;
    final calendar = FakeCalendarPort(
      events: [for (final e in setup.events) _event(e)],
    );
    final memory = FakeMemoryStore(clock: clock);
    for (final m in setup.memory) {
      await memory.save(
        m.text,
        category: MemoryCategory.values.byName(m.category),
        source: 'eval',
      );
    }
    final hits = setup.searchResults ?? defaultSearchResults;
    return (
      <Integration>[
        CalendarIntegration(calendar, deviceTimeZone: () => time.timeZone),
        ClipboardIntegration(FakeClipboardPort(content: setup.clipboard)),
        AlarmsIntegration(FakeAlarmPort()),
        MemoryIntegration(memory),
        WebIntegration(
          searchBackend: FakeWebSearchBackend(
            results: [
              for (final h in hits)
                WebSearchResult(title: h.title, url: h.url, snippet: h.snippet),
            ],
          ),
          fetcher: WebFetcher(
            client: _offlineWeb(),
            resolve: (_) async => [InternetAddress('93.184.215.14')],
          ),
        ),
      ],
      memory,
    );
  }

  CalendarEvent _event(SeedEvent e) {
    final start = time.resolve(e.start);
    final end = e.end == null ? null : time.resolve(e.end!);
    final startUtc = _utc(start);
    return CalendarEvent(
      id: e.id,
      calendarId: 'privat',
      title: e.title,
      start: startUtc,
      end: end == null ? startUtc.add(const Duration(hours: 1)) : _utc(end),
      timeZone: time.timeZone,
    );
  }

  DateTime _utc(WallTime w) => EvalTime(
    WallTime(w.year, w.month, w.day, w.hour ?? 0, w.minute ?? 0),
    time.timeZone,
  ).instant.toUtc();
}

/// Answers every page fetch with a small fixed HTML page; never touches the
/// network.
http.Client _offlineWeb() => MockClient(
  (request) async => http.Response(
    '<html><head><title>Testseite</title></head><body><h1>Testseite</h1>'
    '<p>Dies ist eine feste Seite der Wendelin-Evals.</p></body></html>',
    200,
    headers: {'content-type': 'text/html; charset=utf-8'},
  ),
);

/// [MemoryRetriever] on top of the memory store, as the app wires it: the
/// store's search with the request text.
final class StoreMemoryRetriever implements MemoryRetriever {
  /// Creates the retriever.
  const StoreMemoryRetriever(this.store);

  /// Memory store.
  final MemoryStorePort store;

  @override
  Future<List<MemoryItem>> relevant(String query, {required int limit}) async =>
      [
        for (final e in await store.search(query, limit: limit))
          MemoryItem(id: e.id, text: e.text, category: e.category.name),
      ];
}
