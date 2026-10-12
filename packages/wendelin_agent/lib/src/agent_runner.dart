import 'dart:async';

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'agent_config.dart';
import 'context_builder.dart';
import 'give_up_classifier.dart';
import 'ports.dart';
import 'provider_resolver.dart';

/// The provider-independent agent loop (concept: „Agent-Schleife“).
///
/// One [run] at a time: build the context, route, call the model with
/// streaming, execute requested tools through the [ToolInvoker], repeat until
/// a final answer or a limit; escalate along the resolver's chain when the
/// model fails. See `docs/adr/0003-agent-loop.md` for the details.
final class AgentRunner implements AgentRun {
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
    GiveUpClassifier? giveUpClassifier,
  }) : giveUpClassifier = giveUpClassifier ?? GiveUpClassifier();

  /// Chooses providers and escalation targets.
  final ProviderResolver resolver;

  /// Builds system prompt, tool specs and messages.
  final ContextBuilder contextBuilder;

  /// Executes tool calls.
  final ToolInvoker invoker;

  /// Time source for limits and tools.
  final Clock clock;

  /// Session id passed to tools.
  final String sessionId;

  /// Persists the conversation; `null` = not persisted.
  final ConversationRecorder? recorder;

  /// Prices model calls; `null` = no cost.
  final CostEstimator? costEstimator;

  /// Checked before every model call; `null` = no budget.
  final BudgetGuard? budgetGuard;

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

/// Result of one model call.
final class _ModelReply {
  _ModelReply(this.blocks, this.stopReason, this.error);

  final List<ContentBlock> blocks;
  final StopReason? stopReason;
  final ProviderException? error;

  List<ToolCallBlock> get toolCalls =>
      blocks.whereType<ToolCallBlock>().toList();

  String get text => blocks.whereType<TextBlock>().map((b) => b.text).join();
}

/// A run ended early (abort or limit); carries the terminal event.
final class _Stop implements Exception {
  _Stop(this.event);
  final AgentFailed event;
}

/// An executed tool call; [epoch] counts escalations before it.
typedef _Executed = ({ToolCallBlock call, ToolOutcome outcome, int epoch});

/// State of one [AgentRunner.run] call.
final class _Run {
  _Run(this.runner, this.input);

  final AgentRunner runner;
  final UserInput input;
  final controller = StreamController<AgentEvent>();
  final token = CancelToken();

  AgentConfig get config => runner._config;

  AgentErrorKind? _abortKind;
  Timer? _timer;
  late DateTime _start;
  late Resolution _current;
  late AgentContext _context;
  final List<Message> _messages = [];
  final List<_Executed> _executed = [];
  int _epoch = 0;
  int _tokensSpent = 0;
  int _rounds = 0;
  int _roundsOnProvider = 0;
  int _invalidOnProvider = 0;
  bool _consentDeclined = false;
  final Set<String> _budgetWarned = {};

  /// Assistant messages of a paused turn (`StopReason.pauseTurn`), not yet
  /// recorded.
  final List<Message> _paused = [];

  /// Id the model sent for each (possibly renamed) call id.
  final Map<String, String> _sourceIds = {};

  /// Whether text was streamed in the current segment, i.e. since the last
  /// tool event or text reset (the scope of `AgentTextReset`).
  bool _segmentStreamed = false;

