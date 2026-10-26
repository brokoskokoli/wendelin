import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart'
    show GpuCheckMode, GpuReason;
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../di/attestation_hub.dart';
import '../di/attestation_providers.dart';
import '../di/audit_recorder.dart';
import '../di/locked_scope.dart';
import '../di/preferences.dart';
import '../di/provider_config.dart';
import '../di/providers.dart';
import '../di/speaker_providers.dart';
import '../di/vocabulary_provider.dart';
import '../voice/speaker/person_scope.dart';
import 'agent_request.dart';
import 'chat_entry.dart';
import 'conversation_reducer.dart';
import 'conversation_state.dart';
import 'history_entries.dart';
import 'new_topic_command.dart';
import 'question_answer.dart';

/// The conversation on the main screen.
final agentControllerProvider =
    NotifierProvider<AgentController, ConversationState>(AgentController.new);

/// Runs requests through the agent and keeps the [ConversationState].
///
/// State changes come from [ConversationReducer] (pure); this class adds
/// the side effects: session handling, audit log, usage records, undo
/// registration and answering confirmations.
final class AgentController extends Notifier<ConversationState> {
  AgentRun? _run;
  StreamSubscription<AgentEvent>? _events;
  StreamSubscription<UndoUpdate>? _undo;
  String? _sessionId;
  String? _shownSessionId;
  ProviderConfig? _providers;

  /// Scope of the open conversation (WP92b): the person it belongs to. A
  /// known other person starts a new conversation; an unknown speaker or
  /// typed text stays in the conversation and its scope, so a person's
  /// history never reaches another person's agent or memory.
  PersonScope _scope = PersonScope.standard;
  String? _scopeSessionId;
  final _done = <Completer<void>>[];
  StreamController<AgentEvent>? _out;
  bool _cancelRequested = false;

  ConversationReducer get _reducer => ConversationReducer(
    nameOf: (id) => _providers?.nameOf(id) ?? id,
    texts: () => uiTexts(ref),
    undoWindow: ref.read(undoManagerProvider).window,
  );

  AuditRecorder get _audit => ref.read(auditRecorderProvider);

  @override
  ConversationState build() {
    _undo = ref
        .watch(undoManagerProvider)
        .updates
        .listen((u) => state = _reducer.undo(state, u));
    final late = ref.watch(attestationHubProvider).reports.listen(_lateReport);
    ref.onDispose(() {
      unawaited(late.cancel());
      unawaited(_undo?.cancel());
      unawaited(_events?.cancel());
      _run?.cancel();
    });
    return ConversationState.empty;
  }

  /// Result of a TEE check that arrives without an agent event: the GPU
  /// check after the answer (mode „Nachher“) marks the latest verified
  /// answer.
  void _lateReport(ProfileReport r) {
    final code = r.report.reasonCode;
    if (r.report.status != AttestationStatus.red ||
        (code != 'gpu_failed' && code != 'gpu_unavailable') ||
        ref.read(attestationHubProvider).modeOf(r.profileId) !=
            GpuCheckMode.after) {
      return;
    }
    state = _reducer.lateFailure(
      state,
      r.report,
      text: uiTexts(ref).agentNoticeGpuFailed,
    );
  }

  /// The user chose in the dialog of a request stopped by the GPU check:
  /// [sendWithout] sends it again, once without the check; otherwise it is
  /// dropped.
  Future<void> resolveGpuBlock({required bool sendWithout}) async {
    final block = state.gpuBlock;
    if (block == null) return;
    state = state.copyWith(clearGpuBlock: true);
    if (!sendWithout) return;
    ref.read(attestationHubProvider).allowWithoutGpuCheck(block.profileId);
    await send(block.request);
  }

  /// „Neu prüfen“ of a locked TEE provider: attests again and reports the
  /// result as a hint.
  Future<void> reattest(String profileId) async {
    final report = await ref.read(attestationHubProvider).reattest(profileId);
    if (report == null) return;
    state = _reducer.notice(
      state,
      report.status == AttestationStatus.green
          ? NoticeKind.info
          : NoticeKind.error,
      report.status == AttestationStatus.green
          ? uiTexts(ref).attLogRechecked
          : uiTexts(ref).agentNoticeRecheckFailed,
    );
  }

