import 'dart:typed_data';

/// Verification status of the platform TCB of a TDX/SGX quote (Intel
/// terms). Mapping to the traffic light: see `AttestationPolicy`.
enum TcbStatus {
  /// Fully up to date.
  upToDate,

  /// Software hardening needed (advisories apply).
  swHardeningNeeded,

  /// Configuration change needed.
  configurationNeeded,

  /// Both configuration change and software hardening needed.
  configurationAndSwHardeningNeeded,

  /// TCB level is outdated.
  outOfDate,

  /// Outdated and configuration change needed.
  outOfDateConfigurationNeeded,

  /// The TCB level or the key is revoked.
  revoked,
}

/// Fields of a quote whose signature chain was verified, plus the TCB status.
final class QuoteVerdict {
  /// Creates a verdict.
  QuoteVerdict({
    required this.tcbStatus,
    required this.reportData,
    required this.rtmr3,
    this.advisoryIds = const [],
  });

  /// Platform TCB status.
  final TcbStatus tcbStatus;

  /// The 64 `report_data` bytes of the quote.
  final Uint8List reportData;

  /// The 48-byte runtime measurement register 3.
  final Uint8List rtmr3;

  /// Intel security advisories that apply (for the hint to the user).
  final List<String> advisoryIds;
}

/// Opaque quote collateral (PCK chain, TCB info, QE identity, CRLs) as the
/// implementation of [AttestationCrypto] fetched or cached it.
final class QuoteCollateral {
  /// Creates collateral from its serialised form.
  QuoteCollateral(this.json, {this.validUntil});

  /// Serialised collateral (JSON bytes), format owned by the implementation.
  final Uint8List json;

  /// Earliest `nextUpdate` among the parts; the cache renews before that.
  final DateTime? validUntil;
}

/// The quote could not be verified (bad signature, expired collateral,
/// malformed quote, revoked key, …). [reason] is secret-free.
final class QuoteVerificationException implements Exception {
  /// Creates the exception.
  const QuoteVerificationException(this.reason);

  /// Why verification failed.
  final String reason;

  @override
  String toString() => 'QuoteVerificationException: $reason';
}

/// Collateral could not be obtained (Intel PCS unreachable, no cache).
/// Transient: the check is retried, it is not a failed verification.
final class CollateralUnavailableException implements Exception {
  /// Creates the exception.
  const CollateralUnavailableException(this.reason);

  /// What went wrong.
  final String reason;

  @override
  String toString() => 'CollateralUnavailableException: $reason';
}

/// Cryptographic primitives of the attestation, implemented in Rust by WP47
/// (`flutter_rust_bridge`) and by `FakeAttestationCrypto` in tests.
///
/// Contract (suite: `attestationCryptoContract` in `testing.dart`):
/// - [verifyQuote] throws [QuoteVerificationException] if the quote is not
///   valid against [QuoteCollateral] at [now] (signature chain, collateral
///   expired at `now`, revoked); it never returns a verdict for an invalid
///   quote. Otherwise the verdict carries the TCB status and the report
///   fields of the *verified* quote.
/// - [collateralFor] throws [CollateralUnavailableException] when neither
///   network nor cache can provide it.
/// - The hash functions and [verifyEd25519] are pure; [verifyEd25519]
///   returns `false` (never throws) for malformed keys or signatures.
/// - [spkiSha256] hashes the DER `SubjectPublicKeyInfo` of the X.509
///   certificate [certificateDer]; throws [FormatException] if unparsable.
abstract interface class AttestationCrypto {
  /// Verifies a TDX/SGX quote against [collateral] at time [now].
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  );

  /// Fetches (Intel PCS) or loads from the cache the collateral for [quote].
  Future<QuoteCollateral> collateralFor(Uint8List quote);

  /// Verifies an Ed25519 [signature] over [message].
  bool verifyEd25519(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  );

  /// SHA-256 of [data].
  Uint8List sha256(Uint8List data);

  /// SHA-384 of [data].
  Uint8List sha384(Uint8List data);

  /// SHA-256 of the SubjectPublicKeyInfo of a DER certificate.
  Uint8List spkiSha256(Uint8List certificateDer);
}
