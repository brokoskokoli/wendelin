import 'sigstore_crypto.dart';

/// [SigstoreCrypto] for tests: returns the configured [verdict] and records
/// the last call.
final class FakeSigstoreCrypto implements SigstoreCrypto {
  /// Creates the fake; by default every stage is green.
  FakeSigstoreCrypto({SigstoreVerdict? verdict}) : verdict = verdict ?? _green;

  /// Answer of [verifyRelease].
  SigstoreVerdict verdict;

  /// Answer per bundle (overrides [verdict] when set).
  SigstoreVerdict Function(String bundleJson)? perBundle;

  /// Number of [verifyRelease] calls.
  int verifies = 0;

  /// Arguments of the last call.
  ({String repo, String tag, String digestHex, String measurementHex})? last;

  static const _green = SigstoreVerdict(
    dsseOk: true,
    chainOk: true,
    identityOk: true,
    rekorOk: true,
    measurementOk: true,
  );

  @override
  Future<SigstoreVerdict> verifyRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  }) async {
    verifies++;
    last = (
      repo: repo,
      tag: tag,
      digestHex: digestHex,
      measurementHex: reportMeasurementHex,
    );
    return perBundle?.call(bundleJson) ?? verdict;
  }
}
