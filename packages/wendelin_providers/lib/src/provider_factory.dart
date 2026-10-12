import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import 'anthropic/anthropic_adapter.dart';
import 'anthropic/anthropic_options.dart';
import 'catalog/model_catalog.dart';
import 'common/credentials.dart';
import 'common/http_settings.dart';
import 'openai/openai_adapter.dart';
import 'openai/openai_options.dart';

/// Creates the matching adapter for a [ProviderProfile].
abstract final class ProviderFactory {
  /// Returns an [LlmProvider] for [profile]; secrets are read lazily per
  /// request through [secrets]. [client] and [settings] are injectable for
  /// tests; [catalog] supplies vision support of OpenAI-compatible models.
  ///
  /// Throws [ArgumentError] for profiles without an adapter (`fake`) or an
  /// OpenAI-compatible profile without base URL.
  static LlmProvider create(
    ProviderProfile profile,
    SecretReader secrets, {
    http.Client? client,
    HttpSettings settings = const HttpSettings(),
    ModelCatalog? catalog,
  }) {
    switch (profile.type) {
      case ProviderType.anthropic:
        return AnthropicMessagesAdapter(
          credentials: Credentials(
            profile.authMethod,
            secrets,
            style: ApiKeyStyle.xApiKey,
          ),
          defaultModel: profile.defaultModel,
          baseUrl: profile.baseUrl == null ? null : Uri.parse(profile.baseUrl!),
          client: client,
          extraHeaders: profile.extraHeaders,
          options: AnthropicOptions.fromMap(profile.options),
          settings: settings,
        );
      case ProviderType.openaiCompatible:
        final baseUrl = profile.baseUrl;
        if (baseUrl == null) {
          throw ArgumentError.value(
            profile.baseUrl,
            'profile.baseUrl',
            'OpenAI-kompatible Profile brauchen eine Base-URL',
          );
        }
        final model = (catalog ?? ModelCatalog.builtIn()).lookup(
          profile.defaultModel,
        );
        return OpenAiChatAdapter(
          baseUrl: Uri.parse(baseUrl),
          credentials: Credentials(
            profile.authMethod,
            secrets,
            style: ApiKeyStyle.bearer,
          ),
          defaultModel: profile.defaultModel,
          label: profile.name,
          client: client,
          extraHeaders: profile.extraHeaders,
          options: OpenAiOptions.fromMap(profile.options),
          capabilities: ProviderCapabilities(
            tools: true,
            streaming: true,
            vision: model?.supportsVision ?? false,
            tee: profile.privacy == PrivacyLevel.tee,
          ),
          settings: settings,
        );
      case ProviderType.fake:
        throw ArgumentError.value(
          profile.type,
          'profile.type',
          'Für Fake-Profile gibt es keinen HTTP-Adapter',
        );
    }
  }
}