  /// Completes when the running request (if any) has finished.
  Future<void> get idle {
    if (!state.running) return Future.value();
    final c = Completer<void>();
    _done.add(c);
    return c.future;
  }

  /// Restores the open session (if it is still within the inactivity
  /// window) after an app start.
  Future<void> restore() async {
    final storage = ref.read(storageProvider);
    final now = ref.read(clockProvider).now();
    final last = (await storage.conversations.sessions(
      limit: 1,
      origin: SessionOrigin.app,
    )).firstOrNull;
    if (last == null ||
        now.difference(last.lastActivityAt) >=
            ConversationRepository.defaultInactivity ||
        state.entries.isNotEmpty) {
      return;
    }
    final messages = await storage.conversations.messages(last.id);
    _shownSessionId = last.id;
    state = state.copyWith(
      entries: entriesFromMessages([
        for (final m in messages) m.message,
      ], sessionStart: last.startedAt),
      privateSince: privateSinceOf(messages),
      privateByRequest: await _anyPrivateRequest(messages),
    );
  }

  /// Whether one of the user [messages] with a privacy floor was itself a
  /// private request (and not only tainted, e.g. by the memory).
  Future<bool> _anyPrivateRequest(List<StoredMessage> messages) async {
    final floored = [
      for (final m in messages)
        if (m.message.role == Role.user && m.message.privacyFloor != null)
          m.message.text,
    ];
    if (floored.isEmpty) return false;
    final ProviderConfig? config;
    try {
      config = await ref.read(providerConfigProvider.future);
    } on Object {
      return true; // Unknown: the stricter hint.
    }
    return floored.any((t) => isPrivateRequest(config, UserInput(text: t)));
  }

  /// The session [sessionId] ended (inactivity, „neues Thema“): a shown
  /// private state belongs to it and ends too.
  void sessionEnded(String sessionId) {
    if (sessionId == _shownSessionId && state.privateSince != null) {
      state = state.copyWith(clearPrivate: true);
    }
  }

  /// Time of the first message with a privacy floor in [messages], or
  /// `null`: from then on the conversation is private (taint propagation,
  /// ADR 0009 §4).
  static DateTime? privateSinceOf(List<StoredMessage> messages) => messages
      .where((m) => m.message.privacyFloor != null)
      .map((m) => m.createdAt)
      .firstOrNull;

  /// Looks up whether the session [sessionId] became private.
  Future<void> _refreshPrivacy(String sessionId) async {
    if (state.privateSince != null) return;
    final List<StoredMessage> messages;
    try {
      messages = await ref
          .read(storageProvider)
          .conversations
          .messages(sessionId);
    } on Object catch (e, stack) {
      _report(e, stack);
      return;
    }
    final since = privateSinceOf(messages);
    if (since != null && sessionId == _shownSessionId) {
      state = state.copyWith(privateSince: since);
    }
  }

