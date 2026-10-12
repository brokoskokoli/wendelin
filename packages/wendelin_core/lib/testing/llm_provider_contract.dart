import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../wendelin_core.dart';

/// Situations the contract suite asks a provider under test to produce.
///
/// The `create` callback of [llmProviderContract] receives one scenario and
/// must return a provider whose **next** `chat` call behaves as described
/// (adapters: answer with a matching recorded/rebuilt fixture via a mock
/// HTTP client; the fake: a matching `ScriptedTurn`).
enum ContractScenario {
  /// Text answer exactly [ContractExpectations.text], at least one
  /// `UsageEvent`, `Done(StopReason.endTurn)`.
  text,

  /// One call of [ContractExpectations.toolName] with arguments
  /// [ContractExpectations.singleCallArgs], `Done(StopReason.toolUse)`.
  toolCall,

  /// Two calls of [ContractExpectations.toolName] with arguments
  /// [ContractExpectations.parallelCallArgs] (in that order),
  /// `Done(StopReason.toolUse)`.
  parallelToolCalls,

  /// Server-side failure (e.g. HTTP 500/529 or an in-stream overload
  /// error): ends with `ErrorEvent(ServerException)` that is retryable.
  serverError,

  /// Invalid credentials (HTTP 401): ends with `ErrorEvent(AuthException)`.
  authError,

  /// Rate limit (HTTP 429): ends with `ErrorEvent(RateLimitException)`.
  rateLimited,

  /// Emits at least one `TextDelta` and then keeps the stream open until the
  /// request's `CancelToken` is cancelled (e.g. a never-closing body).
  hang,
}

/// Values the scenarios of [ContractScenario] must produce.
abstract final class ContractExpectations {
  /// Expected answer text for [ContractScenario.text].
  static const text = 'Hallo! Ich bin Wendelin.';

  /// Tool used in the tool scenarios.
  static const toolName = 'contract__echo';

  /// Arguments of [ContractScenario.toolCall].
  static const singleCallArgs = {'text': 'hallo'};

  /// Arguments of the two calls of [ContractScenario.parallelToolCalls].
  static const parallelCallArgs = [
    {'text': 'eins'},
    {'text': 'zwei'},
  ];

  /// Spec of [toolName], included in [request].
  static const toolSpec = ToolSpec(
    name: toolName,
    description: 'Gibt den Text zurück.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
      },
      'required': ['text'],
    },
  );

  /// The request the suite sends in every scenario.
  static ChatRequest request() => ChatRequest(
    systemPrompt: 'Du bist ein Testassistent.',
    messages: [Message.user('Sag hallo.')],
    tools: const [toolSpec],
    model: 'contract-model',
    maxTokens: 200,
  );
}

