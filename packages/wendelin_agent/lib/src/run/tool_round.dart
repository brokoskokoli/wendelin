/// One tool round of an agent run (concept: „Agent-Schleife“, K10 a): call
/// ids, refusal of tools the target may not see, repetition after an
/// escalation, execution through the [ToolInvoker] with confirmations, and
/// refused rounds at a limit. Internal to `wendelin_agent`, not exported.
library;

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../agent_config.dart';
import '../agent_runner_texts.dart';
import '../context_builder.dart';
import 'attestation_gate.dart';
import 'privacy_scope.dart';
import 'run_config.dart';
import 'run_state.dart';

/// Executes the tool calls of one model answer.
///
/// Invariants:
/// - A call to a tool outside the current target's catalog never reaches
///   the invoker; it is refused, reported to [AgentRunner.onToolRefused]
///   and marked in the [PrivacyScope].
/// - A call that repeats an earlier execution (same model id and content,
///   or same content at a previous provider and not declined) is not run
///   again.
/// - Every tool call gets exactly one result, also when the invoker breaks
///   its contract or the round is refused ([refuse]).
final class ToolRound {
  /// Creates the tool rounds of [runner]'s run.
  ToolRound(
    this.runner,
    this._state,
    this._privacy,
    this._control,
    this._attest,
  );

  /// The runner (invoker, session, clock, device).
  final RunConfig runner;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunControl _control;
  final AttestationGate _attest;

  /// Id the model sent for each (possibly renamed) call id.
  final Map<String, String> _sourceIds = {};

  /// Ids every provider accepts (Anthropic: `^[a-zA-Z0-9_-]+$`).
  static final _validId = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _invalidIdChars = RegExp('[^A-Za-z0-9_-]');

  /// Gives every tool call an id that is unique in the conversation and
  /// consists only of `[A-Za-z0-9_-]`. Weak servers repeat ids such as
  /// `call_0` or send empty ones; such a call gets an internal id
  /// (`call_0_dup1`, `call_dup1`; other characters become `_`) so that
  /// tool_use and tool_result stay consistent across providers.
  /// [_sourceIds] keeps the id the model sent.
  (Message, List<ToolCallBlock>) assignCallIds(List<ContentBlock> blocks) {
    final used = {
      for (final m in _state.messages)
        for (final c in m.toolCalls) c.id,
    };
    final out = <ContentBlock>[];
    final calls = <ToolCallBlock>[];
    for (final b in blocks) {
      if (b is! ToolCallBlock) {
        out.add(b);
        continue;
      }
      var call = b;
      final valid = _validId.hasMatch(b.id);
      if (!valid || used.contains(b.id)) {
        final base = b.id.isEmpty
            ? 'call'
            : b.id.replaceAll(_invalidIdChars, '_');
        var id = base;
        if (b.id.isEmpty || used.contains(id)) {
          var n = 1;
          while (used.contains('${base}_dup$n')) {
            n++;
          }
          id = '${base}_dup$n';
        }
        call = ToolCallBlock(
          id: id,
          name: b.name,
          argumentsJson: b.argumentsJson,
        );
      }
      used.add(call.id);
      _sourceIds[call.id] = b.id;
      out.add(call);
      calls.add(call);
    }
    return (Message.assistant(out), calls);
  }

  /// Executes [calls] and verifies the answer that asked for them; returns
  /// one result per call, in call order.
  Future<List<ToolResultBlock>> run(
    List<ToolCallBlock> calls,
    AttestationStep? step,
  ) async {
    final round = await execute(calls, step);
    await verify(round);
    return resultsOf(round);
  }

