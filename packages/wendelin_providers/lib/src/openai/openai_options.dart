import 'package:meta/meta.dart';

/// Adapter options for OpenAI-compatible servers, read from
/// `ProviderProfile.options`.
///
/// Keys (all optional):
/// - `reasoningEffort` (String): sent as `reasoning_effort`.
/// - `disableReasoning` (bool): asks reasoning models (e.g. GLM via
///   Phala/RedPill) to answer without reasoning; see
///   [OpenAiOptions.disableReasoning].
/// - `emitReasoning` (bool, default true): forward `reasoning_content` /
///   `reasoning` deltas as thinking events; `false` drops them.
/// - `maxTokensField` (`max_tokens` | `max_completion_tokens`): name of the
///   output limit field. Default: `max_completion_tokens` for
///   `api.openai.com`, `max_tokens` elsewhere.
/// - `includeUsage` (bool, default true): request usage in the last chunk
///   (`stream_options.include_usage`). If the server rejects it, the adapter
///   retries once without and remembers that.
/// - `teeModelsOnly` (bool): `listModels` keeps only models with
///   `is_tee: true` (Phala).
/// - `ownedBy` (string): `listModels` keeps only models whose `owned_by`
///   equals it (NEAR AI: `nearai`, the own E2EE fleet, not routed models).
/// - `toolsOnly` (bool): `listModels` keeps only models that support tools.
/// - `modelType` (string): `listModels` keeps only models whose `type`
///   equals it (Tinfoil: `chat`; the catalog also lists audio, embedding,
///   safety models).
/// - `extraBody` (object): merged into the request body (escape hatch for
///   server-specific parameters).
@immutable
final class OpenAiOptions {
  /// Creates options.
  const OpenAiOptions({
    this.reasoningEffort,
    this.disableReasoning = false,
    this.emitReasoning = true,
    this.maxTokensField,
    this.includeUsage = true,
    this.teeModelsOnly = false,
    this.ownedBy,
    this.toolsOnly = false,
    this.modelType,
    this.extraBody = const {},
  });

  /// Reads options from a profile's option map; unknown keys and values of
  /// the wrong type are ignored.
  factory OpenAiOptions.fromMap(Map<String, Object?> map) {
    T? read<T>(String key) {
      final v = map[key];
      return v is T ? v : null;
    }

    return OpenAiOptions(
      reasoningEffort: read<String>('reasoningEffort'),
      disableReasoning: read<bool>('disableReasoning') ?? false,
      emitReasoning: read<bool>('emitReasoning') ?? true,
      maxTokensField: read<String>('maxTokensField'),
      includeUsage: read<bool>('includeUsage') ?? true,
      teeModelsOnly: read<bool>('teeModelsOnly') ?? false,
      ownedBy: read<String>('ownedBy'),
      toolsOnly: read<bool>('toolsOnly') ?? false,
      modelType: read<String>('modelType'),
      extraBody: read<Map<String, Object?>>('extraBody') ?? const {},
    );
  }

  /// See class docs.
  final String? reasoningEffort;

  /// Sends `reasoning: {"enabled": false}` (OpenRouter/RedPill style).
  /// Note: some models (observed: `z-ai/glm-5.3-flash` on RedPill,
  /// 2026-10-13) then write their reasoning into the answer text instead.
  final bool disableReasoning;

  /// See class docs.
  final bool emitReasoning;

  /// See class docs.
  final String? maxTokensField;

  /// See class docs.
  final bool includeUsage;

  /// See class docs.
  final bool teeModelsOnly;

  /// See class docs.
  final String? ownedBy;

  /// See class docs.
  final bool toolsOnly;

  /// See class docs.
  final String? modelType;

  /// See class docs.
  final Map<String, Object?> extraBody;
}
