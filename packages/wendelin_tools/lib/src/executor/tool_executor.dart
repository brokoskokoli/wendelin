import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../policy/risk_policy.dart';
import '../validation/argument_validator.dart';
import 'confirmation_turns.dart';
import 'error_text.dart';
import 'result_shaper.dart';
import 'tool_audit.dart';

/// Executes the tool calls of one model turn ([ToolInvoker] for the agent).
///
/// Per call: look up the tool, decode and validate the arguments, ask the
/// [RiskPolicy], ask the user if needed, run the tool with a [timeout], turn
/// exceptions into readable error outcomes, truncate and wrap the result
/// ([ResultShaper]) and report to the [audit] sink.
///
/// Independent calls run in parallel; confirmations are asked strictly one
/// after another in call order. Every call gets one [ToolStarted] (all at
/// the start, in call order) and one [ToolFinished], emitted as soon as the
/// call is done (so the UI never waits for an earlier call's confirmation).
/// The agent puts the results for the model back into call order by call
/// id. Cancellation follows the [ToolInvoker] contract.
///
/// Everything a tool produced reaches the model inside the data envelope,
/// including the text of exceptions it threw (sanitised, see
/// [sanitizeErrorText]).
final class ToolExecutor
    implements ToolInvoker, ToolRiskAssessor, SessionLockable {
  /// Creates an executor over [catalog].
  ToolExecutor({
    required this.catalog,
    RiskPolicy? policy,
    this.validator = const ArgumentValidator(),
    this.audit,
    this.timeout = const Duration(seconds: 20),
    this.shaper = const ResultShaper(),
    this.catalogFor,
    this.access = AccessContext.unlocked,
  }) : policy = policy ?? RiskPolicy();

  /// Where tools are looked up when the context names no privacy level.
  final ToolCatalog catalog;

  /// Catalog per privacy level (e.g. `ToolRegistry.catalogFor`). If set and
  /// `ToolContext.privacyLevel` is given, tools are looked up only in the
  /// catalog of that level: a call from a standard model to a sensitive tool
  /// is an unknown tool, and `tools__search` lists only that level's tools.
  final ToolCatalog Function(PrivacyLevel level)? catalogFor;

  ToolCatalog _catalogOf(ToolContext ctx) {
    final level = ctx.privacyLevel;
    final perLevel = catalogFor;
    return level == null || perLevel == null ? catalog : perLevel(level);
  }

  /// Decides allow / confirm / deny.
  final RiskPolicy policy;

  /// Lock state and voice of the run (WP154 L2). Authoritative: the policy
  /// decides with it and every tool gets it in `ToolContext.access`, whatever
  /// the context of the call says. Locked calls are audited `whileLocked`.
  final AccessContext access;

  @override
  RiskLevel effectiveRisk(
    Tool tool,
    String sessionId, {
    bool foreignContent = false,
  }) => RiskPolicy.effectiveRisk(
    tool.risk,
    policy
        .decide(tool, sessionId, access: access, foreignContent: foreignContent)
        .action,
  );

  @override
  void lockExternal(String sessionId, {String? profileId}) =>
      policy.lockExternal(sessionId, profileId: profileId);

  @override
  void holdSession(String sessionId) => policy.holdSession(sessionId);

  @override
  void releaseSession(String sessionId) => policy.releaseSession(sessionId);

  PolicyDecision _decide(Tool tool, ToolContext ctx) => policy.decide(
    tool,
    ctx.sessionId,
    access: access,
    foreignContent: ctx.foreignContentSeen,
  );

  /// Checks arguments against the tool's input schema.
  final ArgumentValidator validator;

  /// Optional audit log.
  final ToolAuditSink? audit;

  /// Maximum run time of a single tool.
  final Duration timeout;

  /// Truncates (default 8000 characters) and wraps tool results.
  final ResultShaper shaper;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) {
    final out = StreamController<ToolInvocationEvent>();
    Future<void> run() async {
      // The stored session locks are loaded before the first decision.
      await policy.ready;
      final turns = ConfirmationTurns(ctx.cancel);
      final running = <Future<void>>[];
      for (final call in calls) {
        out.add(ToolStarted(call));
        // _run never completes synchronously, so all ToolStarted come first.
        running.add(_run(call, ctx, turns, out.add).then(out.add));
      }
      await Future.wait(running);
      await out.close();
    }

    out.onListen = () => unawaited(run());
    return out.stream;
  }

  /// Arguments for the audit log: tools with private texts reduce them
  /// ([AuditArgumentsRedactor]); a slow or failing reduction stores `{}`.
  Future<String> _auditArguments(ToolCallBlock call, ToolContext ctx) async {
    final tool = _catalogOf(ctx).lookup(call.name);
    if (tool == null) return call.argumentsJson;
    try {
      return await tool
          .auditArguments(call.argumentsJson, _decode(call), ctx)
          .timeout(const Duration(seconds: 2));
    } on Object {
      return tool is AuditArgumentsRedactor ? '{}' : call.argumentsJson;
    }
  }

  Future<ToolFinished> _run(
    ToolCallBlock call,
    ToolContext ctx,
    ConfirmationTurns turns,
    void Function(ToolInvocationEvent) emit,
  ) async {
    final start = ctx.clock.now();
    _Result result;
    try {
      result = await _process(call, ctx, turns, emit);
    } on Object catch (e) {
      // Defensive: a broken catalog, schema or confirmation text must not
      // break the stream or leave the call without a result. No free text
      // of the exception reaches the model.
      result = (
        ToolOutcome.error(internalErrorText(call.name, e)),
        AuditStatus.error,
        AuditDecision.none,
      );
    }
    final (outcome, status, decision) = result;
    final duration = ctx.clock.now().difference(start);
    final auditedArguments = await _auditArguments(call, ctx);
    _audit(
      ToolAuditEntry(
        sessionId: ctx.sessionId,
        callId: call.id,
        tool: call.name,
        argumentsJson: auditedArguments,
        decision: decision,
        status: status,
        duration: duration,
        whileLocked: access.locked,
      ),
    );
    return ToolFinished(call, outcome, duration);
  }

  /// Everything up to the confirmation question runs synchronously, so the
  /// confirmation turns are taken in call order.
  Future<_Result> _process(
    ToolCallBlock call,
    ToolContext ctx,
    ConfirmationTurns turns,
    void Function(ToolInvocationEvent) emit,
  ) async {
    if (ctx.cancel.isCancelled) return _cancelled(AuditDecision.none);
    final tool = _catalogOf(ctx).lookup(call.name);
    if (tool == null) {
      return (
        ToolOutcome.error(unknownToolText(call.name)),
        AuditStatus.unknownTool,
        AuditDecision.none,
      );
    }
    final decoded = _decode(call);
    if (decoded == null) {
      return (
        ToolOutcome.error(invalidJsonText),
        AuditStatus.invalidArguments,
        AuditDecision.none,
      );
    }
    final args = validator.normalize(decoded, tool.inputSchema);
    final problem = validator.validate(args, tool.inputSchema);
    if (problem != null) {
      return (
        ToolOutcome.error(
          'Ungültige Argumente für ${tool.name}: $problem. '
          'Bitte korrigieren und erneut aufrufen.',
        ),
        AuditStatus.invalidArguments,
        AuditDecision.none,
      );
    }

    final policyDecision = _decide(tool, ctx);
    var decision = AuditDecision.allowed;
    switch (policyDecision.action) {
      case PolicyAction.deny:
        return (
          _deniedOutcome(policyDecision),
          AuditStatus.denied,
          AuditDecision.denied,
        );
      case PolicyAction.allow when access.locked && tool is WorksOnlyUnlocked:
        // Allowed by the level, but the action needs the unlocked device
        // (WP163 B): not run, the caller remembers the call for the unlock.
        return (
          ToolOutcome.error(
            deferredText,
            summary: deferredSummary,
            endsRun: true,
          ),
          AuditStatus.denied,
          AuditDecision.denied,
        );
      case PolicyAction.confirm:
        final risk = RiskPolicy.effectiveRisk(tool.risk, policyDecision.action);
        final approved = await turns.ask(
          () async => ConfirmationNeeded(
            call,
            await tool.confirmationText(args, ctx),
            Completer<bool>(),
            risk: risk,
            privateDetails: tool is AuditArgumentsRedactor,
          ),
          emit,
        );
        if (ctx.cancel.isCancelled) return _cancelled(AuditDecision.declined);
        if (!approved) {
          return (
            ToolOutcome.declined(),
            AuditStatus.declined,
            AuditDecision.declined,
          );
        }
        // The policy may have changed while the card was open (e.g.
        // lockExternal after a failed receipt check).
        final recheck = _decide(tool, ctx);
        if (recheck.action == PolicyAction.deny) {
          return (
            ToolOutcome.error(recheck.reason ?? RiskPolicy.deniedReason),
            AuditStatus.denied,
            AuditDecision.denied,
          );
        }
        decision = AuditDecision.confirmed;
      case PolicyAction.allow:
    }
    // No await since the last cancellation check: a tool is never entered
    // after cancellation.
    final (outcome, status) = await _execute(tool, args, ctx);
    return (outcome, status, decision);
  }

  Future<(ToolOutcome, AuditStatus)> _execute(
    Tool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    // Own token per call: cancelled by the run's token or by the timeout.
    final token = CancelToken();
    unawaited(ctx.cancel.whenCancelled.then((_) => token.cancel()));
    final callCtx = ToolContext(
      sessionId: ctx.sessionId,
      clock: ctx.clock,
      locale: ctx.locale,
      timeZone: ctx.timeZone,
      cancel: token,
      privacyLevel: ctx.privacyLevel,
      privacyFloor: ctx.privacyFloor,
      memoryOwner: ctx.memoryOwner,
      access: access,
      foreignContentSeen: ctx.foreignContentSeen,
    );

    final result = Completer<(ToolOutcome, AuditStatus)>();
    void finish(ToolOutcome outcome, AuditStatus status) {
      if (!result.isCompleted) result.complete((outcome, status));
    }

    final timer = Timer(timeout, () {
      finish(
        ToolOutcome.error(timeoutText(tool, timeout)),
        AuditStatus.timeout,
      );
      token.cancel();
    });
    unawaited(
      Future.sync(() => tool.execute(args, callCtx)).then(
        // A tool that completed despite cancellation keeps its real outcome:
        // its effect has happened.
        (o) => finish(
          shaper.shape(tool.name, o),
          o.isError ? AuditStatus.error : AuditStatus.ok,
        ),
        onError: (Object e) {
          if (e is CancelledException || ctx.cancel.isCancelled) {
            finish(ToolOutcome.cancelled(), AuditStatus.cancelled);
          } else {
            finish(
              shaper.shape(
                tool.name,
                ToolOutcome.error(
                  'Fehler bei ${tool.name} (${e.runtimeType}): '
                  '${sanitizeErrorText(e)}',
                ),
              ),
              AuditStatus.error,
            );
          }
        },
      ),
    );
    try {
      return await result.future;
    } finally {
      timer.cancel();
    }
  }

  void _audit(ToolAuditEntry entry) {
    final sink = audit;
    if (sink == null) return;
    try {
      sink.record(entry);
    } on Object catch (e, s) {
      // Not swallowed: reported to the zone, but the run goes on.
      Zone.current.handleUncaughtError(e, s);
    }
  }

  /// Result summary of a call that waits for the unlock (WP154 L2).
  static const unlockSummary = 'Entsperren nötig';

  /// Result summary of a call that is allowed locked but works only
  /// unlocked (WP163 B): not executed, remembered for the unlock.
  static const deferredSummary = 'Nur entsperrt';

  /// Text of that outcome for the model (the run ends there anyway).
  static const deferredText =
      'Nicht ausgeführt: die Aktion wirkt nur bei entsperrtem Gerät. Sie wird '
      'nach dem Entsperren ausgeführt; nicht wiederholen.';

  static ToolOutcome _deniedOutcome(PolicyDecision d) => ToolOutcome.error(
    d.reason ?? RiskPolicy.deniedReason,
    summary: d.needsUnlock ? unlockSummary : null,
  );

  /// Error text for a call to an unknown or inactive tool.
  static String unknownToolText(String name) =>
      'Unbekanntes Tool „$name“. Nutze nur Tools aus der Tool-Liste.';

  /// Error text for arguments that are no JSON object.
  static const invalidJsonText =
      'Die Argumente sind kein gültiges JSON-Objekt. Bitte die Argumente als '
      'JSON-Objekt übergeben, z. B. {"feld": "wert"}.';

  /// Empty arguments are accepted as `{}` (some providers send "" for tools
  /// without parameters).
  static Map<String, Object?>? _decode(ToolCallBlock call) =>
      call.argumentsJson.trim().isEmpty
      ? <String, Object?>{}
      : call.tryDecodeArguments();

  /// Error text when the runtime itself failed for [callName].
  static String internalErrorText(String callName, Object error) =>
      'Interner Fehler bei „$callName“ (${error.runtimeType}).';

  /// Error text when [tool] did not answer within [timeout]. For `write` and
  /// `external` tools the effect is unknown, so the model must not simply
  /// retry.
  static String timeoutText(Tool tool, Duration timeout) {
    final base =
        'Zeitüberschreitung: ${tool.name} hat nicht innerhalb von '
        '${_format(timeout)} geantwortet.';
    return tool.risk == RiskLevel.read
        ? base
        : '$base Die Wirkung ist unklar: nicht automatisch wiederholen, '
              'sondern erst prüfen oder den Nutzer fragen.';
  }

  static String _format(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds} s'
      : '${d.inMilliseconds} ms';

  static _Result _cancelled(AuditDecision decision) =>
      (ToolOutcome.cancelled(), AuditStatus.cancelled, decision);
}

typedef _Result = (ToolOutcome, AuditStatus, AuditDecision);
