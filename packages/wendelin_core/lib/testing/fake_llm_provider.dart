import 'dart:async';

import '../wendelin_core.dart';

/// One scripted model answer for [FakeLlmProvider].
///
/// The factories turn the answer into the [ChatEvent]s a real streaming
/// provider would emit (text split into deltas of [chunkSize] characters,
/// tool-call arguments split into fragments, then usage and `Done`).
final class ScriptedTurn {
  ScriptedTurn._(List<ChatEvent> events, {this.hangs = false})
    : events = List.unmodifiable(events);

  /// Usage reported by scripted turns unless overridden.
  static const defaultUsage = Usage(inputTokens: 100, outputTokens: 20);

  /// A plain text answer, optionally preceded by [thinking].
  ///
  /// With [thinking], reasoning deltas and a `ThinkingComplete` (carrying
  /// [thinkingSignature]) precede the text.
  factory ScriptedTurn.text(
    String text, {
    String? thinking,
    String? thinkingSignature,
    Usage usage = defaultUsage,
    StopReason stopReason = StopReason.endTurn,
    int chunkSize = 4,
  }) => ScriptedTurn._([
    if (thinking != null) ...[
      for (final c in _chunks(thinking, chunkSize)) ThinkingDelta(c),
      ThinkingComplete(ThinkingBlock(thinking, signature: thinkingSignature)),
    ],
    for (final c in _chunks(text, chunkSize)) TextDelta(c),
    UsageEvent(usage),
    Done(stopReason),
  ]);

  /// An answer requesting [calls], optionally preceded by [text].
  factory ScriptedTurn.toolCalls(
    List<ToolCallBlock> calls, {
    String? text,
    Usage usage = defaultUsage,
    int chunkSize = 4,
  }) => ScriptedTurn._([
    if (text != null)
      for (final c in _chunks(text, chunkSize)) TextDelta(c),
    for (final (i, call) in calls.indexed) ...[
      for (final (j, frag) in _chunks(call.argumentsJson, chunkSize).indexed)
        ToolCallDelta(
          index: i,
          id: j == 0 ? call.id : null,
          name: j == 0 ? call.name : null,
          argumentsFragment: frag,
        ),
      ToolCallComplete(call),
    ],
    UsageEvent(usage),
    const Done(StopReason.toolUse),
  ]);

  /// A failing answer: emits [partialText] deltas, then `ErrorEvent(error)`.
  factory ScriptedTurn.error(
    ProviderException error, {
    String partialText = '',
    int chunkSize = 4,
  }) => ScriptedTurn._([
    for (final c in _chunks(partialText, chunkSize)) TextDelta(c),
    ErrorEvent(error),
  ]);

  /// A failure in the middle of a tool call: emits the first half of
  /// [call]'s arguments as deltas (no `ToolCallComplete`), then
  /// `ErrorEvent(error)`.
  factory ScriptedTurn.errorDuringToolCall(
    ToolCallBlock call,
    ProviderException error,
  ) => ScriptedTurn._([
    ToolCallDelta(
      index: 0,
      id: call.id,
      name: call.name,
      argumentsFragment: call.argumentsJson.substring(
        0,
        call.argumentsJson.length ~/ 2,
      ),
    ),
    ErrorEvent(error),
  ]);

  /// Emits [partialText] deltas and then waits until the request's
  /// `CancelToken` is cancelled; ends with `ErrorEvent(CancelledException)`.
  /// Without a token the stream never ends.
  factory ScriptedTurn.hang({String partialText = '', int chunkSize = 4}) =>
      ScriptedTurn._([
        for (final c in _chunks(partialText, chunkSize)) TextDelta(c),
      ], hangs: true);

  /// Emits exactly [events] (for malformed or unusual sequences).
  factory ScriptedTurn.events(List<ChatEvent> events) => ScriptedTurn._(events);

  /// Events emitted for this turn.
  final List<ChatEvent> events;

  /// Whether the turn waits for cancellation after [events].
  final bool hangs;

  static List<String> _chunks(String s, int size) => [
    for (var i = 0; i < s.length; i += size)
      s.substring(i, i + size > s.length ? s.length : i + size),
  ];
}

/// Scripted [LlmProvider] for tests and the demo mode.
///
/// Each `chat` call consumes the next [ScriptedTurn] and records the
/// request in [requests]. When the script is exhausted, `chat` ends with
/// `ErrorEvent(InvalidRequestException)`. Honors [CancelToken]s between
/// events. Passes `llmProviderContract`.
final class FakeLlmProvider implements LlmProvider {
  /// Creates a provider that plays [turns] in order.
  FakeLlmProvider(
    Iterable<ScriptedTurn> turns, {
    this.caps = const ProviderCapabilities(
      tools: true,
      vision: true,
      streaming: true,
    ),
    List<ModelInfo> models = const [ModelInfo(id: 'fake-model')],
    this.eventDelay = Duration.zero,
    this.health,
  }) : _turns = List.of(turns),
       _models = List.unmodifiable(models);

  final List<ScriptedTurn> _turns;
  final List<ModelInfo> _models;

  /// Returned by [test]; `null` = a healthy default result.
  final HealthCheck? health;

  /// Pause before each event (0 = only a microtask hop).
  final Duration eventDelay;

  /// All requests received by [chat], in order.
  final List<ChatRequest> requests = [];

  @override
  final ProviderCapabilities caps;

  @override
  ProviderType get type => ProviderType.fake;

  /// Number of turns not yet played.
  int get remainingTurns => _turns.length;

  /// Appends [turn] to the script.
  void enqueue(ScriptedTurn turn) => _turns.add(turn);

  @override
  Future<List<ModelInfo>> listModels() async => _models;

  @override
  Future<HealthCheck> test() async =>
      health ??
      HealthCheck(
        ok: true,
        latency: Duration.zero,
        message: 'Fake-Provider bereit',
        models: _models,
      );

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    requests.add(req);
    final token = cancel ?? CancelToken();
    if (token.isCancelled) {
      yield const ErrorEvent(CancelledException());
      return;
    }
    if (_turns.isEmpty) {
      yield const ErrorEvent(
        InvalidRequestException('FakeLlmProvider: kein Zug mehr im Skript'),
      );
      return;
    }
    final turn = _turns.removeAt(0);
    for (final event in turn.events) {
      await _pause(token);
      if (token.isCancelled) {
        yield const ErrorEvent(CancelledException());
        return;
      }
      yield event;
      if (event.isTerminal) return;
    }
    if (turn.hangs) {
      await token.whenCancelled;
      yield const ErrorEvent(CancelledException());
    }
  }

  Future<void> _pause(CancelToken token) async {
    if (eventDelay <= Duration.zero) {
      await Future<void>.value();
      return;
    }
    final done = Completer<void>();
    final timer = Timer(eventDelay, done.complete);
    await Future.any([done.future, token.whenCancelled]);
    timer.cancel();
  }
}
