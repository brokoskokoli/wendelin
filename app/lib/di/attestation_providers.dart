import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/attest/attest_backend.dart';
import '../platform/attest/attestation_port.dart';
import '../platform/attest/collateral_cache.dart';
import '../platform/attest/pcs_collateral_client.dart';
import '../platform/attest/rust_attestation_crypto.dart';
import 'core_providers.dart';

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