/// Reusable contract test suite for every [LlmProvider] implementation.
///
/// Call it inside a test file; it registers a `group`. [create] is invoked
/// once per test with the scenario to produce (see [ContractScenario]).
/// [name] labels the group. [timeout] bounds each test.
///
/// Checked invariants (see `ChatEvent`):
/// - the stream never emits errors and closes after exactly one terminal
///   event (`Done` or `ErrorEvent`), which is the last event;
/// - `UsageEvent`s come before `Done` (implied by the previous rule);
/// - `ToolCallDelta`s of call *k* come before the *k*-th `ToolCallComplete`
///   and their fragments reassemble to the same JSON as the complete call;
/// - cancellation ends the stream with `ErrorEvent(CancelledException)` and
///   without `Done`.
void llmProviderContract(
  FutureOr<LlmProvider> Function(ContractScenario scenario) create, {
  String name = 'LlmProvider',
  Duration timeout = const Duration(seconds: 10),
}) {
  Future<List<ChatEvent>> collect(
    ContractScenario scenario, {
    CancelToken? cancel,
  }) async {
    final provider = await create(scenario);
    return _collect(
      provider.chat(ContractExpectations.request(), cancel: cancel),
    ).timeout(timeout);
  }

  group('$name erfüllt LlmProvider-Vertrag', () {
    test('text: Deltas ergeben den Text, Usage vor genau einem Done', () async {
      final events = await collect(ContractScenario.text);
      expectWellFormedChatStream(events);
      expect(events.last, const Done(StopReason.endTurn));
      expect(
        events.whereType<TextDelta>().map((e) => e.text).join(),
        ContractExpectations.text,
      );
      expect(events.whereType<UsageEvent>(), isNotEmpty);
      expect(events.whereType<ToolCallComplete>(), isEmpty);
    });

    test('toolCall: ein vollständiger Tool-Call, Done(toolUse)', () async {
      final events = await collect(ContractScenario.toolCall);
      expectWellFormedChatStream(events);
      expect(events.last, const Done(StopReason.toolUse));
      final calls = events.whereType<ToolCallComplete>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.call.name, ContractExpectations.toolName);
      expect(calls.single.call.id, isNotEmpty);
      expect(
        jsonDecode(calls.single.call.argumentsJson),
        ContractExpectations.singleCallArgs,
      );
    });

    test(
      'parallelToolCalls: zwei Calls in Reihenfolge, eindeutige Ids',
      () async {
        final events = await collect(ContractScenario.parallelToolCalls);
        expectWellFormedChatStream(events);
        expect(events.last, const Done(StopReason.toolUse));
        final calls = [
          for (final e in events.whereType<ToolCallComplete>()) e.call,
        ];
        expect(calls, hasLength(2));
        expect(
          calls.map((c) => c.name),
          everyElement(ContractExpectations.toolName),
        );
        expect(calls[0].id, isNot(calls[1].id));
        expect([
          for (final c in calls) jsonDecode(c.argumentsJson),
        ], ContractExpectations.parallelCallArgs);
      },
    );

    for (final (scenario, matcher, retryable) in [
      (ContractScenario.serverError, isA<ServerException>(), true),
      (ContractScenario.authError, isA<AuthException>(), false),
      (ContractScenario.rateLimited, isA<RateLimitException>(), true),
    ]) {
      test('${scenario.name}: endet mit ErrorEvent, kein Done', () async {
        final events = await collect(scenario);
        expectWellFormedChatStream(events);
        final last = events.last;
        expect(last, isA<ErrorEvent>());
        final error = (last as ErrorEvent).error;
        expect(error, matcher);
        expect(error.retryable, retryable);
        expect(events.whereType<Done>(), isEmpty);
      });
    }

    test('Abbruch mitten im Stream endet mit CancelledException', () async {
      final provider = await create(ContractScenario.hang);
      final cancel = CancelToken();
      final events = <ChatEvent>[];
      final done = Completer<void>();
      final sub = provider
          .chat(ContractExpectations.request(), cancel: cancel)
          .listen(
            (e) {
              events.add(e);
              if (e is TextDelta) cancel.cancel();
            },
            onError: (Object e, StackTrace s) =>
                fail('Stream darf keine Fehler senden: $e'),
            onDone: done.complete,
          );
      await done.future.timeout(timeout);
      await sub.cancel();
      expectWellFormedChatStream(events);
      expect(events.whereType<TextDelta>(), isNotEmpty);
      expect(events.last, isA<ErrorEvent>());
      expect((events.last as ErrorEvent).error, isA<CancelledException>());
      expect(events.whereType<Done>(), isEmpty);
    });

    test('bereits abgebrochenes Token: nur ErrorEvent(Cancelled)', () async {
      final cancel = CancelToken()..cancel();
      final events = await collect(ContractScenario.text, cancel: cancel);
      expect(events, hasLength(1));
      expect(events.single, isA<ErrorEvent>());
      expect((events.single as ErrorEvent).error, isA<CancelledException>());
    });
  });
}

/// Asserts the structural stream invariants listed at [llmProviderContract]
/// on an already collected event list. Usable directly in adapter tests.
void expectWellFormedChatStream(List<ChatEvent> events) {
  expect(events, isNotEmpty, reason: 'Stream ohne Events');
  final terminals = events.where((e) => e.isTerminal).toList();
  expect(
    terminals,
    hasLength(1),
    reason: 'genau ein Done/ErrorEvent erwartet, war: $terminals',
  );
  expect(
    events.last.isTerminal,
    isTrue,
    reason: 'Done/ErrorEvent muss das letzte Event sein',
  );
  // Usage before Done follows from Done being the single, last event.

  final completes = <int>[
    for (final (i, e) in events.indexed)
      if (e is ToolCallComplete) i,
  ];
  final fragments = <int, StringBuffer>{};
  for (final (i, e) in events.indexed) {
    if (e is! ToolCallDelta) continue;
    expect(
      e.index,
      lessThan(completes.length),
      reason: 'ToolCallDelta(index ${e.index}) ohne ToolCallComplete',
    );
    expect(
      i,
      lessThan(completes[e.index]),
      reason: 'ToolCallDelta(index ${e.index}) nach seinem ToolCallComplete',
    );
    final call = (events[completes[e.index]] as ToolCallComplete).call;
    if (e.id != null) expect(e.id, call.id, reason: 'Delta-Id ≠ Call-Id');
    if (e.name != null) expect(e.name, call.name, reason: 'Delta-Name ≠ Name');
    (fragments[e.index] ??= StringBuffer()).write(e.argumentsFragment);
  }
  fragments.forEach((index, buffer) {
    final call = (events[completes[index]] as ToolCallComplete).call;
    if (buffer.isEmpty) return;
    expect(
      jsonDecode(buffer.toString()),
      jsonDecode(call.argumentsJson),
      reason: 'Delta-Fragmente ergeben nicht die Argumente von ${call.id}',
    );
  });
}

Future<List<ChatEvent>> _collect(Stream<ChatEvent> stream) {
  final events = <ChatEvent>[];
  final done = Completer<List<ChatEvent>>();
  stream.listen(
    events.add,
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) {
        done.completeError(
          TestFailure('Stream darf keine Fehler senden, war: $e'),
          s,
        );
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete(events);
    },
  );
  return done.future;
}
