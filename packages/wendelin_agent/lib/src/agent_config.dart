import 'package:meta/meta.dart';

/// Limits and persona settings of the agent loop (concept: „Agent-Schleife“,
/// „Routing und Eskalation“).
@immutable
final class AgentConfig {
  /// Creates a configuration; all limits have the concept's defaults.
  const AgentConfig({
    this.maxToolRounds = 8,
    this.maxDuration = const Duration(seconds: 60),
    this.maxTokensPerRequest = 50000,
    this.maxOutputTokens = 1024,
    this.historyTurns = 10,
    this.memoryEntries = 5,
    this.assistantName = 'Wendelin',
    this.userName,
    this.personaAddon,
    this.escalateAfterInvalidToolCalls = 2,
    this.escalateAfterRoundsWithoutResult = 4,
    this.temperature,
  }) : assert(maxToolRounds > 0, 'maxToolRounds must be positive'),
       assert(maxTokensPerRequest > 0, 'maxTokensPerRequest must be positive'),
       assert(maxOutputTokens > 0, 'maxOutputTokens must be positive');

  /// Maximum number of tool rounds per user request (a round = executing
  /// the tool calls of one model answer). The next round is refused.
  final int maxToolRounds;

  /// Maximum total duration of one run.
  final Duration maxDuration;

  /// Token budget of one user request: the sum of all usage (input, output,
  /// cache read and write) over all model calls of the run.
  final int maxTokensPerRequest;

  /// `ChatRequest.maxTokens` of each model call.
  final int maxOutputTokens;

  /// Number of previous turns of the session put into the context.
  final int historyTurns;

  /// Number of memory entries put into the system prompt.
  final int memoryEntries;

  /// Name the assistant uses for itself.
  final String assistantName;

  /// The user's name, if known.
  final String? userName;

  /// Free-form personality addition from the settings.
  final String? personaAddon;

  /// Escalate after this many invalid tool calls (invalid JSON or unknown
  /// tool) of one provider.
  final int escalateAfterInvalidToolCalls;

  /// Escalate when one provider wants more than this many tool rounds
  /// without producing a final answer.
  final int escalateAfterRoundsWithoutResult;

  /// Sampling temperature; `null` = provider default.
  final double? temperature;
}
