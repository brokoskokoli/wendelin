import 'dart:typed_data';

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
import 'tee/tls_pin_gate.dart';
import 'tee/tls_pinned_client.dart';

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
    this.nonceSource,
    this.pinnedClient,
  });

  /// Builds the HTTP client of a TEE profile on top of the pin [TlsPinGate]:
  /// `enforce: true` for everything that carries content, `false` for the
  /// attestation endpoints. `null` = [PinnedHttpClient] (production). Only
  /// device tests with recorded fixtures replace it; the pin is then not
  /// enforced by the transport.
  final http.Client Function(TlsPinGate gate, {required bool enforce})?
  pinnedClient;

  /// Nonce for the session attestation; `null` = random (production). Only
  /// device tests with recorded fixtures set it.
  final Uint8List Function()? nonceSource;

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

/// Whether [profile] is a Phala/RedPill profile whose answers must be
/// attested: bound to the template option `attestation: phala` (or an older
/// profile on the RedPill host), not to the privacy level, so a profile is
/// only „TEE“ when the app really checks it.
bool needsAttestation(ProviderProfile profile) {
  if (profile.type != ProviderType.openaiCompatible) return false;
  if (profile.options['attestation'] == 'phala') return true;
  return _normalizedHost(profile.baseUrl) == 'api.redpill.ai';
}

/// Host of [url] in lower case and without a trailing dot, so
/// `API.RedPill.ai.` counts as `api.redpill.ai`.
String _normalizedHost(String? url) {
  var host = (Uri.tryParse(url ?? '')?.host ?? '').toLowerCase();
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  return host;
}

/// Privacy level that counts for [profile]: „TEE“ only for profiles the app
/// really attests ([needsAttestation]); an unchecked profile is capped to
/// `standard` (older profiles may still carry `tee`).
PrivacyLevel effectivePrivacy(ProviderProfile profile) =>
    profile.privacy == PrivacyLevel.tee && !needsAttestation(profile)
    ? PrivacyLevel.standard
    : profile.privacy;

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
        if (attestation == null && needsAttestation(profile)) {
          // Fail-closed: a profile that must be attested is never built
          // unchecked.
          throw ArgumentError.value(
            profile.id,
            'attestation',
            'Profile mit TEE-Prüfung brauchen die Prüf-Verdrahtung',
          );
        }
        final attested = attestation != null && needsAttestation(profile);
        final gate = attested
            ? TlsPinGate(spkiSha256: attestation.crypto.spkiSha256)
            : null;
        final build =
            attestation?.pinnedClient ??
            (TlsPinGate g, {required bool enforce}) =>
                PinnedHttpClient(gate: g, enforce: enforce);
        final adapter = OpenAiChatAdapter(
          baseUrl: Uri.parse(baseUrl),
          credentials: Credentials(
            profile.authMethod,
            secrets,
            style: ApiKeyStyle.bearer,
          ),
          defaultModel: profile.defaultModel,
          label: profile.name,
          client: gate == null ? client : build(gate, enforce: true),
          extraHeaders: profile.extraHeaders,
          options: OpenAiOptions.fromMap(
            attested ? _withAciVerified(profile.options) : profile.options,
          ),
          capabilities: ProviderCapabilities(
            tools: true,
            streaming: true,
            vision: model?.supportsVision ?? false,
            tee: attested,
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
            client: build(gate!, enforce: false),
            tlsPin: gate,
            settings: settings,
            pins: attestation.pins,
            trustedCommits: attestation.trustedCommits,
            nonceSource: attestation.nonceSource,
          ),
          profileId: profile.id,
          tlsPin: gate,
          gpuVerifier: NrasGpuVerifier(
            baseUrl: root,
            client: client ?? defaultHttpClient(),
          ),
          gpuMode: attestation.gpuMode,
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
