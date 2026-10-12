/// Why the model stopped generating.
enum StopReason {
  /// Natural end of the answer.
  endTurn,

  /// The model wants tool calls executed.
  toolUse,

  /// Output token limit reached.
  maxTokens,

  /// A stop sequence was produced.
  stopSequence,

  /// The provider paused a long-running turn (Anthropic server tools such as
  /// web search). The agent must continue by sending the conversation,
  /// including the partial assistant message, again – this is not a final
  /// answer and not a tool round.
  pauseTurn,

  /// The model refused.
  refusal,

  /// Anything else the provider reports.
  other,
}
