import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'agent_config.dart';
import 'agent_runner_texts.dart';
import 'context_builder.dart';
import 'ports.dart';
import 'provider_resolver.dart';
import 'run/attestation_gate.dart';
import 'run/escalation.dart';
import 'run/fixed_answer.dart';
import 'run/model_call.dart';
import 'run/overlap_control.dart';
import 'run/privacy_scope.dart';
import 'run/retry_offer.dart';
import 'run/run_budget.dart';
import 'run/run_config.dart';
import 'run/run_start.dart';
import 'run/run_state.dart';
import 'run/tool_round.dart';

/// The provider-independent agent loop (concept: „Agent-Schleife“).
///
/// One [run] at a time: build the context, route, call the model with
/// streaming, execute requested tools through the [ToolInvoker], repeat until
/// a final answer or a limit. A failing provider ends the run with the reason;
/// the runner never switches to another provider on its own (K28), only on the
/// user's explicit request („nochmal mit …“) or after a yes to the offer „Mit X
/// nochmal?“ ([RetryOffer]). See `docs/adr/0003-agent-loop.md` for the details; the
/// loop is [_Run], its parts are under `src/run/`.
final class AgentRunner implements AgentRun, RunConfig {
  /// Creates a runner.
  AgentRunner({
    required this.resolver,
    required this.contextBuilder,
    required this.invoker,
    required this.clock,
    required this.sessionId,
    this.recorder,
    this.costEstimator,
    this.budgetGuard,
    this.catalogFor,
    this.onToolRefused,
    this.onUndoFailed,
    this.onFixedConfirmation,
    this.fallbackTargets,
    this.memoryFloor,
    this.memoryOwner = '',
  });

  /// Chooses providers and escalation targets.
  @override
  final ProviderResolver resolver;

  /// Builds system prompt, tool specs and messages.
  @override
  final ContextBuilder contextBuilder;

  /// Executes tool calls.
  @override
  final ToolInvoker invoker;

  /// Time source for limits and tools.
  @override
  final Clock clock;

  /// Session id passed to tools.
  @override
  final String sessionId;

  /// Persists the conversation; `null` = not persisted.
  final ConversationRecorder? recorder;

  /// Prices model calls; `null` = no cost.
  @override
  final CostEstimator? costEstimator;

  /// Checked before every model call; `null` = no budget.
  final BudgetGuard? budgetGuard;

  /// The tools a target with the given privacy level may see (e.g.
  /// `ToolRegistry.catalogFor`). With it, every model call gets the catalog
  /// of the current target – also after an escalation – so TEE or local
  /// targets can use sensitive tools that standard targets never see. Calls
  /// to tools the current target may not see are refused before they reach
  /// the [invoker], and calls and results of such tools in the history are
  /// redacted for that target. `null` = the [ContextBuilder.catalog] for
  /// every target (the [invoker] must then use the same catalog).
  @override
  final ToolCatalog Function(PrivacyLevel level)? catalogFor;

  /// Called for every call refused because the current target may not see
  /// the tool (it never reaches the [invoker], so the app audits it here).
  @override
  final void Function(String sessionId, ToolCallBlock call)? onToolRefused;

  /// Called when an action had to be taken back because its answer was not
  /// verified (TEE) and the undo failed (the app audits it here).
  @override
  final void Function(String sessionId, ToolCallBlock call)? onUndoFailed;

  /// Called per tool whose fixed confirmation sentence ended a request
  /// without a second model call (WP122); the app logs
  /// `confirm=fixed tool=<name>` here.
  @override
  final void Function(String sessionId, String toolName)? onFixedConfirmation;

  /// The other configured targets, best (recommended) first. After a provider
  /// failure the runner offers the first one with at least the privacy level
  /// of the failed target („Mit X nochmal?“, WP128) and hands over only if the
  /// user says yes. `null` = no offer, the run just fails.
  @override
  final List<ProviderTarget> Function()? fallbackTargets;