  /// Sends [text] to the agent. „neues Thema“ starts a new session instead.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.running) return;
    if (isNewTopicPhrase(trimmed)) return newTopic();
    await _start(UserInput(text: trimmed), trigger: null, out: null);
  }

  /// Runs [input] (e.g. a voice transcript) like [send] and returns the
  /// agent events of this request; the stream ends after `AgentDone` or
  /// `AgentFailed`. [trigger] names what started it (audit log, e.g.
  /// `assistant`). If the request cannot start (busy, no provider), the
  /// stream holds a single `AgentFailed`. [locked] (WP154 L2) is the scope
  /// of a request on a locked device: only its tools, nothing stored, the
  /// wording not in the audit log.
  Stream<AgentEvent> submit(
    UserInput input, {
    String? trigger,
    LockedScope? locked,
  }) {
    final out = StreamController<AgentEvent>();
    final text = input.text.trim();
    if (text.isEmpty || state.running) {
      out
        ..add(
          AgentFailed(
            error: AgentErrorKind.internal,
            message: text.isEmpty
                ? uiTexts(ref).agentNoticeRequestEmpty
                : uiTexts(ref).agentNoticeRequestRunning,
          ),
        )
        ..close();
      return out.stream;
    }
    if (isNewTopicPhrase(text)) {
      // Spoken „neues Thema“: same as typed, nothing goes to the model.
      unawaited(newTopic());
      out
        ..add(const AgentDone(finalText: '', stopReason: StopReason.endTurn))
        ..close();
      return out.stream;
    }
    unawaited(_start(input, trigger: trigger, out: out, locked: locked));
    return out.stream;
  }

  Future<void> _start(
    UserInput input, {
    required String? trigger,
    required StreamController<AgentEvent>? out,
    LockedScope? locked,
  }) async {
    final trimmed = input.text.trim();
    // Corrected note names only count for their spoken request (WP33, B8).
    if (input.source != InputSource.voice) {
      ref.read(correctedTitlesProvider).record(const []);
    }
    // Mark as running right away, so a second tap cannot start another run.
    state = state.copyWith(running: true, clearGpuBlock: true);
    _out = out;
    _cancelRequested = false;
    final ProviderConfig? providers;
    try {
      providers = await ref.read(providerConfigProvider.future);
    } on Object catch (e) {
      _finishWithNotice(
        NoticeKind.error,
        uiTexts(ref).agentNoticeProfileBroken(e),
      );
      return;
    }
    if (providers == null) {
      _finishWithNotice(NoticeKind.info, uiTexts(ref).agentNoticeSetupFirst);
      return;
    }
    final String sessionId;
    final PersonScope scope;
    try {
      // The first request after start waits until every integration was
      // checked, so its active tools are offered.
      await ref.read(toolRegistryReadyProvider.future);
      (sessionId, scope) = await _sessionFor(input.speakerId, locked != null);
    } on Object catch (e, stack) {
      _report(e, stack);
      _finishWithNotice(NoticeKind.error, uiTexts(ref).agentNoticeStartFailed);
      return;
    }
    if (_cancelRequested) {
      // Cancelled while starting (e.g. tap in the overlay): nothing runs.
      _finishWithNotice(
        NoticeKind.info,
        uiTexts(ref).agentNoticeCancelled,
        error: AgentErrorKind.cancelled,
      );
      return;
    }
    _sessionId = sessionId;
    final scoped = providers.withDefaultProfile(scope.agentProfileId);
    _providers = scoped;
    final isNew = locked == null && sessionId != _shownSessionId;
    if (locked == null) _shownSessionId = sessionId;
    state = _reducer.userMessage(
      isNew ? state.copyWith(clearPrivate: true) : state,
      trimmed,
      sessionStart: isNew ? ref.read(clockProvider).now() : null,
    );
    if (isPrivateRequest(scoped, input)) {
      state = state.copyWith(privateByRequest: true);
    }

    final request = requestFor(input, trimmed, uiTexts(ref).localeName);
    final lockedRun = locked != null;
    _audit.request(
      sessionId,
      request,
      trigger: trigger,
      whileLocked: lockedRun,
    );
    final run = ref
        .read(agentFactoryProvider)
        .create(scoped, sessionId, person: scope, locked: locked);
    _run = run;
    _events = run
        .run(request)
        .listen(
          (event) => _onEvent(sessionId, event),
          onError: (Object e, StackTrace stack) => _failed(sessionId, e, stack),
          onDone: _finished,
          cancelOnError: true,
        );
  }

  /// The session for a request of [speakerId] and the scope it runs in
  /// (WP92b). A known person who is not the one of the open conversation
  /// gets a new conversation (no history); everything else continues the
  /// open one in its scope. After an app restart the scope comes from the
  /// person stored with the conversation; unreadable or deleted: new one.
  /// [locked] (WP154 L3): no session created or changed ([lockedSessionId],
  /// not in the DB), no remembered scope; only the speaker's own scope.
  Future<(String, PersonScope)> _sessionFor(String? who, bool locked) async {
    final sessions = ref.read(sessionManagerProvider);
    final resolver = ref.read(personScopeResolverProvider);
    final requested = await resolver.scopeOf(who);
    if (locked) return (lockedSessionId, requested);
    bool clashes(PersonScope open) =>
        !requested.isStandard && open.personId != requested.personId;

    final open = sessions.currentId;
    if (open != null && open == _scopeSessionId && clashes(_scope)) {
      return _startFor(requested);
    }
    final id = await sessions.ensure();
    if (id == _scopeSessionId) {
      if (!requested.isStandard && _scope.personId == requested.personId) {
        _scope = requested; // settings changed meanwhile: the fresh ones
      }
      return (id, _scope);
    }
    try {
      final conversations = sessions.conversations;
      if ((await conversations.messages(id)).isEmpty) {
        return await _adopt(id, requested); // new/expired: the speaker's own
      }
      final stored = await conversations.sessionPerson(id);
      final scope = stored == null
          ? PersonScope.standard
          : await resolver.scopeOf(stored);
      final gone = stored != null && scope.isStandard;
      if (!gone && !clashes(scope)) {
        _scope = scope;
        _scopeSessionId = id;
        return (id, scope);
      }
    } on Object {
      // Fail closed: what cannot be read is not continued.
    }
    return _startFor(requested);
  }

  Future<(String, PersonScope)> _startFor(PersonScope scope) async =>
      _adopt(await ref.read(sessionManagerProvider).startNew(), scope);

  /// Session [id] belongs to [scope] from now on (also stored for a restart).
  Future<(String, PersonScope)> _adopt(String id, PersonScope scope) async {
    await ref
        .read(sessionManagerProvider)
        .conversations
        .setSessionPerson(id, scope.personId);
    _scope = scope;
    _scopeSessionId = id;
    return (id, scope);
  }

  /// The agent stream broke its contract (no terminal event, an error):
  /// end the run like a failure so the screen is usable again.
  void _failed(String sessionId, Object error, StackTrace stack) {
    _report(error, stack);
    _onEvent(
      sessionId,
      const AgentFailed(
        error: AgentErrorKind.internal,
        message: 'Interner Fehler, die Anfrage wurde abgebrochen.',
      ),
    );
    _finished();
  }

  static void _report(Object error, StackTrace stack) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'wendelin',
          context: ErrorDescription('in der Agent-Anfrage'),
        ),
      );

  /// Cancels the running request (also while it is still starting).
  void cancel() {
    if (!state.running) return;
    final run = _run;
    if (run == null) {
      _cancelRequested = true;
    } else {
      run.cancel();
    }
  }

  /// Answers the open question (tool confirmation or escalation consent).
  void answer({required bool approved}) {
    final pending = state.pending;
    final sessionId = _sessionId;
    if (pending == null || sessionId == null) return;
    if (!pending.answered) {
      answerQuestion(pending, _audit, sessionId, approved: approved);
    }
    state = _reducer.answered(state);
  }

  /// Undoes the tool call [callId] (through its port). Returns whether it
  /// was undone; a failing undo is shown as hint.
  Future<bool> undo(String callId) async {
    final manager = ref.read(undoManagerProvider);
    if (!manager.canUndo(callId)) return false;
    final tool = state.tool(callId)?.toolName ?? '?';
    final sessionId = _sessionId;
    state = _reducer.undoStarted(state, callId);
    try {
      final ok = await manager.undo(callId);
      _audit.undo(sessionId, callId: callId, tool: tool, ok: ok);
      return ok;
    } on Object catch (e) {
      _audit.undo(sessionId, callId: callId, tool: tool, ok: false);
      state = _reducer.notice(
        state,
        NoticeKind.error,
        uiTexts(ref).agentNoticeUndoFailed(e),
      );
      return false;
    }
  }

  /// Adds a small hint line to the conversation („Abgebrochen.“,
  /// „Zurückgenommen.“).
  void addNotice(String text, {NoticeKind kind = NoticeKind.info}) =>
      state = _reducer.notice(state, kind, text);

  /// Ends the session and clears the conversation („neues Thema“).
  Future<void> newTopic() async {
    if (state.running) return;
    final sessions = ref.read(sessionManagerProvider);
    sessions.end();
    _sessionId = await sessions.startNew();
    _shownSessionId = _sessionId;
    state = ConversationState.empty.copyWith(
      entries: [SessionStartEntry('s1', ref.read(clockProvider).now())],
      nextSeq: 2,
    );
  }

  /// A new assistant overlay invocation: the next request starts a new
  /// session without history and the shown conversation and its privacy
  /// floor are cleared (WP67). Does nothing while a request runs.
  void beginFreshConversation() {
    if (state.running) return;
    ref.read(sessionManagerProvider).beginFresh();
    _sessionId = null;
    _shownSessionId = null;
    state = ConversationState.empty;
  }

  /// Replaces the state (golden tests with sample data).
  @visibleForTesting
  void seed(ConversationState value) => state = value;

  /// Whether [text] asks for a new topic (see [isNewTopicCommand]).
  static bool isNewTopicCommand(String text) => isNewTopicPhrase(text);

  void _onEvent(String sessionId, AgentEvent original) {
    _audit.agentEvent(sessionId, original);
    // A request stopped for lack of GPU evidence is shown and spoken with a
    // plain hint instead of the technical message (WP82).
    final event =
        original is AgentFailed &&
            original.cause is AttestationFailedException &&
            (original.cause! as AttestationFailedException).stage == 'gpu' &&
            (original.cause! as AttestationFailedException).category ==
                GpuReason.noEvidence
        ? AgentFailed(
            error: original.error,
            message: gpuNoEvidenceSpoken,
            cause: original.cause,
          )
        : original;
    _out?.add(event);
    switch (event) {
      case ToolCallFinished(:final call, :final outcome):
        final undo = outcome.undo;
        if (undo != null &&
            ConversationReducer.phaseOf(outcome) == ToolPhase.done) {
          state = _reducer.apply(state, event);
          ref.read(undoManagerProvider).register(call.id, undo);
          return;
        }
        if (undo == null) {
          // Undone by the agent (red TEE receipt, WP77): no second undo.
          ref.read(undoManagerProvider).discard(call.id);
        }
      case UsageReported(:final profileId, :final modelId, :final usage):
        unawaited(_recordUsage(sessionId, event, profileId, modelId, usage));
      case AgentFailed(:final cause, :final message)
          when cause is AttestationFailedException && cause.stage == 'gpu':
        unawaited(_refreshPrivacy(sessionId));
        final profile = state.activeProfileId;
        final request = state.lastRequest;
        if (profile != null && request != null) {
          state = _reducer
              .apply(state, event)
              .copyWith(
                gpuBlock: GpuBlock(
                  profileId: profile,
                  request: request,
                  reason: message,
                  noEvidence: cause.category == GpuReason.noEvidence,
                ),
              );
          return;
        }
      case EscalationConfirmationRequired() || AgentDone() || AgentFailed():
        // The answers and the request are stored by now (with their floor).
        unawaited(_refreshPrivacy(sessionId));
      case _:
    }
    state = _reducer.apply(state, event);
  }

  Future<void> _recordUsage(
    String sessionId,
    UsageReported event,
    String profileId,
    String modelId,
    Usage usage,
  ) async {
    await ref
        .read(storageProvider)
        .usage
        .record(
          sessionId: sessionId,
          profileId: profileId,
          modelId: modelId,
          usage: usage,
          costMicros: event.costMicros ?? 0,
        );
    ref.invalidate(todayCostProvider);
  }

  void _finished() {
    _run = null;
    _events = null;
    if (state.running) {
      // The stream ended without a terminal event (should not happen).
      state = state.copyWith(running: false, clearPending: true);
    }
    if (_sessionId != lockedSessionId) ref.read(sessionManagerProvider).touch();
    _closeOut();
    _completeIdle();
  }

  void _finishWithNotice(
    NoticeKind kind,
    String text, {
    AgentErrorKind error = AgentErrorKind.internal,
  }) {
    state = _reducer
        .notice(state, kind, text)
        .copyWith(running: false, clearPending: true);
    _out?.add(AgentFailed(error: error, message: text));
    _closeOut();
    _completeIdle();
  }

  void _closeOut() {
    final out = _out;
    _out = null;
    _cancelRequested = false;
    if (out != null) unawaited(out.close());
  }

  void _completeIdle() {
    for (final c in _done) {
      c.complete();
    }
    _done.clear();
  }
}
