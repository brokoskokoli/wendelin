import 'dart:async';

import '../messages/content_block.dart';
import '../messages/tool_spec.dart';
import 'tool.dart';
import 'tool_context.dart';
import 'tool_outcome.dart';

/// The set of tools currently offered to the model (implemented by the
/// `ToolRegistry` in `wendelin_tools`).
abstract interface class ToolCatalog {
  /// Specs of all active tools, in stable order (prompt caching).
  List<ToolSpec> activeSpecs();

  /// The tool called [name], or `null` if unknown or inactive.
  Tool? lookup(String name);
}

/// Executes tool calls with policy, confirmation and validation
/// (implemented by the `ToolExecutor` in `wendelin_tools`).
abstract interface class ToolInvoker {
  /// Executes [calls] and reports progress.
  ///
  /// Contract: for every call exactly one [ToolStarted] and, at the end,
  /// exactly one [ToolFinished]; [ConfirmationNeeded] in between if the user
  /// must decide. The stream closes after the last [ToolFinished]. Failures
  /// are reported as error outcomes, never as stream errors.
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  );
}

/// Progress of [ToolInvoker.invokeAll].
sealed class ToolInvocationEvent {
  const ToolInvocationEvent(this.call);

  /// The call this event belongs to.
  final ToolCallBlock call;
}

/// Execution of [call] has started.
final class ToolStarted extends ToolInvocationEvent {
  /// Creates the event.
  const ToolStarted(super.call);

  @override
  String toString() => 'ToolStarted(${call.id})';
}

/// The user must confirm [call]; complete [decision] with `true` (run) or
/// `false` (decline). The invoker waits for it.
final class ConfirmationNeeded extends ToolInvocationEvent {
  /// Creates the event.
  const ConfirmationNeeded(super.call, this.description, this.decision);

  /// German text for the confirmation card (`Tool.describeForConfirmation`).
  final String description;

  /// Completed by the UI/agent with the user's answer.
  final Completer<bool> decision;

  @override
  String toString() => 'ConfirmationNeeded(${call.id}, $description)';
}

/// [call] has finished with [outcome] after [duration].
final class ToolFinished extends ToolInvocationEvent {
  /// Creates the event.
  const ToolFinished(super.call, this.outcome, this.duration);

  /// The result (also for failures and declined confirmations).
  final ToolOutcome outcome;

  /// Execution time.
  final Duration duration;

  @override
  String toString() => 'ToolFinished(${call.id}, $outcome)';
}
