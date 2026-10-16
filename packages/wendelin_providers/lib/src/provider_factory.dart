import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import 'anthropic/anthropic_adapter.dart';
import 'anthropic/anthropic_options.dart';
import 'catalog/model_catalog.dart';
import 'common/credentials.dart';
import 'common/http_settings.dart';
import 'common/redactor.dart';
import 'openai/openai_adapter.dart';
import 'openai/openai_options.dart';
import 'tee/attestation_crypto.dart';
import 'tee/attestation_log.dart';
import 'tee/attestation_pin_store.dart';
import 'tee/attested_provider.dart';
import 'tee/e2ee_v2.dart';
import 'tee/gpu_attestation.dart';
import 'tee/near/near_crypto.dart';
import 'tee/near/near_e2ee.dart';
import 'tee/near/near_verifier.dart';
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
    this.tlsConnect,
    this.nearCrypto,
  });

  /// Field encryption of NEAR AI profiles (Rust in the app). Without it a
  /// NEAR profile is not built (fail-closed).
  final NearCrypto? nearCrypto;

  /// Builds the HTTP client of a TEE profile on top of the pin [TlsPinGate]:
  /// `enforce: true` for everything that carries content, `false` for the
  /// attestation endpoints. `null` = [PinnedHttpClient] (production). Only
  /// device tests with recorded fixtures replace it; the pin is then not
  /// enforced by the transport.
  final http.Client Function(TlsPinGate gate, {required bool enforce})?
  pinnedClient;

  /// Opens the TLS connections of the default [PinnedHttpClient]s; `null` =
  /// system sockets (production). Tests record or stub it.
  final TlsConnect? tlsConnect;

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

/// Which checked TEE protocol a profile speaks.
enum AttestationKind {
  /// Not attested.
  none,

  /// Phala/RedPill gateway (ACI, E2EE v2; ADR 0014, 0018).
  phala,

  /// NEAR AI Cloud (TDX report per model, E2EE with tools; ADR 0019).
  near,
}

/// The protocol [profile] must be attested with: bound to the template
/// option `attestation: phala|near` (or an older profile on the RedPill
/// host), not to the privacy level, so a profile is only „TEE“ when the app
/// really checks it.
AttestationKind attestationKind(ProviderProfile profile) {
  if (profile.type != ProviderType.openaiCompatible) {
    return AttestationKind.none;
  }
  return switch (profile.options['attestation']) {
    'phala' => AttestationKind.phala,
    'near' => AttestationKind.near,
    _ =>
      _normalizedHost(profile.baseUrl) == 'api.redpill.ai'
          ? AttestationKind.phala
          : AttestationKind.none,
  };
}

/// Whether the answers of [profile] must be attested ([attestationKind]).
bool needsAttestation(ProviderProfile profile) =>
    attestationKind(profile) != AttestationKind.none;

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
        if (attestation != null &&
            attestationKind(profile) == AttestationKind.near) {
          return _near(
            profile,
            baseUrl,
            secrets,
            attestation,
            settings: settings,
            client: client,
            vision: model?.supportsVision ?? false,
          );
        }
        final attested = attestation != null && needsAttestation(profile);
        final gate = attested
            ? TlsPinGate(spkiSha256: attestation.crypto.spkiSha256)
            : null;
        final connect = attestation?.tlsConnect;
        final build =
            attestation?.pinnedClient ??
            (TlsPinGate g, {required bool enforce}) =>
                PinnedHttpClient(gate: g, enforce: enforce, connect: connect);
        final credentials = Credentials(
          profile.authMethod,
          secrets,
          style: ApiKeyStyle.bearer,
        );
        final adapter = OpenAiChatAdapter(
          wireCodec: attested
              ? PhalaE2eeChannel(crypto: attestation.crypto)
              : null,
          baseUrl: Uri.parse(baseUrl),
          credentials: credentials,
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
            // The receipt belongs to the key's owner: the request carries the
            // key, so it goes over the connection pinned to the attested
            // session.
            receiptClient: build(gate, enforce: true),
            receiptHeaders: () => credentials.headers(Redactor()),
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

  /// NEAR AI Cloud: E2EE with tools to the attested model key, one report
  /// per model (the profile's `defaultModel`), TLS pin of the gateway.
  static LlmProvider _near(
    ProviderProfile profile,
    String baseUrl,
    SecretReader secrets,
    AttestationWiring attestation, {
    required HttpSettings settings,
    required http.Client? client,
    required bool vision,
  }) {
    final cipher = attestation.nearCrypto;
    if (cipher == null) {
      throw ArgumentError.value(
        profile.id,
        'attestation.nearCrypto',
        'NEAR-Profile brauchen die Verschlüsselung des Prüfmoduls',
      );
    }
    final gate = TlsPinGate(spkiSha256: attestation.crypto.spkiSha256);
    final build =
        attestation.pinnedClient ??
        (TlsPinGate g, {required bool enforce}) => PinnedHttpClient(
          gate: g,
          enforce: enforce,
          connect: attestation.tlsConnect,
        );
    final credentials = Credentials(
      profile.authMethod,
      secrets,
      style: ApiKeyStyle.bearer,
    );
    final root = Uri.parse(baseUrl);
    final adapter = OpenAiChatAdapter(
      wireCodec: NearE2eeChannel(crypto: cipher),
      baseUrl: root,
      credentials: credentials,
      defaultModel: profile.defaultModel,
      label: profile.name,
      client: build(gate, enforce: true),
      extraHeaders: profile.extraHeaders,
      options: OpenAiOptions.fromMap(profile.options),
      capabilities: ProviderCapabilities(
        tools: true,
        streaming: true,
        vision: vision,
        tee: true,
      ),
      settings: settings,
    );
    Future<Map<String, String>> auth() => credentials.headers(Redactor());
    final verifier = NearVerifier(
      crypto: attestation.crypto,
      baseUrl: root,
      model: profile.defaultModel,
      profileId: profile.id,
      headers: auth,
      // The report endpoint needs the key and the pin comes out of the
      // report, so only this first request carries the key over a
      // connection that is not yet pinned (TLS validated by the system).
      client: build(gate, enforce: false),
      // Receipts go over the pinned connection.
      receiptClient: build(gate, enforce: true),
      tlsPin: gate,
      settings: settings,
      pins: attestation.pins,
      nonceSource: attestation.nonceSource,
    );
    return AttestedProvider(
      inner: adapter,
      verifier: verifier,
      profileId: profile.id,
      tlsPin: gate,
      // NEAR attests per model.
      sessionScope: '$root|${profile.defaultModel}',
      requireUpstreamEnforced: false,
      // GPU evidence comes from the verified report (same nonce as the
      // quote); NRAS gets no key. [client] is only for NRAS.
      gpuVerifier: NrasGpuVerifier(
        baseUrl: root,
        client: client ?? defaultHttpClient(),
        evidenceSource: verifier.gpuEvidence,
      ),
      gpuMode: attestation.gpuMode,
      logSink: attestation.logSink,
      settings: settings,
    );
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
