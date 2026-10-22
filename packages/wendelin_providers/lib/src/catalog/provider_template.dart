import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Kind of credentials a template asks for in the setup dialog.
enum TemplateAuth {
  /// An API key is required.
  apiKey,

  /// An API key may be entered (e.g. a proxy in front of a local server).
  optionalApiKey,

  /// No authentication (local servers).
  none,
}

/// A model recommended for a template, with the numbers behind it
/// (source: `docs/notes/model-recommendation.md`).
@immutable
final class ModelRecommendation {
  /// Creates a recommendation.
  const ModelRecommendation({
    required this.modelId,
    required this.hits,
    required this.runs,
    required this.p50Seconds,
    required this.measured,
    this.weakerThanTee = false,
  });

  /// Model id as the provider lists it.
  final String modelId;

  /// Passed runs of the live evaluation.
  final int hits;

  /// All runs of the live evaluation.
  final int runs;

  /// Median latency of the agent loop in seconds.
  final double p50Seconds;

  /// Measurement date (ISO `yyyy-MM-dd`).
  final String measured;

  /// Best model of this provider, but measurably weaker than the TEE
  /// favourites (the UI says so honestly).
  final bool weakerThanTee;
}

const _measured = '2026-10-20';

/// Recommended models per template id, the single place for them. Templates
/// that are missing here (Mistral, OpenRouter, Ollama, custom) were not
/// measured and recommend nothing.
const modelRecommendations = <String, List<ModelRecommendation>>{
  'claude': [
    ModelRecommendation(
      modelId: 'claude-haiku-5-5',
      hits: 58,
      runs: 58,
      p50Seconds: 1.9,
      measured: _measured,
    ),
  ],
  'openai': [
    ModelRecommendation(
      modelId: 'gpt-5-mini',
      hits: 51,
      runs: 58,
      p50Seconds: 2.0,
      measured: _measured,
    ),
  ],
  'phala': [
    ModelRecommendation(
      modelId: 'google/gemma-4-31b-it',
      hits: 58,
      runs: 58,
      p50Seconds: 1.8,
      measured: _measured,
    ),
  ],
  'tinfoil': [
    ModelRecommendation(
      modelId: 'gemma4-31b',
      hits: 57,
      runs: 58,
      p50Seconds: 1.9,
      measured: _measured,
    ),
  ],
  'near': [
    ModelRecommendation(
      modelId: 'Qwen/Qwen3.6-35B-A3B-FP8',
      hits: 51,
      runs: 58,
      p50Seconds: 2.3,
      measured: _measured,
      weakerThanTee: true,
    ),
  ],
};

/// A preset for the provider setup dialog.
@immutable
final class ProviderTemplate {
  /// Creates a template.
  const ProviderTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.auth,
    required this.privacy,
    this.baseUrl,
    this.keyPageUrl,
    this.suggestedModel,
    this.options = const {},
  });

  /// Stable id (`claude`, `openai`, …).
  final String id;

  /// Display name.
  final String name;

  /// Adapter family.
  final ProviderType type;

  /// Default base URL; `null` = adapter default or user input (custom).
  final String? baseUrl;

  /// Credentials the dialog asks for.
  final TemplateAuth auth;

  /// Where the user creates an API key.
  final String? keyPageUrl;

  /// Default data-protection level.
  final PrivacyLevel privacy;

  /// Model preselected in the dialog (the user can change it).
  final String? suggestedModel;

  /// Default adapter options (`ProviderProfile.options`).
  final Map<String, Object?> options;

  /// Recommended models of this template, best first (may be empty).
  List<ModelRecommendation> get recommendations =>
      modelRecommendations[id] ?? const [];

  /// Builds a profile from this template. [secretRef] names the stored API
  /// key; without it the profile uses [NoAuth].
  ProviderProfile toProfile({
    required String id,
    String? name,
    String? secretRef,
    String? model,
    String? baseUrl,
  }) {
    final chosenModel = model ?? suggestedModel;
    if (chosenModel == null) {
      throw ArgumentError.value(model, 'model', 'Modell fehlt');
    }
    final url = baseUrl ?? this.baseUrl;
    if (type == ProviderType.openaiCompatible && url == null) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Base-URL fehlt');
    }
    if (auth == TemplateAuth.apiKey && secretRef == null) {
      throw ArgumentError.value(secretRef, 'secretRef', 'API-Key fehlt');
    }
    return ProviderProfile(
      id: id,
      name: name ?? this.name,
      type: type,
      baseUrl: url,
      defaultModel: chosenModel,
      privacy: privacy,
      authMethod: secretRef == null || auth == TemplateAuth.none
          ? const NoAuth()
          : ApiKeyAuth(secretRef),
      options: options,
    );
  }

  @override
  String toString() => 'ProviderTemplate($id)';
}

