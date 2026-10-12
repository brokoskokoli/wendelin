/// Author of a [Message] in the internal, provider-neutral format.
///
/// The system prompt normally travels separately in `ChatRequest.systemPrompt`;
/// [system] exists for providers or histories that need it inline.
enum Role {
  /// Instructions for the model.
  system,

  /// The human user.
  user,

  /// The model.
  assistant,

  /// Results of tool calls (content consists of `ToolResultBlock`s).
  tool,
}
