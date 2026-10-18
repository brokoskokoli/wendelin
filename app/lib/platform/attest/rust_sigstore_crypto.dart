import 'package:wendelin_providers/wendelin_providers.dart' as p;

import 'attest_backend.dart';

/// `SigstoreCrypto` über das Rust-Modul `native/attest` (WP76b). Fehler des
/// Prüfmoduls werden zu roten [p.SigstoreVerdict]s ohne Details.
final class RustSigstoreCrypto implements p.SigstoreCrypto {
  /// Erstellt die Implementierung.
  const RustSigstoreCrypto(this.backend);

  /// Rust-Funktionen.
  final AttestBackend backend;

  @override
  Future<p.SigstoreVerdict> verifyRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  }) async {
    try {
      final v = await backend.verifyTinfoilRelease(
        bundleJson: bundleJson,
        repo: repo,
        tag: tag,
        digestHex: digestHex,
        reportMeasurementHex: reportMeasurementHex,
      );
      return p.SigstoreVerdict(
        dsseOk: v.dsseOk,
        chainOk: v.chainOk,
        identityOk: v.identityOk,
        rekorOk: v.rekorOk,
        measurementOk: v.measurementOk,
        snpMeasurementHex: v.snpMeasurementHex,
        releaseTag: v.releaseTag,
        integratedTime: v.integratedTime.toInt(),
        errors: v.errors,
      );
    } on Object catch (e) {
      return p.SigstoreVerdict(
        dsseOk: false,
        chainOk: false,
        identityOk: false,
        rekorOk: false,
        measurementOk: false,
        errors: ['Prüfmodul: ${e.runtimeType}'],
      );
    }
  }
}