  /// Privacy floor of every memory entry: the lowest level allowed to see
  /// the memory at all (e.g. `tee` for the sensitive memory integration).
  /// Each entry counts with the higher of its own floor and this one, so
  /// weaker targets get no memory in the system prompt, and a run that
  /// does see it is tainted (escalations below ask first). `null` = no
  /// floor besides the entries' own.
  @override
  final PrivacyLevel? memoryFloor;

  /// Memory namespace of the person this run belongs to (WP92b); passed to
  /// the tools as `ToolContext.memoryOwner`. `''` = the default memory.
  @override
  final String memoryOwner;

  AgentConfig get _config => contextBuilder.config;

  _Run? _active;

  @override
  Stream<AgentEvent> run(UserInput input) {
    if (_active != null) {
      return Stream.value(
        const AgentFailed(
          error: AgentErrorKind.internal,
          message: 'Es läuft bereits eine Anfrage.',
        ),
      );
    }
    final state = _Run(this, input);
    _active = state;
    state.controller.onListen = () => unawaited(state.drive());
    state.controller.onCancel = () => state.abort(AgentErrorKind.cancelled);
    return state.controller.stream;
  }

  @override
  void cancel() => _active?.abort(AgentErrorKind.cancelled);

  /// Frees the runner before the terminal event goes out, so a listener may
  /// start the next run right away.
  void _finished(_Run state) {
    if (identical(_active, state)) _active = null;
  }
}

/// State and loop of one [AgentRunner.run] call.
///
/// [startRun] routes and builds the context, then the loop calls the model
/// until a final answer or a limit. Each way it goes on has a named step: [_retryOnError], [_handlePauseTurn],
/// [_answer] and [_toolRound]. The details live in the units under
/// `src/run/`: [PrivacyScope] (what the target may see, taint), [RunBudget]
/// (limits), [Escalation] (hand-over), [ToolRound] (tool execution) and
/// [ModelCall] (request and streaming); [RunState] holds the conversation.
///
/// Invariants (details at the enforcing places):
/// - An abort wins over every error ([drive], [throwIfAborted]).
/// - A failed call is retried at most once per model call at the same
///   provider; then the run fails with the reason ([_retryOnError]).
/// - `pauseTurn` without tool calls continues without counting a round
///   ([_handlePauseTurn]).
/// - [_segmentStreamed] decides whether a retry or hand-over sends an
///   `AgentTextReset` ([emit]).
/// - The privacy floor never sinks and rises to the taint level
///   ([RunState.raiseFloor], [PrivacyScope.raiseFloorToTaint]).
final class _Run implements RunControl {
  _Run(this.runner, this.input) : _state = RunState(runner.recorder);

  final AgentRunner runner;
  final UserInput input;
  final controller = StreamController<AgentEvent>();
  @override
  final token = CancelToken();

  AgentConfig get config => runner._config;

  // ------------------------------------------------------------ Lauf-Zustand
  // Abort, time limit, event segment and conversation of this run.

  /// Why the run was aborted; the first abort wins.
  AgentErrorKind? _abortKind;

  /// Aborts the run with [AgentErrorKind.timeout] after `maxDuration`.
  Timer? _timer;

  /// When the run started (for the clock check between steps).
  late DateTime _start;

  /// Whether text was streamed in the current segment, i.e. since the last
  /// tool event or text reset (the scope of `AgentTextReset`).
  bool _segmentStreamed = false;

  /// Target, context, messages, paused answer, executed calls.
  final RunState _state;

  // ------------------------------------------------------------------ units

  late final RunBudget _budget = RunBudget(config);
  late final PrivacyScope _privacy = PrivacyScope(runner, _state);
  late final AttestationGate _attest = AttestationGate(this, runner.sessionId);
  late final ToolRound _tools = ToolRound(
    runner,
    _state,
    _privacy,
    this,
    _attest,
  );
  late final FixedAnswer _fixed = FixedAnswer(
    runner,
    _state,
    _privacy,
    this,
    _tools,
  );

