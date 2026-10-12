import 'package:meta/meta.dart';

/// Adapter options for Anthropic, read from `ProviderProfile.options`.
///
/// Keys (all optional):
/// - `enableServerWebSearch` (bool): offer Anthropic's server-side web search.
/// - `webSearchMaxUses` (int): limit searches per request (default 3).
/// - `webSearchToolType` (String): override the tool version
///   (default: `web_search_20260209` for models that support it, otherwise
///   `web_search_20250305`).
/// - `thinking` (`adaptive` | `disabled`): thinking mode.
/// - `thinkingDisplay` (`summarized` | `omitted`): visibility of adaptive
///   thinking text.
/// - `thinkingBudget` (int): fixed budget (`budget_tokens`) – only for
///   older models (e.g. Haiku 4.5); newer models reject it.
/// - `reasoningEffort` (`low` … `max`): `output_config.effort`.
/// - `cacheConversation` (bool, default true): automatic cache breakpoint
///   at the end of the conversation (in addition to tools and system).
@immutable
final class AnthropicOptions {
  /// Creates options.
  const AnthropicOptions({
    this.enableServerWebSearch = false,
    this.webSearchMaxUses = 3,
    this.webSearchToolType,
    this.thinking,
    this.thinkingDisplay,
    this.thinkingBudget,
    this.reasoningEffort,
    this.cacheConversation = true,
  });

  /// Reads options from a profile's option map; unknown keys and values of
  /// the wrong type are ignored.
  factory AnthropicOptions.fromMap(Map<String, Object?> map) {
    T? read<T>(String key) {
      final v = map[key];
      return v is T ? v : null;
    }

    return AnthropicOptions(
      enableServerWebSearch: read<bool>('enableServerWebSearch') ?? false,
      webSearchMaxUses: read<int>('webSearchMaxUses') ?? 3,
      webSearchToolType: read<String>('webSearchToolType'),
      thinking: read<String>('thinking'),
      thinkingDisplay: read<String>('thinkingDisplay'),
      thinkingBudget: read<int>('thinkingBudget'),
      reasoningEffort: read<String>('reasoningEffort'),
      cacheConversation: read<bool>('cacheConversation') ?? true,
    );
  }

  /// See class docs.
  final bool enableServerWebSearch;

  /// See class docs.
  final int webSearchMaxUses;

  /// See class docs.
  final String? webSearchToolType;

  /// See class docs.
  final String? thinking;

  /// See class docs.
  final String? thinkingDisplay;

  /// See class docs.
  final int? thinkingBudget;

  /// See class docs.
  final String? reasoningEffort;

  /// See class docs.
  final bool cacheConversation;
}
