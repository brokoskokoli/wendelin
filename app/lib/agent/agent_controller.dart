import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../di/audit_recorder.dart';
import '../di/provider_config.dart';
import '../di/providers.dart';
import 'chat_entry.dart';
import 'conversation_reducer.dart';
import 'conversation_state.dart';
import 'history_entries.dart';

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
  final _done = <Completer<void>>[];
  StreamController<AgentEvent>? _out;
  bool _cancelRequested = false;

  ConversationReducer get _reducer => ConversationReducer(
    nameOf: (id) => _providers?.nameOf(id) ?? id,
    undoWindow: ref.read(undoManagerProvider).window,
  );

  AuditRecorder get _audit => ref.read(auditRecorderProvider);

  @override
  ConversationState build() {
    _undo = ref
        .watch(undoManagerProvider)
        .updates
        .listen((u) => state = _reducer.undo(state, u));
    ref.onDispose(() {
      unawaited(_undo?.cancel());
      unawaited(_events?.cancel());
      _run?.cancel();
    });
    return ConversationState.empty;
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
    final last = (await storage.conversations.sessions(limit: 1)).firstOrNull;
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
    return floored.any((t) => _isPrivateRequest(config, UserInput(text: t)));
  }

  /// Whether [input] is routed privately (a `privacy` rule matches).
  static bool _isPrivateRequest(ProviderConfig? config, UserInput input) {
    if (config == null) return false;
    try {
      return config.resolver().resolve(input).privacyFloor != null;
    } on Object {
      return false;
    }
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
    if (isNewTopicCommand(trimmed)) return newTopic();
    await _start(UserInput(text: trimmed), trigger: null, out: null);
  }

  /// Runs [input] (e.g. a voice transcript) like [send] and returns the
  /// agent events of this request; the stream ends after `AgentDone` or
  /// `AgentFailed`. [trigger] names what started it (audit log, e.g.
  /// `assistant`). If the request cannot start (busy, no provider), the
  /// stream holds a single `AgentFailed`.
  Stream<AgentEvent> submit(UserInput input, {String? trigger}) {
    final out = StreamController<AgentEvent>();
    final text = input.text.trim();
    if (text.isEmpty || state.running) {
      out
        ..add(
          AgentFailed(
            error: AgentErrorKind.internal,
            message: text.isEmpty
                ? 'Die Anfrage ist leer.'
                : 'Es läuft schon eine Anfrage.',
          ),
        )
        ..close();
      return out.stream;
    }
    unawaited(_start(input, trigger: trigger, out: out));
    return out.stream;
  }

  Future<void> _start(
    UserInput input, {
    required String? trigger,
    required StreamController<AgentEvent>? out,
  }) async {
    final trimmed = input.text.trim();
    // Mark as running right away, so a second tap cannot start another run.
    state = state.copyWith(running: true);
    _out = out;
    _cancelRequested = false;
    final ProviderConfig? providers;
    try {
      providers = await ref.read(providerConfigProvider.future);
    } on Object catch (e) {
      _finishWithNotice(NoticeKind.error, 'Provider-Profil fehlerhaft: $e');
      return;
    }
    if (providers == null) {
      _finishWithNotice(
        NoticeKind.info,
        'Bitte zuerst einen Provider einrichten.',
      );
      return;
    }
    _providers = providers;

    final String sessionId;
    try {
      // The first request after start waits until every integration was
      // checked, so its active tools are offered.
      await ref.read(toolRegistryReadyProvider.future);
      sessionId = await ref.read(sessionManagerProvider).ensure();
    } on Object catch (e, stack) {
      _report(e, stack);
      _finishWithNotice(NoticeKind.error, 'Die Anfrage konnte nicht starten.');
      return;
    }
    if (_cancelRequested) {
      // Cancelled while starting (e.g. tap in the overlay): nothing runs.
      _finishWithNotice(
        NoticeKind.info,
        'Abgebrochen.',
        error: AgentErrorKind.cancelled,
      );
      return;
    }
    _sessionId = sessionId;
    final isNew = sessionId != _shownSessionId;
    _shownSessionId = sessionId;
    state = _reducer.userMessage(
      isNew ? state.copyWith(clearPrivate: true) : state,
      trimmed,
      sessionStart: isNew ? ref.read(clockProvider).now() : null,
    );
    if (_isPrivateRequest(providers, input)) {
      state = state.copyWith(privateByRequest: true);
    }

    final request = UserInput(
      text: trimmed,
      images: input.images,
      source: input.source,
      sttConfidence: input.sttConfidence,
      language: input.language,
      requestEscalation: input.requestEscalation,
    );
    _audit.request(sessionId, request, trigger: trigger);
    final run = ref.read(agentFactoryProvider).create(providers, sessionId);
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
      switch (pending) {
        case ToolQuestion(:final event):
          event.respond(approved);
          _audit.toolConfirmation(sessionId, event, approved: approved);
        case EscalationQuestion(:final event):
          event.respond(approved);
          _audit.escalationConfirmation(sessionId, event, approved: approved);
      }
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
        'Rückgängig hat nicht geklappt: $e',
      );
      return false;
    }
  }

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

  /// Replaces the state (golden tests with sample data).
  @visibleForTesting
  void seed(ConversationState value) => state = value;

  /// Whether [text] asks for a new topic.
  static bool isNewTopicCommand(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß ]'), '').trim();
    return t == 'neues thema';
  }

  void _onEvent(String sessionId, AgentEvent event) {
    _audit.agentEvent(sessionId, event);
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
      case UsageReported(:final profileId, :final modelId, :final usage):
        unawaited(_recordUsage(sessionId, event, profileId, modelId, usage));
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
    ref.read(sessionManagerProvider).touch();
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
