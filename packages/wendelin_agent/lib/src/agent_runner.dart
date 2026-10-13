import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'agent_config.dart';
import 'context_builder.dart';
import 'give_up_classifier.dart';
import 'ports.dart';
import 'provider_resolver.dart';
import 'run/escalation.dart';
import 'run/model_call.dart';
import 'run/privacy_scope.dart';
import 'run/run_budget.dart';
import 'run/run_config.dart';
import 'run/run_start.dart';
import 'run/run_state.dart';
import 'run/tool_round.dart';

/// The provider-independent agent loop (concept: „Agent-Schleife“).
///
/// One [run] at a time: build the context, route, call the model with
/// streaming, execute requested tools through the [ToolInvoker], repeat until
/// a final answer or a limit; escalate along the resolver's chain when the
/// model fails. See `docs/adr/0003-agent-loop.md` for the details; the
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
    this.memoryFloor,
    GiveUpClassifier? giveUpClassifier,
  }) : giveUpClassifier = giveUpClassifier ?? GiveUpClassifier();

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

  /// Privacy floor of every memory entry: the lowest level allowed to see
  /// the memory at all (e.g. `tee` for the sensitive memory integration).
  /// Each entry counts with the higher of its own floor and this one, so
  /// weaker targets get no memory in the system prompt, and a run that
  /// does see it is tainted (escalations below ask first). `null` = no
  /// floor besides the entries' own.
  @override
  final PrivacyLevel? memoryFloor;

  /// Detects „kann ich nicht“ answers.
  final GiveUpClassifier giveUpClassifier;

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
/// until a final answer or a limit. Each way it goes on has a named step: [_retryOrEscalateOnError], [_handlePauseTurn],
/// [_answerOrEscalate] and [_toolRound]. The details live in the units under
/// `src/run/`: [PrivacyScope] (what the target may see, taint), [RunBudget]
/// (limits), [Escalation] (hand-over), [ToolRound] (tool execution) and
/// [ModelCall] (request and streaming); [RunState] holds the conversation.
///
/// Invariants (details at the enforcing places):
/// - An abort wins over every error ([drive], [throwIfAborted]).
/// - A failed call is retried at most once per model call before the run
///   escalates ([_retryOrEscalateOnError]).
/// - `pauseTurn` without tool calls continues without counting a round
///   ([_handlePauseTurn]).
/// - [_segmentStreamed] decides whether a retry or hand-over sends an
///   `AgentTextReset` ([emit]).
/// - The privacy floor never sinks and rises to the taint level
///   ([RunState.raiseFloor], [PrivacyScope.raiseFloorToTaint]); counters per
///   provider restart at every hand-over ([RunBudget.onEscalated]).
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

  /// Target, context, messages, paused answer, executed calls, epoch.
  final RunState _state;

  // ------------------------------------------------------------------ units

  late final RunBudget _budget = RunBudget(config);
  late final PrivacyScope _privacy = PrivacyScope(runner, _state);
  late final ToolRound _tools = ToolRound(runner, _state, _privacy, this);
  late final _model = ModelCall(runner, _state, _privacy, _budget, this);
  late final Escalation _escalation = Escalation(
    runner.resolver,
    _state,
    _privacy,
    _budget,
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
      case AgentTextDelta():
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
    if (retry) {
      await _escalation.escalate(EscalationReason.userRequested);
    }

    var retried = false;
    while (true) {
      await _checkBeforeCall();
      final reply = await _model.call();

      if (reply.error case final error?) {
        retried = await _retryOrEscalateOnError(error, retried: retried);
        continue;
      }
      retried = false;
      final (assistant, calls) = _tools.assignCallIds(reply.blocks);

      if (calls.isEmpty && reply.stopReason == StopReason.pauseTurn) {
        _handlePauseTurn(assistant);
        continue;
      }
      if (calls.isEmpty) {
        final done = await _answerOrEscalate(assistant, reply.stopReason);
        if (done != null) return done;
        continue; // handed over after „kann ich nicht“
      }
      // Tool round (also for tool calls in a paused answer: every tool_use
      // gets its tool_result).
      await _toolRound(assistant, calls);
    }
  }

  /// A model call failed with [error]. Returns the new `retried` flag when
  /// the loop goes on (retry or hand-over); else throws the terminal event.
  Future<bool> _retryOrEscalateOnError(
    ProviderException error, {
    required bool retried,
  }) async {
    // Invariant: an abort wins over the error it caused.
    throwIfAborted();
    // Invariant: at most one retry at the same provider per model call;
    // `retried` is reset after every successful call and every hand-over.
    if (error.retryable && !retried) {
      _retryCurrentCall();
      return true;
    }
    if (error.retryable &&
        await _escalation.escalate(EscalationReason.providerError)) {
      return false;
    }
    throwIfAborted();
    throw RunStop(
      AgentFailed(
        error: AgentErrorKind.provider,
        message: 'Der Anbieter hat einen Fehler gemeldet: ${error.message}',
        cause: error,
      ),
    );
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

  /// A final answer: returns [AgentDone], or `null` when it gave up
  /// („kann ich nicht“) and the run was handed over.
  Future<AgentDone?> _answerOrEscalate(
    Message assistant,
    StopReason? stopReason,
  ) async {
    final text = [..._state.paused, assistant].map((m) => m.text).join();
    if (runner.giveUpClassifier.isGiveUp(text) &&
        await _escalation.escalate(EscalationReason.modelGaveUp)) {
      return null;
    }
    await _state.append(assistant);
    return AgentDone(
      finalText: text,
      stopReason: stopReason ?? StopReason.other,
    );
  }

  /// Runs the tool [calls] of [assistant] as one round, unless a limit
  /// refuses it (throws) or the run is handed over for lack of progress.
  Future<void> _toolRound(Message assistant, List<ToolCallBlock> calls) async {
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
    if (_budget.noProgress &&
        await _escalation.escalate(EscalationReason.noProgress)) {
      return;
    }
    _budget.onRound();
    await _state.append(assistant);
    final results = await _tools.run(calls);
    await _state.append(Message.toolResults(results));
    throwIfAborted();

    _budget.onInvalidCalls(calls.where(_tools.isInvalid).length);
    if (_budget.tooManyInvalid) {
      await _escalation.escalate(EscalationReason.invalidToolCalls);
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