  /// Executes [calls] without waiting for the receipt of the answer that
  /// asked for them (except `external` ones, which wait for green).
  /// [step] is the check of that answer ([ModelReply.step]): a model call
  /// that overlaps the check (WP81b) begins other steps meanwhile.
  Future<ToolRoundRun> execute(
    List<ToolCallBlock> calls,
    AttestationStep? step,
  ) async {
    final results = <String, ToolResultBlock>{};
    final pending = <ToolCallBlock>[];
    final catalog = _privacy.catalog;
    for (final call in calls) {
      final outcome = _answerWithoutInvoking(call, catalog);
      if (outcome == null) {
        pending.add(call);
        continue;
      }
      _control.emit(ToolCallStarted(call));
      _control.emit(ToolCallFinished(call: call, outcome: outcome));
      results[call.id] = outcome.toResultBlock(call.id);
    }

    final hadExternal = pending.any(_isExternal);
    if (pending.isNotEmpty) await _invokeGated(pending, results, step);
    return ToolRoundRun._(
      calls,
      pending,
      results,
      step,
      // With an `external` call the round already waited for green.
      overlappable: step?.report != null && !hadExternal,
    );
  }

  /// Waits for the receipt of the answer that caused [round] and reports its
  /// status (once per model call). Tools with an undo ran at once, before the
  /// receipt was known. Anything but a green receipt (red, not confirmed,
  /// missing) takes them back, like `external` calls never run without
  /// green (WP77). Returns whether the receipt is green.
  ///
  /// [onNotGreen] runs before the red status event goes out (WP81c: the
  /// overlapping call takes back its output first).
  Future<bool> verify(ToolRoundRun round, {void Function()? onNotGreen}) async {
    final report = await _attest.settle(round.step, onNotGreen: onNotGreen);
    final green = report?.status == AttestationStatus.green;
    if (round.step?.report != null && !green) {
      await _undoUnverified(round.pending, round.results);
    }
    return green;
  }

  /// The results of [round], one per call in call order. Every tool_use needs
  /// a tool_result, even if an invoker broke its contract.
  List<ToolResultBlock> resultsOf(ToolRoundRun round) => [
    for (final call in round.calls)
      round.results[call.id] ??
          ToolOutcome.error('Kein Ergebnis vom Tool erhalten')
              .toResultBlock(call.id),
  ];

  /// Undoes the calls of [pending] that ran with an [UndoAction] before the
  /// answer that asked for them turned out red: the user did not get a
  /// verified answer and must not be left with its effects. Each call gets
  /// an error result for the model and a second [ToolCallFinished] (the
  /// card turns from done to failed with the reason); a failing undo says
  /// so. Calls without undo (`external` ones never run before a green
  /// receipt) are not touched.
  Future<void> _undoUnverified(
    List<ToolCallBlock> pending,
    Map<String, ToolResultBlock> results,
  ) async {
    final ids = {for (final c in pending) c.id};
    for (final e in List.of(_state.executed)) {
      final undo = e.outcome.undo;
      if (undo == null || e.outcome.isError || !ids.contains(e.call.id)) {
        continue;
      }
      ToolOutcome outcome;
      var failed = false;
      try {
        await undo.run();
        outcome = ToolOutcome.error(
          AgentRunnerTexts.undoneUnverified,
          summary: 'Rückgängig gemacht (Antwort nicht verifiziert)',
        );
      } on Object {
        outcome = ToolOutcome.error(
          AgentRunnerTexts.undoFailedUnverified,
          summary: 'Rückgängig machen fehlgeschlagen',
        );
        failed = true;
        runner.onUndoFailed?.call(runner.sessionId, e.call);
      }
      _control.emit(ToolCallFinished(call: e.call, outcome: outcome));
      // Also on the voice path: the card alone is not seen by voice users.
      if (failed) {
        _control.emit(const AgentTextDelta(AgentRunnerTexts.undoFailedNotice));
      }
      results[e.call.id] = outcome.toResultBlock(e.call.id);
    }
  }

  /// The outcome of [call] if it must not reach the invoker: refused (not
  /// in [catalog]) or already executed. `null` = invoke it.
  ToolOutcome? _answerWithoutInvoking(ToolCallBlock call, ToolCatalog catalog) {
    if (_privacy.perTarget && catalog.lookup(call.name) == null) {
      // Invariant: not offered to this target (e.g. sensitive tool,
      // standard provider), so it never reaches the invoker.
      _privacy.refuse(call.id);
      runner.onToolRefused?.call(runner.sessionId, call);
      return ToolOutcome.error(AgentRunnerTexts.hiddenTool(call.name));
    }
    final earlier = _earlierExecution(call);
    if (earlier == null) return null;
    return ToolOutcome(
      content: [
        const TextBlock(
          'Bereits ausgeführt, nicht wiederholt. Früheres Ergebnis:',
        ),
        ...earlier.outcome.content,
      ],
      isError: earlier.outcome.isError,
      summary: 'Bereits ausgeführt',
    );
  }

