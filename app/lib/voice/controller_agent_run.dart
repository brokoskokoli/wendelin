import 'package:wendelin_core/wendelin_core.dart';

import '../agent/agent_controller.dart';
import '../di/locked_scope.dart';

/// [AgentRun] of the voice pipeline on the [AgentController]: the request
/// runs like a typed one (conversation, audit with [trigger], undo,
/// confirmations), only the events also go back to the pipeline.
final class ControllerAgentRun implements AgentRun {
  /// Creates the adapter; [trigger] names what started the request.
  ControllerAgentRun(this.controller, {required this.trigger, this.locked});

  /// The conversation controller.
  final AgentController controller;

  /// Scope of a request on a locked device (WP154 L2); `null` = unlocked.
  final LockedScope? locked;

  /// Name of the current trigger (`pushToTalk`, `assistant`).
  final String? Function() trigger;

  @override
  Stream<AgentEvent> run(UserInput input) =>
      controller.submit(input, trigger: trigger(), locked: locked);

  @override
  void cancel() => controller.cancel();
}
