/// What the units of one agent run need from their runner: the ports and
/// settings of `AgentRunner`, without importing it (no import cycle).
/// Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import '../context_builder.dart';
import '../ports.dart';
import '../provider_resolver.dart';

/// The runner's configuration as seen by the units under `src/run/`;
/// `AgentRunner` implements it, the fields are documented there.
abstract interface class RunConfig {
  /// Chooses providers and escalation targets.
  ProviderResolver get resolver;

  /// Builds system prompt, tool specs and messages.
  ContextBuilder get contextBuilder;

  /// Executes tool calls.
  ToolInvoker get invoker;

  /// Time source for limits and tools.
  Clock get clock;

  /// Session id passed to tools.
  String get sessionId;

  /// Prices model calls; `null` = no cost.
  CostEstimator? get costEstimator;

  /// The tools a target with the given privacy level may see.
  ToolCatalog Function(PrivacyLevel level)? get catalogFor;

  /// Called for every call refused because the target may not see the tool.
  void Function(String sessionId, ToolCallBlock call)? get onToolRefused;

  /// Privacy floor of every memory entry.
  PrivacyLevel? get memoryFloor;
}
