/// Result per stage of the Sigstore check of a Tinfoil release (WP76b); each
/// stage is evaluated on its own, so a red stage never hides the others.
final class SigstoreVerdict {
  /// Creates a verdict.
  const SigstoreVerdict({
    required this.dsseOk,
    required this.chainOk,
    required this.identityOk,
    required this.rekorOk,
    required this.measurementOk,
    this.snpMeasurementHex = '',
    this.releaseTag = '',
    this.integratedTime = 0,
    this.errors = const [],
  });

  /// DSSE signature, in-toto statement and subject digest (`tinfoil.hash`).
  final bool dsseOk;

  /// Fulcio chain to the embedded trust root, valid at the Rekor time.
  final bool chainOk;

  /// GitHub Actions issuer, expected repository, workflow at `refs/tags/<tag>`.
  final bool identityOk;

  /// SET, checkpoint, Merkle inclusion proof and binding of the log entry.
  final bool rekorOk;

  /// Signed release measurement equals the measurement of the SNP report.
  final bool measurementOk;

  /// Measurement of the signed release (SHA-384, hex); empty if unreadable.
  final String snpMeasurementHex;

  /// Release tag from the verified workflow identity.
  final String releaseTag;

  /// Entry time signed by Rekor (Unix seconds).
  final int integratedTime;

  /// Hard failures (German, no secrets).
  final List<String> errors;

  /// All stages green and no errors: the report measurement belongs to the
  /// signed release.
  bool get allOk =>
      errors.isEmpty &&
      dsseOk &&
      chainOk &&
      identityOk &&
      rekorOk &&
      measurementOk;
}

/// Sigstore verification of the Tinfoil router release (WP76b). Rust in the
/// app (`native/attest/src/sigstore.rs`, embedded trust root), `FakeSigstoreCrypto`
/// in tests. The caller fetches `tinfoil.hash` and the attestation bundle of the
/// release (GitHub) and passes the measurement from `SnpReportInfo`.
abstract interface class SigstoreCrypto {
  /// Verifies [bundleJson] for [repo]@[tag] (`owner/name`, tag as released),
  /// [digestHex] = content of `tinfoil.hash`, and compares the signed SNP
  /// measurement with [reportMeasurementHex]. Works offline (a cached bundle
  /// stays valid: validity is judged at the Rekor time, not "now").
  Future<SigstoreVerdict> verifyRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  });
}
