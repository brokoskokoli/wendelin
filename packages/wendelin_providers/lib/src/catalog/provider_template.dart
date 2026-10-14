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
    suggestedModel: 'z-ai/glm-5.3-flash',
    options: {'teeModelsOnly': true, 'attestation': 'phala'},
  ),
  ProviderTemplate(
    id: 'tinfoil',
    name: 'Tinfoil',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://inference.tinfoil.sh/v1',
    auth: TemplateAuth.apiKey,
    keyPageUrl: 'https://tinfoil.sh',
    // Not „TEE“ in the app's sense until its attestation is checked.
    privacy: PrivacyLevel.standard,
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
