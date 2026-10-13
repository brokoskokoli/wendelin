import 'dart:async';

import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');

/// Shorthand for a tool call block.
ToolCallBlock call(String id, String name, [String args = '{}']) =>
    ToolCallBlock(id: id, name: name, argumentsJson: args);

/// Builds a target with its own scripted provider.
(ProviderTarget, FakeLlmProvider) scripted(
  String profileId,
  List<ScriptedTurn> turns, {
  PrivacyLevel privacy = PrivacyLevel.standard,
  Duration eventDelay = Duration.zero,
}) {
  final provider = FakeLlmProvider(turns, eventDelay: eventDelay);
  return (
    ProviderTarget(
      profileId: profileId,
      modelId: '$profileId-model',
      provider: provider,
      privacy: privacy,
    ),
    provider,
  );
}

/// Agent runner wired with fakes.
final class Harness {
  Harness({
    required ProviderTarget primary,
    List<ProviderTarget> chain = const [],
    List<Tool> tools = const [],
    this.config = const AgentConfig(),
    bool Function(UserInput)? isPrivate,
    ToolInvoker? invoker,
    this.budget,
    CostEstimator? cost,
    ConversationRecorder? recorder,
    ToolCatalog Function(PrivacyLevel)? catalogFor,
    void Function(String, ToolCallBlock)? onToolRefused,
    List<Message> history = const [],
    ProviderResolver? resolver,
  }) : conversation = InMemoryConversation(history),
       clock = FixedClock(DateTime.utc(2026, 10, 13, 9)),
       catalog = FakeToolCatalog(tools) {
    this.invoker = invoker ?? FakeToolInvoker(catalog);
    runner = AgentRunner(
      resolver:
          resolver ??
          DefaultProviderResolver(primary, chain, isPrivate: isPrivate),
      contextBuilder: ContextBuilder(
        config: config,
        clock: clock,
        device: device,
        catalog: catalog,
        history: conversation,
      ),
      invoker: this.invoker,
      clock: clock,
      sessionId: 's1',
      recorder: recorder ?? conversation,
      costEstimator: cost,
      budgetGuard: budget,
      catalogFor: catalogFor,
      onToolRefused: onToolRefused,
    );
  }

  final AgentConfig config;
  final FixedClock clock;
  final FakeToolCatalog catalog;
  late final ToolInvoker invoker;
  final FixedBudgetGuard? budget;
  final InMemoryConversation conversation;
  late final AgentRunner runner;

  /// Runs [text] and collects all events; [onEvent] may answer
  /// confirmations or cancel.
  Future<List<AgentEvent>> run(
    String text, {
    void Function(AgentEvent e)? onEvent,
    bool requestEscalation = false,
  }) async {
    final events = <AgentEvent>[];
    await for (final e in runner.run(
      UserInput(text: text, requestEscalation: requestEscalation),
    )) {
      events.add(e);
      onEvent?.call(e);
    }
    return events;
  }
}

/// The terminal event.
AgentEvent terminal(List<AgentEvent> events) => events.last;

/// Concatenated AgentTextDeltas.
String streamedText(List<AgentEvent> events) =>
    events.whereType<AgentTextDelta>().map((e) => e.text).join();

/// Tool result blocks of the last tool message in [req].
List<ToolResultBlock> lastResults(ChatRequest req) => req.messages
    .lastWhere((m) => m.role == Role.tool)
    .content
    .cast<ToolResultBlock>();

/// Invoker that never reports anything (contract violation).
final class SilentInvoker implements ToolInvoker {
  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) => const Stream.empty();
}

/// Invoker that finishes calls in reverse order (like a parallel invoker
/// whose last call is fastest).
final class ReversedInvoker implements ToolInvoker {
  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    for (final c in calls) {
      yield ToolStarted(c);
    }
    for (final c in calls.reversed) {
      yield ToolFinished(
        c,
        ToolOutcome.text('Ergebnis ${c.id}'),
        Duration.zero,
      );
    }
  }
}

/// Invoker that asks every call with the given effective [risk] and then
/// reports it as done.
final class RiskInvoker implements ToolInvoker {
  RiskInvoker(this.risk);

  final RiskLevel risk;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    for (final c in calls) {
      yield ToolStarted(c);
      final q = ConfirmationNeeded(c, 'Frage', Completer<bool>(), risk: risk);
      yield q;
      final ok = await q.decision.future;
      yield ToolFinished(
        c,
        ok ? ToolOutcome.text('ok') : ToolOutcome.declined(),
        Duration.zero,
      );
    }
  }
}

/// Invoker that records the contexts it gets and reports `ok` for every
/// call.
final class ContextInvoker implements ToolInvoker {
  final contexts = <ToolContext>[];

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    contexts.add(ctx);
    for (final c in calls) {
      yield ToolStarted(c);
      yield ToolFinished(c, ToolOutcome.text('ok'), Duration.zero);
    }
  }
}

/// Recorder that fails.
final class FailingRecorder implements ConversationRecorder {
  @override
  Future<void> record(Message message) =>
      Future.error(StateError('Datenbank voll'));
}

/// Provider that throws instead of emitting events (contract violation).
final class ThrowingProvider implements LlmProvider {
  @override
  ProviderCapabilities get caps =>
      const ProviderCapabilities(tools: true, vision: false, streaming: true);

  @override
  ProviderType get type => ProviderType.fake;

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      Stream.error(StateError('kaputt'));

  @override
  Future<List<ModelInfo>> listModels() async => const [];

  @override
  Future<HealthCheck> test() => throw UnimplementedError();
}