  void emit(AgentEvent e) {
    if (controller.isClosed) return;
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
    } on _Stop catch (s) {
      terminal = s.event;
    } on Object catch (e) {
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

    _current = runner.resolver.resolve(input);
    emit(
      Routed(
        profileId: _current.profileId,
        modelId: _current.modelId,
        reason: _current.reason,
      ),
    );
    _context = await runner.contextBuilder.build(input);
    _messages.addAll(_context.messages);
    await _record(_context.messages.last);

    if (input.requestEscalation) {
      await _escalate(EscalationReason.userRequested);
    }

    var retried = false;
    while (true) {
      await _checkBeforeCall();
      final reply = await _callModel();

      if (reply.error case final error?) {
        _throwIfAborted();
        if (error.retryable && !retried) {
          retried = true;
          _retryCurrentCall();
          continue;
        }
        if (error.retryable &&
            await _escalate(EscalationReason.providerError)) {
          retried = false;
          continue;
        }
        _throwIfAborted();
        throw _Stop(
          AgentFailed(
            error: AgentErrorKind.provider,
            message: 'Der Anbieter hat einen Fehler gemeldet: ${error.message}',
            cause: error,
          ),
        );
      }
      retried = false;
      final (assistant, calls) = _assignCallIds(reply.blocks);

      if (calls.isEmpty && reply.stopReason == StopReason.pauseTurn) {
        // Kept for the continuation, recorded once the answer stands.
        _messages.add(assistant);
        _paused.add(assistant);
        continue;
      }

      if (calls.isEmpty) {
        final text = [..._paused, assistant].map((m) => m.text).join();
        if (runner.giveUpClassifier.isGiveUp(text) &&
            await _escalate(EscalationReason.modelGaveUp)) {
          continue;
        }
        await _append(assistant);
        return AgentDone(
          finalText: text,
          stopReason: reply.stopReason ?? StopReason.other,
        );
      }

      // Tool round (also for tool calls in a paused answer: every tool_use
      // gets its tool_result).
      if (_rounds >= config.maxToolRounds) {
        await _refuseRound(assistant, calls, 'Limit der Tool-Runden erreicht');
        throw _Stop(_failed(AgentErrorKind.toolRoundLimit));
      }
      if (_tokensSpent >= config.maxTokensPerRequest) {
        await _refuseRound(assistant, calls, 'Token-Budget aufgebraucht');
        throw _Stop(_failed(AgentErrorKind.tokenBudget));
      }
      if (_roundsOnProvider >= config.escalateAfterRoundsWithoutResult &&
          await _escalate(EscalationReason.noProgress)) {
        continue;
      }
      _rounds++;
      _roundsOnProvider++;
      await _append(assistant);
      final results = await _runTools(calls);
      await _append(Message.toolResults(results));
      _throwIfAborted();

      _invalidOnProvider += calls.where(_isInvalid).length;
      if (_invalidOnProvider >= config.escalateAfterInvalidToolCalls) {
        if (await _escalate(EscalationReason.invalidToolCalls)) continue;
      }
    }
  }

  /// Before retrying a failed call at the same provider: drop the text it
  /// streamed. Paused segments of this answer stay in the request; as the
  /// reset also clears them in the UI, their text is sent again.
  void _retryCurrentCall() {
    if (!_segmentStreamed) return;
    emit(const AgentTextReset('Neuer Versuch nach Fehler'));
    final kept = _paused.map((m) => m.text).join();
    if (kept.isNotEmpty) emit(AgentTextDelta(kept));
  }

