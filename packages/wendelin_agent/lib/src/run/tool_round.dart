/// One tool round of an agent run (concept: „Agent-Schleife“, K10 a): call
/// ids, refusal of tools the target may not see, repetition after an
/// escalation, execution through the [ToolInvoker] with confirmations, and
/// refused rounds at a limit. Internal to `wendelin_agent`, not exported.
library;

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

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

  /// Executes [calls]; returns one result per call, in call order.
  Future<List<ToolResultBlock>> run(List<ToolCallBlock> calls) async {
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

    if (pending.isNotEmpty) await _invokeGated(pending, results);
    // Status of the answer that caused this round (once per model call).
    await _attest.settle();

    // Every tool_use needs a tool_result, even if an invoker broke its
    // contract.
    return [
      for (final call in calls)
        results[call.id] ??
            ToolOutcome.error('Kein Ergebnis vom Tool erhalten')
                .toResultBlock(call.id),
    ];
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
  ) async {
    final external = [
      for (final call in pending)
        if (_isExternal(call)) call,
    ];
    if (!_attest.expectsReport || external.isEmpty) {
      return _invoke(pending, results);
    }
    final immediate = [
      for (final call in pending)
        if (!external.contains(call)) call,
    ];
    if (immediate.isNotEmpty) await _invoke(immediate, results);
    final report = await _attest.settle();
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
        ? (invoker as ToolRiskAssessor).effectiveRisk(tool, runner.sessionId)
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
            ),
          );
        case ToolFinished(:final call, :final outcome, :final duration):
          // Invariant (fail-closed): every result that is not explicitly
          // trusted switches the invisible speech text off.
          if (!isTrustedResult(
            _privacy.catalog,
            call.name,
            isError: outcome.isError,
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
