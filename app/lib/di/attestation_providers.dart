import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../platform/attest/attest_backend.dart';
import '../platform/attest/collateral_cache.dart';
import '../platform/attest/pcs_collateral_client.dart';
import '../platform/attest/rust_attestation_crypto.dart';
import '../platform/channel_notifier.dart';
import 'app_settings.dart';
import 'attestation_hub.dart';
import 'providers.dart';

/// Rust-Prüfmodul (lädt `libwendelin_attest.so` beim ersten Zugriff). Tests überschreiben es mit einem Fake.
final attestBackendProvider = FutureProvider<AttestBackend>(
  (ref) => FrbAttestBackend.init(),
);

/// Ordner des Kollateral-Caches (App-Support, nicht in Backups relevant: nur öffentliche Intel-Daten).
final attestCacheDirProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/attest');
});

/// Kryptografie der TEE-Prüfung (Port aus WP46, Implementierung WP47).
final attestationCryptoProvider = FutureProvider<AttestationCrypto>((
  ref,
) async {
  final backend = await ref.watch(attestBackendProvider.future);
  final dir = await ref.watch(attestCacheDirProvider.future);
  final clock = ref.watch(clockProvider);
  return RustAttestationCrypto(
    backend: backend,
    pcs: PcsCollateralClient(
      client: ref.watch(httpClientProvider),
      backend: backend,
    ),
    cache: CollateralCache(dir: dir, now: () => clock.now()),
    clock: () => clock.now(),
  );
});

/// Waits until the Rust check module ([crypto]) is loaded so the (synchronous) provider
/// factory finds it. Without it (tests, unsupported platform) the factory
/// refuses TEE profiles, it never builds them unchecked.
Future<void> awaitCheckModule(Future<AttestationCrypto> crypto) async {
  try {
    await crypto;
  } on Object {
    // Reported when a TEE profile is built.
  }
}

/// Whether any of [profiles] must be attested.
bool anyNeedsAttestation(Iterable<ProviderProfile> profiles) =>
    profiles.any(needsAttestation);

/// System notifications (failed GPU check after the answer).
final attestationNotifierProvider = Provider<AttestationNotifier>(
  (ref) => const ChannelAttestationNotifier(),
);

/// Pin store of the attested providers.
final attestationPinStoreProvider = Provider<AttestationPinStore>(
  (ref) => SettingsAttestationPinStore(ref.watch(storageProvider).settings),
);

/// GPU check of TEE models at NVIDIA: off, before or after the request.
final gpuCheckModeProvider = NotifierProvider<GpuCheckModePref, GpuCheckMode>(
  GpuCheckModePref.new,
);

/// GPU mode preference; applies the change to the live providers.
final class GpuCheckModePref extends Notifier<GpuCheckMode> {
  @override
  GpuCheckMode build() => ref.watch(startupProvider).gpuCheck;

  /// Stores [mode]; for „nachher“ it first asks for the notification
  /// permission (the warning is a system notification).
  Future<void> set(GpuCheckMode mode) async {
    if (mode == GpuCheckMode.after) {
      final notifier = ref.read(attestationNotifierProvider);
      if (!await notifier.hasPermission()) await notifier.requestPermission();
    }
    state = mode;
    ref.read(attestationHubProvider).gpuMode = mode;
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.gpuCheck, mode.name);
  }
}

/// The live TEE providers, their results and actions.
final Provider<AttestationHub> attestationHubProvider =
    Provider<AttestationHub>((ref) {
      final hub = AttestationHub(
        notifier: ref.watch(attestationNotifierProvider),
        gpuMode: ref.read(gpuCheckModeProvider),
        nameOf: (id) =>
            ref.read(providerConfigProvider).asData?.value?.nameOf(id) ?? id,
      );
      ref.onDispose(() => unawaited(hub.dispose()));
      return hub;
    });

/// Transport of the TEE check (HTTP client, clock, nonce). `null` in the app
/// (real network); the device test overrides it with recorded fixtures while
/// everything else, the factory included, stays the production path.
final class AttestationTransport {
  /// Creates the transport.
  const AttestationTransport({
    required this.client,
    required this.settings,
    this.nonceSource,
    this.pinnedClient,
  });

  /// HTTP client of the adapter and the checks.
  final http.Client client;

  /// Client of the pinned connections on top of the pin gate (like
  /// `PinnedHttpClient`: judges the certificate of each request against the
  /// attestation); `null` = [client] as is (no TLS connection to pin).
  final http.Client Function(TlsPinGate gate, {required bool enforce})?
  pinnedClient;

  /// Clock and log of the HTTP side.
  final HttpSettings settings;

  /// Fixed nonce of the recording.
  final Uint8List Function()? nonceSource;
}

/// Override point of [AttestationTransport] (tests only).
final attestationTransportProvider = Provider<AttestationTransport?>(
  (ref) => null,
);

/// Wiring the provider factory gives to TEE profiles; `null` while the
/// check module is not loaded.
AttestationWiring? attestationWiringOf(Ref ref) {
  final crypto = ref.read(attestationCryptoProvider).asData?.value;
  if (crypto == null) return null;
  final transport = ref.read(attestationTransportProvider);
  return AttestationWiring(
    crypto: crypto,
    logSink: ref.read(attestationLogWriterProvider),
    pins: ref.read(attestationPinStoreProvider),
    gpuMode: ref.read(gpuCheckModeProvider),
    nonceSource: transport?.nonceSource,
    // Production: the pinned TLS clients of the package. The device test
    // replays recorded fixtures through its own client and therefore has no
    // TLS connection to pin.
    pinnedClient: transport == null
        ? null
        : transport.pinnedClient ??
              (gate, {required enforce}) => transport.client,
  );
}
