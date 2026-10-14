import 'package:test/test.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'fake_crypto_test.dart' show probeQuoteCase;
import 'fixture_suite.dart';

/// Test hook for WP47: return the Rust implementation of
/// [AttestationCrypto] (flutter_rust_bridge) here and the contract suite and
/// all fixture tests run against the real verification. Until WP47 delivers
/// it, this returns `null` and the tests are skipped.
AttestationCrypto? realAttestationCrypto() => null;

void main() {
  final real = realAttestationCrypto();
  final skip = real == null
      ? 'wartet auf die Rust-Implementierung von WP47 (realAttestationCrypto)'
      : null;

  group('echte Prüfung (WP47)', skip: skip, () {
    attestationCryptoContract(
      () => real!,
      name: 'Rust-AttestationCrypto',
      quoteCase: probeQuoteCase(),
    );
    gatewayFixtureTests(
      () => real!,
      name: 'Rust-AttestationCrypto',
      verifiesQuoteSignature: true,
    );
  });
}