  /// Like [_invoke], but with a provider that verifies its answers
  /// afterwards (TEE): `external` calls start only after a green
  /// verification, everything else runs at once. Invariant (fail-closed):
  /// a red or missing verification refuses the `external` calls; they never
  /// reach the invoker.
  Future<void> _invokeGated(
    List<ToolCallBlock> pending,
    Map<String, ToolResultBlock> results,
    AttestationStep? step,
  ) async {
    final external = [
      for (final call in pending)
        if (_isExternal(call)) call,
    ];
    if (step?.report == null || external.isEmpty) {
      return _invoke(pending, results);
    }
    final immediate = [
      for (final call in pending)
        if (!external.contains(call)) call,
    ];
    if (immediate.isNotEmpty) await _invoke(immediate, results);
    final report = await _attest.settle(step);
    if (report?.status == AttestationStatus.green) {
      return _invoke(external, results);
    }
    for (final call in external) {
      final outcome = ToolOutcome.error(AgentRunnerTexts.unverifiedAnswer);
      _control.emit(ToolCallStarted(call));
      _control.emit(ToolCallFinished(call: call, outcome: outcome));
      results[call.id] = outcome.toResultBlock(call.id);
    }
  }

  /// Whether [call] is effectively `external` for the invoker's policy (own
  /// level or made confirm-only by the user or an integration). Without a
  /// [ToolRiskAssessor] the contract is fail-closed: everything except
  /// [RiskLevel.read] counts as `external` and waits for the receipt.
  bool _isExternal(ToolCallBlock call) {
    final tool = _privacy.catalog.lookup(call.name);
    if (tool == null) return false;
    final invoker = runner.invoker;
    final risk = invoker is ToolRiskAssessor
        ? (invoker as ToolRiskAssessor).effectiveRisk(
            tool,
            runner.sessionId,
            foreignContent: _state.untrustedSeen,
          )
        : (tool.risk == RiskLevel.read ? RiskLevel.read : RiskLevel.external);
    return risk == RiskLevel.external;
  }

  /// Runs [pending] through the invoker and collects their [results].
  Future<void> _invoke(
    List<ToolCallBlock> pending,
    Map<String, ToolResultBlock> results,
  ) async {
    final current = _state.current;
    final ctx = ToolContext(
      sessionId: runner.sessionId,
      clock: runner.clock,
      locale: runner.contextBuilder.device.locale,
      timeZone: runner.contextBuilder.device.timeZone,
      cancel: _control.token,
      privacyLevel: current.privacy,
      // Tools persist with the run's (possibly tainted) floor.
      privacyFloor: current.privacyFloor,
      memoryOwner: runner.memoryOwner,
      foreignContentSeen: _state.untrustedSeen,
    );
    await for (final event in runner.invoker.invokeAll(pending, ctx)) {
      switch (event) {
        case ToolStarted(:final call):
          _control.emit(ToolCallStarted(call));
        case ConfirmationNeeded(:final call, :final description):
          _control.emit(
            ConfirmationRequired(
              call: call,
              description: description,
              respond: event.respond,
              risk: event.risk,
              privateDetails: event.privateDetails,
            ),
          );
        case ToolFinished(:final call, :final outcome, :final duration):
          // Invariant (fail-closed): every result that is not explicitly
          // trusted switches the invisible speech text off.
          if (!isTrustedResult(
            _privacy.catalog,
            call.name,
            isError: outcome.isError,
            content: outcome.content,
          )) {
            _state.untrustedSeen = true;
          }
          _state.executed.add((call: call, outcome: outcome));
          _control.emit(
            ToolCallFinished(call: call, outcome: outcome, duration: duration),
          );
          results[call.id] = outcome.toResultBlock(call.id);
      }
    }
  }

  /// How often the model may send the same failing call (same tool, same
  /// arguments, error each time) before the run stops with that error.
  static const maxSameFailures = 3;