  /// Gives every tool call an id that is unique in the conversation. Weak
  /// servers repeat ids such as `call_0` or send empty ones; a colliding
  /// call gets an internal id so that tool_use and tool_result stay
  /// consistent. [_sourceIds] keeps the id the model sent.
  (Message, List<ToolCallBlock>) _assignCallIds(List<ContentBlock> blocks) {
    final used = {
      for (final m in _messages)
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
      if (b.id.isEmpty || used.contains(b.id)) {
        final base = b.id.isEmpty ? 'call' : b.id;
        var n = 2;
        while (used.contains('$base~$n')) {
          n++;
        }
        call = ToolCallBlock(
          id: '$base~$n',
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

  // ---------------------------------------------------------------- limits

  Future<void> _checkBeforeCall() async {
    if (_abortKind == null &&
        runner.clock.now().difference(_start) >= config.maxDuration) {
      abort(AgentErrorKind.timeout);
    }
    _throwIfAborted();
    if (_tokensSpent >= config.maxTokensPerRequest) {
      throw _Stop(_failed(AgentErrorKind.tokenBudget));
    }
    final budget = await runner.budgetGuard?.check(_current.profileId);
    switch (budget?.status) {
      case BudgetStatus.block:
        throw _Stop(_failed(AgentErrorKind.budgetBlocked));
      case BudgetStatus.warn when _budgetWarned.add(_current.profileId):
        emit(
          BudgetWarning(
            profileId: _current.profileId,
            spentMicros: budget!.spentMicros,
            budgetMicros: budget.budgetMicros,
          ),
        );
      case _:
        break;
    }
    _throwIfAborted();
  }

  void _throwIfAborted() {
    if (_abortKind case final kind?) throw _Stop(_failed(kind));
  }

  AgentFailed _failed(AgentErrorKind kind) => AgentFailed(
    error: kind,
    message: switch (kind) {
      AgentErrorKind.cancelled => 'Abgebrochen.',
      AgentErrorKind.timeout =>
        'Das hat zu lange gedauert, ich habe nach '
            '${config.maxDuration.inSeconds} Sekunden abgebrochen.',
      AgentErrorKind.toolRoundLimit =>
        'Ich bin nach ${config.maxToolRounds} Tool-Runden zu keinem '
            'Ergebnis gekommen und habe abgebrochen.',
      AgentErrorKind.tokenBudget =>
        'Das Token-Budget für diese Anfrage ist aufgebraucht.',
      AgentErrorKind.budgetBlocked =>
        'Das Monatsbudget für diesen Anbieter ist erreicht.',
      AgentErrorKind.provider => 'Der Anbieter ist nicht erreichbar.',
      AgentErrorKind.internal => 'Interner Fehler im Agenten.',
    },
  );

  // ----------------------------------------------------------- model call

  Future<_ModelReply> _callModel() async {
    final target = _current;
    final request = ChatRequest(
      messages: _messages,
      model: target.modelId,
      maxTokens: config.maxOutputTokens,
      tools: _context.tools,
      temperature: config.temperature,
      systemPrompt: _systemPrompt(),
      metadata: {'sessionId': runner.sessionId},
    );
    final blocks = <ContentBlock>[];
    Usage? usage;
    StopReason? stopReason;
    ProviderException? error;

    await for (final event in target.provider.chat(request, cancel: token)) {
      switch (event) {
        case TextDelta(text: final delta):
          if (delta.isEmpty) break;
          emit(AgentTextDelta(delta));
          _appendText(blocks, delta);
        case ThinkingDelta(text: final delta):
          if (delta.isNotEmpty) emit(AgentThinkingDelta(delta));
        case ThinkingComplete(:final block):
          blocks.add(block);
        case ToolCallDelta():
          break; // assembled calls arrive as ToolCallComplete
        case ToolCallComplete(:final call):
          blocks.add(call);
        case UsageEvent(usage: final increment):
          usage = (usage ?? Usage.zero) + increment;
        case Done(stopReason: final reason):
          stopReason = reason;
        case ErrorEvent(error: final e):
          error = e;
      }
      if (event.isTerminal) break;
    }
    if (usage case final used?) {
      // Cache reads are cheap and do not count towards the run budget.
      _tokensSpent +=
          used.inputTokens + used.outputTokens + used.cacheWriteTokens;
      emit(
        UsageReported(
          profileId: target.profileId,
          modelId: target.modelId,
          usage: used,
          costMicros: runner.costEstimator?.estimateMicros(
            profileId: target.profileId,
            modelId: target.modelId,
            usage: used,
          ),
        ),
      );
    }
    if (error == null && stopReason == null) {
      error = const MalformedResponseException(
        'Antwortstrom ohne Abschluss beendet',
      );
    }
    // Incomplete tool calls of a failed stream are never executed: the
    // whole reply is discarded on error.
    return _ModelReply(error == null ? blocks : const [], stopReason, error);
  }

  /// Appends [text] to the last block if it is text, else starts a new
  /// text block – keeps the order of text, thinking and tool-call blocks.
  void _appendText(List<ContentBlock> blocks, String text) {
    if (blocks.isNotEmpty && blocks.last is TextBlock) {
      final last = blocks.removeLast() as TextBlock;
      blocks.add(TextBlock(last.text + text));
    } else {
      blocks.add(TextBlock(text));
    }
  }

  String _systemPrompt() {
    final base = _context.systemPrompt;
    if (_epoch == 0) return base;
    final before = _executed.where((e) => e.epoch < _epoch).toList();
    if (before.isEmpty) return base;
    final actions = [
      for (final e in before) (call: e.call, outcome: e.outcome),
    ];
    return '$base\n\n${ContextBuilder.escalationNote(actions)}';
  }

  // ----------------------------------------------------------------- tools

  bool _isInvalid(ToolCallBlock call) =>
      runner.contextBuilder.catalog.lookup(call.name) == null ||
      call.tryDecodeArguments() == null;

  /// The earlier execution [call] would repeat, if any: a call with the
  /// same id from the model *and* the same tool and arguments, or – after an
  /// escalation – the same tool and arguments as a call of a previous
  /// provider that was not declined. Equal ids with other content are an id
  /// collision, not a repetition (see [_assignCallIds]).
  _Executed? _earlierExecution(ToolCallBlock call) {
    final sourceId = _sourceIds[call.id] ?? call.id;
    for (final e in _executed) {
      if (!_sameContent(e.call, call)) continue;
      final earlierId = _sourceIds[e.call.id] ?? e.call.id;
      if (sourceId.isNotEmpty && earlierId == sourceId) return e;
      if (e.epoch < _epoch && !_isDeclined(e.outcome)) return e;
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

  static bool _isDeclined(ToolOutcome o) =>
      !o.isError && o.text == ToolOutcome.declinedText;

  Future<List<ToolResultBlock>> _runTools(List<ToolCallBlock> calls) async {
    final results = <String, ToolResultBlock>{};
    final pending = <ToolCallBlock>[];
    for (final call in calls) {
      final earlier = _earlierExecution(call);
      if (earlier == null) {
        pending.add(call);
        continue;
      }
      final outcome = ToolOutcome(
        content: [
          const TextBlock(
            'Bereits ausgeführt, nicht wiederholt. Früheres Ergebnis:',
          ),
          ...earlier.outcome.content,
        ],
        isError: earlier.outcome.isError,
        summary: 'Bereits ausgeführt',
      );
      emit(ToolCallStarted(call));
      emit(ToolCallFinished(call: call, outcome: outcome));
      results[call.id] = outcome.toResultBlock(call.id);
    }

    if (pending.isNotEmpty) {
      final ctx = ToolContext(
        sessionId: runner.sessionId,
        clock: runner.clock,
        locale: runner.contextBuilder.device.locale,
        timeZone: runner.contextBuilder.device.timeZone,
        cancel: token,
      );
      await for (final event in runner.invoker.invokeAll(pending, ctx)) {
        switch (event) {
          case ToolStarted(:final call):
            emit(ToolCallStarted(call));
          case ConfirmationNeeded(:final call, :final description):
            emit(
              ConfirmationRequired(
                call: call,
                description: description,
                respond: event.respond,
              ),
            );
          case ToolFinished(:final call, :final outcome, :final duration):
            _executed.add((call: call, outcome: outcome, epoch: _epoch));
            emit(
              ToolCallFinished(
                call: call,
                outcome: outcome,
                duration: duration,
              ),
            );
            results[call.id] = outcome.toResultBlock(call.id);
        }
      }
    }

    // Every tool_use needs a tool_result, even if an invoker broke its
    // contract.
    return [
      for (final call in calls)
        results[call.id] ??
            ToolOutcome.error('Kein Ergebnis vom Tool erhalten')
                .toResultBlock(call.id),
    ];
  }

  /// Records [assistant] with error results for [calls] that are not
  /// executed, so every tool call in the history has a result.
  Future<void> _refuseRound(
    Message assistant,
    List<ToolCallBlock> calls,
    String why,
  ) async {
    await _append(assistant);
    await _append(
      Message.toolResults([
        for (final c in calls)
          ToolOutcome.error('Nicht ausgeführt: $why').toResultBlock(c.id),
      ]),
    );
  }

  // ------------------------------------------------------------ escalation

  /// Tries to hand the request to the next provider; returns whether it
  /// happened.
  Future<bool> _escalate(EscalationReason reason) async {
    final next = runner.resolver.escalate(_current, reason);
    if (next == null) return false;
    if (next.belowPrivacyFloor) {
      // Ask at most once per run; a „no“ stands.
      if (_consentDeclined) return false;
      final answer = Completer<bool>();
      final question = EscalationConfirmationRequired(
        fromProfile: _current.profileId,
        toProfile: next.profileId,
        reason: reason,
        respond: answer.complete,
      );
      emit(question);
      final approved = await Future.any([
        answer.future,
        token.whenCancelled.then((_) => false),
      ]);
      question.respond(false); // no-op if answered
      _throwIfAborted();
      if (!approved) {
        _consentDeclined = true;
        return false;
      }
    }
    emit(
      Escalated(
        fromProfile: _current.profileId,
        toProfile: next.profileId,
        reason: reason,
      ),
    );
    // The answer of the previous provider is discarded: paused segments and
    // streamed text of the current call.
    _messages.removeWhere((m) => _paused.any((p) => identical(p, m)));
    _paused.clear();
    if (_segmentStreamed) {
      emit(const AgentTextReset('An anderes Modell übergeben'));
    }
    _current = next;
    _epoch++;
    _roundsOnProvider = 0;
    _invalidOnProvider = 0;
    // Signed thinking belongs to the provider that produced it.
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.content.any((b) => b is ThinkingBlock)) {
        _messages[i] = Message(m.role, [
          for (final b in m.content)
            if (b is! ThinkingBlock) b,
        ]);
      }
    }
    return true;
  }

  // ------------------------------------------------------------- history

  /// Adds a kept message; records paused segments of this answer first.
  Future<void> _append(Message m) async {
    for (final p in _paused) {
      await _record(p);
    }
    _paused.clear();
    _messages.add(m);
    await _record(m);
  }

  Future<void> _record(Message m) async {
    await runner.recorder?.record(m);
  }
}
