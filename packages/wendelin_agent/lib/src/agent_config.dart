import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

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
    this.temperature,
    this.spokenVersion = SpokenVersion.off,
    this.spokenCheckTimeout = const Duration(seconds: 5),
  }) : assert(maxToolRounds > 0, 'maxToolRounds must be positive'),
       assert(maxTokensPerRequest > 0, 'maxTokensPerRequest must be positive'),
       assert(maxOutputTokens > 0, 'maxOutputTokens must be positive');

  /// Copy with another [userName] (`null` = no name in the prompt); used for
  /// the address of the recognized person (WP92b).
  AgentConfig withUserName(String? userName) => AgentConfig(
    maxToolRounds: maxToolRounds,
    maxDuration: maxDuration,
    maxTokensPerRequest: maxTokensPerRequest,
    maxOutputTokens: maxOutputTokens,
    historyTurns: historyTurns,
    memoryEntries: memoryEntries,
    assistantName: assistantName,
    userName: userName,
    personaAddon: personaAddon,
    temperature: temperature,
    spokenVersion: spokenVersion,
    spokenCheckTimeout: spokenCheckTimeout,
  );

  /// Copy without the personal parts of the prompt: no user name and no
  /// free persona text (WP154, a locked device sends nothing personal).
  AgentConfig withoutPersonal() => AgentConfig(
    maxToolRounds: maxToolRounds,
    maxDuration: maxDuration,
    maxTokensPerRequest: maxTokensPerRequest,
    maxOutputTokens: maxOutputTokens,
    historyTurns: historyTurns,
    memoryEntries: memoryEntries,
    assistantName: assistantName,
    temperature: temperature,
    spokenVersion: spokenVersion,
    spokenCheckTimeout: spokenCheckTimeout,
  );

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

  /// Sampling temperature; `null` = provider default.
  final double? temperature;

  /// Stage 2 of the speech-friendly answers (WP41, WP55): for voice requests
  /// the model first writes a short spoken version in `<spoken>…</spoken>`,
  /// then the written answer. Costs more output tokens; off by default. The
  /// level decides how the spoken text is protected after foreign content.
  final SpokenVersion spokenVersion;

  /// Time limit of the check call for [SpokenVersion.checked]; on timeout
  /// the written answer is read out.
  final Duration spokenCheckTimeout;
}