  /// The tool, error text and number of a call of [round] that failed [maxSameFailures] times
  /// in this run with the same tool and arguments, or `null`. The model gets
  /// the error in every result; if it still repeats the call, the run ends
  /// instead of spinning until the round limit (WP150).
  ({String tool, String error, int count})? repeatedFailure(
    ToolRoundRun round,
  ) {
    for (final call in round.pending) {
      final same = [
        for (final e in _state.executed)
          if (e.outcome.isError && _sameContent(e.call, call)) e,
      ];
      if (same.length >= maxSameFailures) {
        final text = same.last.outcome.content
            .whereType<TextBlock>()
            .map((b) => b.text)
            .join(' ')
            .trim();
        return (tool: call.name, error: text, count: same.length);
      }
    }
    return null;
  }

  /// The stop for a [round] whose call failed [maxSameFailures] times (see
  /// [repeatedFailure]) or whose outcome ends the run ([ToolOutcome.endsRun],
  /// WP163 B), or `null`. Closes the round first so every call has a result.
  Future<RunStop?> stopOnRepeatedFailure(
    ToolRoundRun round,
    AgentConfig config,
  ) async {
    final error = repeatedFailure(round);
    if (error == null && !_endsRun(_state.executed, round)) return null;
    await verify(round);
    await _state.append(Message.toolResults(resultsOf(round)));
    return _stopOf(error, config);
  }

  /// The earlier execution [call] would repeat, if any: a call with the
  /// same id from the model *and* the same tool and arguments. Equal ids
  /// with other content are an id collision, not a repetition (see
  /// [assignCallIds]).
  Executed? _earlierExecution(ToolCallBlock call) {
    final sourceId = _sourceIds[call.id] ?? call.id;
    for (final e in _state.executed) {
      if (!_sameContent(e.call, call)) continue;
      final earlierId = _sourceIds[e.call.id] ?? e.call.id;
      if (sourceId.isNotEmpty && earlierId == sourceId) return e;
    }
    return null;
  }

  static bool _sameContent(ToolCallBlock a, ToolCallBlock b) {
    if (a.name != b.name) return false;
    final args = b.tryDecodeArguments();
    return args == null
        ? a.argumentsJson == b.argumentsJson
        : const DeepCollectionEquality().equals(a.tryDecodeArguments(), args);
  }

  /// Records [assistant] with error results for [calls] that are not
  /// executed, so every tool call in the history has a result.
  Future<void> refuse(
    Message assistant,
    List<ToolCallBlock> calls,
    String why,
  ) async {
    await _state.append(assistant);
    await _state.append(
      Message.toolResults([
        for (final c in calls)
          ToolOutcome.error('Nicht ausgeführt: $why').toResultBlock(c.id),
      ]),
    );
  }
}

/// The stop for a repeated [error], else for a run ended by a call (WP163 B:
/// cancelled, the caller of the run answers).
RunStop _stopOf(
  ({String tool, String error, int count})? error,
  AgentConfig config,
) => RunStop(
  failedEvent(
    error == null ? AgentErrorKind.cancelled : AgentErrorKind.repeatedToolError,
    config,
    tool: error?.tool,
    detail: error?.error,
    repeats: error?.count,
  ),
);

/// Whether a call of [round] has an outcome that ends the run.
bool _endsRun(Iterable<Executed> executed, ToolRoundRun round) => executed.any(
  (e) => e.outcome.endsRun && round.pending.any((c) => c.id == e.call.id),
);

/// A tool round that was executed and waits for the receipt of its answer.
final class ToolRoundRun {
  ToolRoundRun._(
    this.calls,
    this.pending,
    this.results,
    this.step, {
    required this.overlappable,
  });

  /// All calls of the answer.
  final List<ToolCallBlock> calls;

  /// The calls that reached the invoker.
  final List<ToolCallBlock> pending;

  /// Results by call id; an undo replaces entries.
  final Map<String, ToolResultBlock> results;

  /// The check of the answer that asked for this round (`null`: none).
  final AttestationStep? step;

  /// Whether the next model call may start before the check ends (WP81b):
  /// the answer is verified afterwards and the round had no `external` call.
  final bool overlappable;
}