  /// The terminal event when a tool round ended the run with a fixed
  /// confirmation sentence (WP122), else `null`.
  AgentDone? _fixedDone;
  late final _model = ModelCall(
    runner,
    _state,
    _privacy,
    _budget,
    this,
    _attest,
  );
  late final Escalation _escalation = Escalation(
    runner.resolver,
    _state,
    _privacy,
    this,
  );
  late final RetryOffer _retryOffer = RetryOffer(
    runner,
    _state,
    _escalation,
    this,
  );

  @override
  bool get segmentStreamed => _segmentStreamed;

  @override
  void emit(AgentEvent e) {
    if (controller.isClosed) return;
    // Invariant: a text delta opens a segment, tool events and resets close
    // it; only an open segment needs an `AgentTextReset` on retry or
    // hand-over.
    switch (e) {
      case AgentTextDelta() || AgentSpokenText():
        _segmentStreamed = true;
      case ToolCallStarted() || ToolCallFinished() || AgentTextReset():
        _segmentStreamed = false;
      case _:
        break;
    }
    controller.add(e);
  }

  /// Aborts the run with [kind] (first abort wins).
  void abort(AgentErrorKind kind) {
    _abortKind ??= kind;
    token.cancel();
  }

  Future<void> drive() async {
    AgentEvent terminal;
    try {
      terminal = await _loop();
    } on RunStop catch (s) {
      terminal = s.event;
    } on Object catch (e) {
      // Invariant: an abort wins over the error it caused.
      terminal = _abortKind != null
          ? _failed(_abortKind!)
          : AgentFailed(
              error: AgentErrorKind.internal,
              message: 'Interner Fehler im Agenten.',
              cause: e,
            );
    } finally {
      _timer?.cancel();
    }
    runner._finished(this);
    emit(terminal);
    await controller.close();
  }

  Future<AgentEvent> _loop() async {
    _start = runner.clock.now();
    _timer = Timer(config.maxDuration, () => abort(AgentErrorKind.timeout));
    final retry = await startRun(runner, input, _state, _privacy, this);
    if (retry &&
        !await _escalation.escalate(EscalationReason.userRequested) &&
        _privacy.consentDeclined) {
      // K28: the user declined the target they asked for; the target routed
      // first does not answer instead.
      throw RunStop(
        AgentFailed(
          error: AgentErrorKind.provider,
          message: AgentRunnerTexts.notSent(
            _escalation.declinedName ?? _state.current.target.displayName,
            language: input.language,
          ),
        ),
      );
    }

    var retried = false;
    // The reply of a model call that ran during the receipt check (WP81b).
    ModelReply? ahead;
    while (true) {
      final ModelReply reply;
      if (ahead != null) {
        reply = ahead;
        ahead = null;
      } else {
        await _checkBeforeCall();
        reply = await _model.call();
      }

      if (reply.error case final error?) {
        retried = await _retryOnError(error, retried: retried);
        continue;
      }
      retried = false;
      final (assistant, calls) = _tools.assignCallIds(reply.blocks);

      if (calls.isEmpty && reply.stopReason == StopReason.pauseTurn) {
        _handlePauseTurn(assistant);
        continue;
      }
      if (calls.isEmpty) {
        final done = await _answer(assistant, reply.stopReason);
        return done;
      }
      // Tool round (also for tool calls in a paused answer: every tool_use
      // gets its tool_result).
      ahead = await _toolRound(assistant, calls, reply.step);
      if (_fixedDone case final done?) return done;
    }
  }

