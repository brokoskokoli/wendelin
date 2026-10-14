import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import 'anthropic/anthropic_adapter.dart';
import 'anthropic/anthropic_options.dart';
import 'catalog/model_catalog.dart';
import 'common/credentials.dart';
import 'common/http_settings.dart';
import 'openai/openai_adapter.dart';
import 'openai/openai_options.dart';
import 'tee/attestation_crypto.dart';
import 'tee/attestation_log.dart';
import 'tee/attestation_pin_store.dart';
import 'tee/attested_provider.dart';
import 'tee/gpu_attestation.dart';
import 'tee/phala_verifier.dart';

/// What the factory needs to make a Phala/RedPill profile verifiable
/// (ADR 0014): the crypto port (Rust in the app), where the audit log goes,
/// the pin store and the GPU mode.
final class AttestationWiring {
  /// Creates the wiring.
  const AttestationWiring({
    required this.crypto,
    this.logSink,
    this.pins,
    this.gpuMode = GpuCheckMode.off,
    this.trustedCommits = const {},
  });

  /// Cryptographic primitives.
  final AttestationCrypto crypto;

  /// Receives the audit-log entries.
  final AttestationLogSink? logSink;

  /// Pin store per profile.
  final AttestationPinStore? pins;

  /// Initial GPU check mode.
  final GpuCheckMode gpuMode;

  /// Trusted `repo_commit`s of the gateway; empty = only logged.
  final Set<String> trustedCommits;
}

/// Whether [profile] is a Phala/RedPill TEE profile whose answers must be
/// attested (template option `attestation: phala`, or an older profile on
/// the RedPill host).
bool needsAttestation(ProviderProfile profile) {
  if (profile.type != ProviderType.openaiCompatible ||
      profile.privacy != PrivacyLevel.tee) {
    return false;
  }
  if (profile.options['attestation'] == 'phala') return true;
  return Uri.tryParse(profile.baseUrl ?? '')?.host == 'api.redpill.ai';
}

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
    AttestationWiring? attestation,
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
          catalog: catalog,
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
        final attested = attestation != null && needsAttestation(profile);
        final adapter = OpenAiChatAdapter(
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
          options: OpenAiOptions.fromMap(
            attested ? _withAciVerified(profile.options) : profile.options,
          ),
          capabilities: ProviderCapabilities(
            tools: true,
            streaming: true,
            vision: model?.supportsVision ?? false,
            tee: profile.privacy == PrivacyLevel.tee,
          ),
          settings: settings,
        );
        if (!attested) return adapter;
        final root = Uri.parse(baseUrl);
        return AttestedProvider(
          inner: adapter,
          verifier: PhalaVerifier(
            crypto: attestation.crypto,
            baseUrl: root,
            profileId: profile.id,
            client: client,
            settings: settings,
            pins: attestation.pins,
            trustedCommits: attestation.trustedCommits,
          ),
          profileId: profile.id,
          gpuVerifier: NrasGpuVerifier(
            baseUrl: root,
            client: client ?? defaultHttpClient(),
          ),
          gpuMode: attestation.gpuMode,
          fallbackOnFailure: profile.options['attestationFallback'] == true,
          logSink: attestation.logSink,
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

  /// The gateway must enforce the upstream check: the request carries
  /// `provider.aci_verified: true` (ADR 0014).
  static Map<String, Object?> _withAciVerified(Map<String, Object?> options) {
    final extra = options['extraBody'];
    final body = extra is Map<String, Object?> ? extra : <String, Object?>{};
    final provider = body['provider'];
    return {
      ...options,
      'extraBody': {
        ...body,
        'provider': {
          if (provider is Map<String, Object?>) ...provider,
          'aci_verified': true,
        },
      },
    };
  }
}
