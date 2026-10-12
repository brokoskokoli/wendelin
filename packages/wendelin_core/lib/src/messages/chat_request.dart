import 'package:meta/meta.dart';

import 'message.dart';
import 'tool_choice.dart';
import 'tool_spec.dart';

/// A provider-neutral request for one model call.
///
/// The system prompt is kept separate from [messages]: Anthropic expects it
/// as a top-level field, OpenAI-compatible adapters prepend it as a `system`
/// message (see ADR 0002).
@immutable
final class ChatRequest {
  /// Creates a request; lists and maps are copied unmodifiable.
  ChatRequest({
    required List<Message> messages,
    required this.model,
    required this.maxTokens,
    List<ToolSpec> tools = const [],
    this.temperature,
    this.toolChoice = ToolChoice.auto,
    Map<String, String> metadata = const {},
    this.systemPrompt,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(tools),
       metadata = Map.unmodifiable(metadata);

  /// Conversation so far (without the system prompt).
  final List<Message> messages;

  /// Tools offered to the model, in stable order (prompt caching).
  final List<ToolSpec> tools;

  /// Provider model id.
  final String model;

  /// Upper bound for generated tokens.
  final int maxTokens;

  /// Sampling temperature; `null` = provider default.
  final double? temperature;

  /// Tool usage constraint.
  final ToolChoice toolChoice;

  /// Free-form metadata (e.g. session id) – adapters may ignore it; never
  /// put secrets here.
  final Map<String, String> metadata;

  /// System prompt, sent separately from [messages].
  final String? systemPrompt;

  /// Returns a copy with the given fields replaced.
  ChatRequest copyWith({
    List<Message>? messages,
    List<ToolSpec>? tools,
    String? model,
    int? maxTokens,
    double? temperature,
    ToolChoice? toolChoice,
    Map<String, String>? metadata,
    String? systemPrompt,
  }) => ChatRequest(
    messages: messages ?? this.messages,
    tools: tools ?? this.tools,
    model: model ?? this.model,
    maxTokens: maxTokens ?? this.maxTokens,
    temperature: temperature ?? this.temperature,
    toolChoice: toolChoice ?? this.toolChoice,
    metadata: metadata ?? this.metadata,
    systemPrompt: systemPrompt ?? this.systemPrompt,
  );

  @override
  String toString() =>
      'ChatRequest($model, ${messages.length} messages, '
      '${tools.length} tools)';
}
