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

  /// The model refused.
  refusal,

  /// Anything else the provider reports.
  other,
}
