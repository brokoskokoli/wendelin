import 'dart:async';

import '../wendelin_core.dart';

/// Signature of a custom [FakeTool] behaviour.
typedef FakeToolHandler = FutureOr<ToolOutcome> Function(
  Map<String, Object?> args,
  ToolContext ctx,
);

/// Configurable [Tool] for tests: risk, result, delay, failure, undo and a
/// record of all calls.
final class FakeTool implements Tool {
  /// Creates a fake tool.
  ///
  /// Result precedence: [throws] (thrown after [delay]) > [handler] >
  /// [outcome] > `ToolOutcome.text('ok')`. With [withUndo] the result gets an
  /// [UndoAction] that increments [undoCount].
  FakeTool({
    required this.name,
    this.description = 'Fake-Tool für Tests',
    this.inputSchema = const {'type': 'object'},
    this.risk = RiskLevel.read,
    this.outcome,
    this.handler,
    this.delay = Duration.zero,
    this.throws,
    this.withUndo = false,
    this.ignoresCancel = false,
    this.confirmation,
  });

  @override
  final String name;

  @override
  final String description;

  @override
  final Map<String, Object?> inputSchema;

  @override
  final RiskLevel risk;

  /// Fixed result, if no [handler] is set.
  final ToolOutcome? outcome;

  /// Custom behaviour.
  final FakeToolHandler? handler;

  /// Simulated execution time (aborted early by `ctx.cancel`).
  final Duration delay;

  /// If set, [execute] throws this after [delay].
  final Object? throws;

  /// Whether results carry an [UndoAction].
  final bool withUndo;

  /// If true, the tool ignores `ctx.cancel`: [delay] runs to the end and the
  /// normal result is returned (a tool whose effect cannot be stopped).
  final bool ignoresCancel;

  /// Text for [describeForConfirmation]; default „`name` ausführen“.
  final String Function(Map<String, Object?> args)? confirmation;

  /// Arguments of every [execute] call, in order.
  final List<Map<String, Object?>> calls = [];

  /// Number of [execute] calls.
  int get callCount => calls.length;

  /// Number of [execute] calls that returned normally (not thrown, not
  /// cancelled) – i.e. whose effect has happened.
  int completedCount = 0;

  /// Number of [execute] calls entered although `ctx.cancel` was already
  /// cancelled – an invoker must never do that.
  int startedAfterCancel = 0;

  /// Number of undo invocations.
  int undoCount = 0;

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    calls.add(Map.unmodifiable(args));
    if (ctx.cancel.isCancelled) startedAfterCancel++;
    if (delay > Duration.zero) {
      final done = Completer<void>();
      final timer = Timer(delay, done.complete);
      await Future.any([
        done.future,
        if (!ignoresCancel) ctx.cancel.whenCancelled,
      ]);
      timer.cancel();
    }
    if (!ignoresCancel) ctx.cancel.throwIfCancelled();
    if (throws case final error?) throw error;
    final result =
        await handler?.call(args, ctx) ?? outcome ?? ToolOutcome.text('ok');
    completedCount++;
    if (!withUndo) return result;
    return ToolOutcome(
      content: result.content,
      isError: result.isError,
      summary: result.summary,
      undo: UndoAction(label: 'Rückgängig', run: () async => undoCount++),
    );
  }

  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      confirmation?.call(args) ?? '$name ausführen';
}

/// Configurable [Integration] for tests.
final class FakeIntegration implements Integration {
  /// Creates a fake integration with the given [tools].
  FakeIntegration({
    required this.id,
    required List<Tool> tools,
    String? displayName,
    this.iconId = 'extension',
    this.platforms = const {AppPlatform.android, AppPlatform.ios},
    this.sensitive = false,
    this.availability = Availability.yes,
    List<SetupStep> setup = const [],
    List<String> missingSteps = const [],
  }) : displayName = displayName ?? id,
       tools = List.unmodifiable(tools),
       setup = List.unmodifiable(setup),
       missingSteps = List.of(missingSteps);

  @override
  final String id;

  @override
  final String displayName;

  @override
  final String iconId;

  @override
  final Set<AppPlatform> platforms;

  @override
  final bool sensitive;

  @override
  final List<Tool> tools;

  @override
  final List<SetupStep> setup;

  /// Returned by [checkAvailability]; may be changed by tests.
  Availability availability;

  /// Ids of missing setup steps; may be changed by tests.
  List<String> missingSteps;

  /// Number of [checkAvailability] calls.
  int availabilityChecks = 0;

  @override
  Future<Availability> checkAvailability() async {
    availabilityChecks++;
    return availability;
  }

  @override
  Future<SetupState> setupState() async =>
      SetupState(missingSteps: missingSteps);
}

/// [ToolCatalog] over a fixed list of tools (all active, given order).
final class FakeToolCatalog implements ToolCatalog {
  /// Creates a catalog of [tools].
  FakeToolCatalog(List<Tool> tools) : tools = List.unmodifiable(tools);

  /// All tools.
  final List<Tool> tools;

  @override
  List<ToolSpec> activeSpecs() => [for (final t in tools) t.spec];

  @override
  Tool? lookup(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Simple sequential [ToolInvoker] for agent tests. Passes
/// `toolInvokerContract`.
///
/// Unknown tools and invalid JSON give error outcomes; `external` tools emit
/// [ConfirmationNeeded] and wait; a declined call yields
/// `ToolOutcome.declined()`; exceptions become error outcomes; cancellation
/// follows the [ToolInvoker] contract. No schema validation, no timeouts, no
/// parallelism – that is `ToolExecutor`'s job.
final class FakeToolInvoker implements ToolInvoker {
  /// Creates an invoker over [catalog].
  FakeToolInvoker(this.catalog);

  /// Where tools are looked up.
  final ToolCatalog catalog;

  /// All calls received, in order.
  final List<ToolCallBlock> received = [];

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    for (final call in calls) {
      received.add(call);
      final start = ctx.clock.now();
      yield ToolStarted(call);
      final tool = catalog.lookup(call.name);
      final args = call.tryDecodeArguments();
      ToolOutcome outcome;
      if (ctx.cancel.isCancelled) {
        outcome = ToolOutcome.cancelled();
      } else if (tool == null) {
        outcome = ToolOutcome.error('Unbekanntes Tool ${call.name}');
      } else if (args == null) {
        outcome = ToolOutcome.error('Argumente sind kein gültiges JSON-Objekt');
      } else {
        var approved = true;
        if (tool.risk == RiskLevel.external) {
          final confirmation = ConfirmationNeeded(
            call,
            tool.describeForConfirmation(args),
            Completer<bool>(),
          );
          yield confirmation;
          approved = await Future.any([
            confirmation.decision.future,
            ctx.cancel.whenCancelled.then((_) => false),
          ]);
          confirmation.respond(false); // no-op if already answered
        }
        if (ctx.cancel.isCancelled) {
          outcome = ToolOutcome.cancelled();
        } else if (!approved) {
          outcome = ToolOutcome.declined();
        } else {
          outcome = await _execute(tool, args, ctx);
        }
      }
      yield ToolFinished(call, outcome, ctx.clock.now().difference(start));
    }
  }

  static Future<ToolOutcome> _execute(
    Tool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    try {
      // A tool that completed despite cancellation keeps its real outcome:
      // its effect has happened and the model must know.
      return await tool.execute(args, ctx);
    } on CancelledException {
      return ToolOutcome.cancelled();
    } on Object catch (e) {
      return ToolOutcome.error('Fehler bei ${tool.name}: $e');
    }
  }
}