  /// A model call failed with [error]. Returns the new `retried` flag when
  /// the loop goes on (retry); else throws the terminal event.
  Future<bool> _retryOnError(
    ProviderException error, {
    required bool retried,
  }) async {
    // Invariant: an abort wins over the error it caused.
    throwIfAborted();
    // Invariant: at most one retry at the same provider per model call;
    // `retried` is reset after every successful call and every hand-over.
    if (error is AttestationFailedException) {
      return _onAttestationError(error, retried: retried);
    }
    if (error.retryable && !retried) {
      _retryCurrentCall();
      return true;
    }
    // Invariant (K28): after the retry the run ends with the reason, unless
    // the user accepts the offer „Mit X nochmal?“ ([_offerRetry]).
    throwIfAborted();
    if (await _offerRetry(error)) return false;
    throw RunStop(
      AgentFailed(
        error: AgentErrorKind.provider,
        message: AgentRunnerTexts.providerFailure(
          _state.current.target.displayName,
          error,
          language: input.language,
        ),
        cause: error,
      ),
    );
  }

  /// A TEE check failed. Invariant: a failed or impossible check (session,
  /// receipt, GPU) never hands the request to another provider silently.
  /// Only a check that could not be completed (`unavailable`) is retried
  /// once at the same provider; then the user is offered another provider
  /// with at least the same privacy level ([_offerRetry]), else the run
  /// ends with the reason. The GPU dialog „Ohne GPU-Prüfung
  /// senden“ stays with the same provider.
  Future<bool> _onAttestationError(
    AttestationFailedException error, {
    required bool retried,
  }) async {
    if (error.unavailable && !retried) {
      _retryCurrentCall();
      return true;
    }
    throwIfAborted();
    if (await _offerRetry(error)) return false;
    throw RunStop(
      AgentFailed(
        error: AgentErrorKind.provider,
        message: AgentRunnerTexts.providerFailure(
          _state.current.target.displayName,
          error,
          language: input.language,
        ),
        cause: error,
      ),
    );
  }

  /// After the retry failed: offers another provider (WP128). Returns
  /// whether the user accepted and the run goes on there. The time the user
  /// needs to decide does not count towards the duration limit.
  Future<bool> _offerRetry(ProviderException error) async {
    final target = _retryOffer.candidate(error);
    if (target == null) return false;
    _timer?.cancel();
    if (!await _retryOffer.offer(error, target)) return false;
    _start = runner.clock.now();
    _timer = Timer(config.maxDuration, () => abort(AgentErrorKind.timeout));
    return true;
  }

  /// Before retrying a failed call at the same provider: drop the text it
  /// streamed. Paused segments of this answer stay in the request; as the
  /// reset also clears them in the UI, their text is sent again.
  void _retryCurrentCall() {
    if (!_segmentStreamed) return;
    emit(const AgentTextReset('Neuer Versuch nach Fehler'));
    final kept = _state.paused.map((m) => m.text).join();
    if (kept.isNotEmpty) emit(AgentTextDelta(kept));
  }

  /// The model paused its turn (`StopReason.pauseTurn`) without tool calls.
  void _handlePauseTurn(Message assistant) {
    // Invariant: the turn continues with the next call without counting a
    // tool round. The segment is kept for the continuation and recorded
    // once the answer stands.
    _state.messages.add(assistant);
    _state.paused.add(assistant);
  }

  /// A final answer ends the run with [AgentDone]; an answer like „kann ich
  /// nicht“ is shown as it is.
  Future<AgentDone> _answer(Message assistant, StopReason? stopReason) async {
    final text = [..._state.paused, assistant].map((m) => m.text).join();
    await _state.append(assistant);
    return AgentDone(
      finalText: text,
      stopReason: stopReason ?? StopReason.other,
    );
  }