/// Built-in templates in display order.
const providerTemplates = <ProviderTemplate>[
  ProviderTemplate(
    id: 'claude',
    name: 'Claude',
    type: ProviderType.anthropic,
    baseUrl: 'https://api.anthropic.com',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://platform.claude.com/settings/keys',
    privacy: PrivacyLevel.standard,
    suggestedModel: 'claude-haiku-5-5',
  ),
  ProviderTemplate(
    id: 'openai',
    name: 'OpenAI',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://api.openai.com/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://platform.openai.com/api-keys',
    privacy: PrivacyLevel.standard,
    suggestedModel: 'gpt-5-mini',
  ),
  ProviderTemplate(
    id: 'openrouter',
    name: 'OpenRouter',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://openrouter.ai/api/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://openrouter.ai/settings/keys',
    privacy: PrivacyLevel.standard,
  ),
  ProviderTemplate(
    id: 'mistral',
    name: 'Mistral',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://api.mistral.ai/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://console.mistral.ai/api-keys',
    privacy: PrivacyLevel.eu,
    suggestedModel: 'mistral-small-latest',
  ),
  ProviderTemplate(
    id: 'phala',
    name: 'Phala (RedPill)',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://api.redpill.ai/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://redpill.ai',
    privacy: PrivacyLevel.tee,
    suggestedModel: 'google/gemma-4-31b-it',
    options: {'teeModelsOnly': true, 'attestation': 'phala'},
  ),
  ProviderTemplate(
    id: 'near',
    name: 'NEAR AI (TEE)',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://cloud-api.near.ai/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://cloud.near.ai',
    privacy: PrivacyLevel.tee,
    suggestedModel: 'Qwen/Qwen3.6-35B-A3B-FP8',
    options: {'attestation': 'near', 'ownedBy': 'nearai', 'toolsOnly': true},
  ),
  ProviderTemplate(
    id: 'tinfoil',
    name: 'Tinfoil (TEE)',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://inference.tinfoil.sh/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://tinfoil.sh',
    privacy: PrivacyLevel.tee,
    // Live evaluation 2026-10-20 (docs/notes/model-recommendation.md):
    // `gemma4-31b` 57/58, `gpt-oss-120b` only 50/58.
    suggestedModel: 'gemma4-31b',
    options: {'attestation': 'tinfoil', 'modelType': 'chat', 'toolsOnly': true},
  ),
  ProviderTemplate(
    id: 'ollama',
    name: 'Ollama',
    type: ProviderType.openaiCompatible,
    baseUrl: 'http://localhost:11434/v1',
    auth: TemplateAuth.none,
    privacy: PrivacyLevel.local,
  ),
  ProviderTemplate(
    id: 'custom',
    name: 'Eigener Endpunkt',
    type: ProviderType.openaiCompatible,
    auth: TemplateAuth.optionalApiKey,
    privacy: PrivacyLevel.standard,
  ),
];

/// The template with [id], or `null`.
ProviderTemplate? providerTemplateById(String id) {
  for (final t in providerTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
