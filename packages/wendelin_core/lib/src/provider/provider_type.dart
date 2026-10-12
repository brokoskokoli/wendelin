import 'package:meta/meta.dart';

/// API family of a provider; selects the adapter.
enum ProviderType {
  /// Anthropic Messages API.
  anthropic,

  /// OpenAI Chat Completions and compatible servers (OpenRouter, Mistral,
  /// Ollama, Phala, …).
  openaiCompatible,

  /// Scripted test provider (`FakeLlmProvider`, demo mode).
  fake,
}

/// What a provider (with its configured model) supports.
@immutable
final class ProviderCapabilities {
  /// Creates capabilities; every flag defaults to `false`.
  const ProviderCapabilities({
    this.tools = false,
    this.vision = false,
    this.streaming = false,
    this.promptCaching = false,
    this.tee = false,
  });

  /// Function/tool calling.
  final bool tools;

  /// Image input.
  final bool vision;

  /// Incremental streaming of deltas.
  final bool streaming;

  /// Provider-side prompt caching.
  final bool promptCaching;

  /// Runs in an attested trusted execution environment.
  final bool tee;

  @override
  bool operator ==(Object other) =>
      other is ProviderCapabilities &&
      other.tools == tools &&
      other.vision == vision &&
      other.streaming == streaming &&
      other.promptCaching == promptCaching &&
      other.tee == tee;

  @override
  int get hashCode => Object.hash(tools, vision, streaming, promptCaching, tee);

  @override
  String toString() =>
      'ProviderCapabilities(tools: $tools, vision: $vision, '
      'streaming: $streaming, promptCaching: $promptCaching, tee: $tee)';
}