  /// Runs the tool [calls] of [assistant] as one round, unless a limit
  /// refuses it (throws). Returns the reply of the next model call if it
  /// already ran during the receipt check ([_overlap]), else `null`.
  Future<ModelReply?> _toolRound(
    Message assistant,
    List<ToolCallBlock> calls,
    AttestationStep? step,
  ) async {
    // Invariant: at most `maxToolRounds` rounds; the next one is refused
    // with a result for every call, then the run ends.
    if (_budget.roundLimitReached) {
      await _tools.refuse(assistant, calls, 'Limit der Tool-Runden erreicht');
      throw RunStop(_failed(AgentErrorKind.toolRoundLimit));
    }
    if (_budget.tokensExhausted) {
      await _tools.refuse(assistant, calls, 'Token-Budget aufgebraucht');
      throw RunStop(_failed(AgentErrorKind.tokenBudget));
    }
    _budget.onRound();
    await _state.append(assistant);
    final round = await _tools.execute(calls, step);
    // WP122: every call succeeded and has a template → no second model call.
    final sentence = _fixed.sentenceFor(
      round,
      input.language ?? input.interfaceLanguage,
    );
    if (sentence != null) {
      _fixedDone = await _fixed.finish(round, sentence);
      throwIfAborted();
      return null;
    }
    ModelReply? ahead;
    if (round.overlappable) {
      ahead = await _overlap(round);
    } else {
      await _tools.verify(round);
      await _state.append(Message.toolResults(_tools.resultsOf(round)));
    }
    throwIfAborted();
    return ahead;
  }

  /// The next model call starts now, while the receipt of the answer that
  /// caused [round] is still being fetched (WP81b).
  ///
  /// Invariants:
  /// - The call's text, speech and thinking events go out at once
  ///   ([OverlapControl], WP81c); its tool calls run in the loop, which only
  ///   gets the reply after the green receipt.
  /// - Anything but green drops the call: cancelled, `AgentTextReset` before
  ///   the red status event of the previous answer, its reply never in the
  ///   history; paid tokens are still reported. The undo ran as without the
  ///   overlap and the loop calls the model again; it sees the undone
  ///   results.
  /// - An abort ends both: the call's token follows the run's.
  Future<ModelReply?> _overlap(ToolRoundRun round) async {
    // The request needs the results; they are recorded once the receipt is
    // known (an undo changes them).
    final provisional = Message.toolResults(_tools.resultsOf(round));
    _state.messages.add(provisional);
    void dropProvisional() =>
        _state.messages.removeWhere((m) => identical(m, provisional));
    final overlap = OverlapControl(this);
    Future<ModelReply>? call;
    try {
      try {
        await _checkBeforeCall();
      } on RunStop {
        dropProvisional();
        await _tools.verify(round);
        await _state.append(Message.toolResults(_tools.resultsOf(round)));
        rethrow;
      }
      // Paid tokens count in any case: the call shares the run's budget.
      // A discarded call is still paid for: its tokens count towards the run
      // budget and may end the run with tokenBudget. If it ends only after the
      // run, its usage is no longer reported.
      call = ModelCall(
        runner,
        _state,
        _privacy,
        _budget,
        overlap,
        _attest,
      ).call();
      // Failures surface where the reply is awaited.
      call.ignore();
      if (await _tools.verify(round, onNotGreen: overlap.discard)) {
        overlap.verified();
        // Recorded at once: an abort during the call keeps the history whole.
        await _state.record(provisional);
        return await call;
      }
      overlap.discard();
      dropProvisional();
      await _state.append(Message.toolResults(_tools.resultsOf(round)));
      return null;
    } finally {
      // Not verified (abort, error): the call must not go on.
      if (call != null) overlap.abandon();
    }
  }

  // ---------------------------------------------------------------- limits

  Future<void> _checkBeforeCall() async {
    if (_abortKind == null &&
        runner.clock.now().difference(_start) >= config.maxDuration) {
      abort(AgentErrorKind.timeout);
    }
    throwIfAborted();
    if (_budget.tokensExhausted) {
      throw RunStop(_failed(AgentErrorKind.tokenBudget));
    }
    await _budget.checkGuard(runner.budgetGuard, _state.current, this);
    throwIfAborted();
  }

  @override
  void throwIfAborted() {
    if (_abortKind case final kind?) throw RunStop(_failed(kind));
  }

  AgentFailed _failed(AgentErrorKind kind) => failedEvent(kind, config);
}
