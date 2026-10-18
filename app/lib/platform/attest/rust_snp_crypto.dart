import 'dart:typed_data';

import 'package:wendelin_providers/wendelin_providers.dart' as p;

import 'attest_backend.dart';
import 'generated/snp.dart' as g;

/// `SnpCrypto` über das Rust-Modul `native/attest` (WP76a). Fehler des
/// Prüfmoduls werden zu [p.SnpVerdict]-Fehlern ohne Schlüsselmaterial.
final class RustSnpCrypto implements p.SnpCrypto {
  /// Erstellt die Implementierung.
  const RustSnpCrypto(this.backend);

  /// Rust-Funktionen.
  final AttestBackend backend;

  @override
  p.SnpReportInfo reportInfo(Uint8List report) =>
      _info(backend.snpReportInfo(report));

  @override
  Future<p.SnpVerdict> verify({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required DateTime now,
    required p.SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  }) async {
    final g.SnpVerdict v;
    try {
      v = await backend.verifySnp(
        report: report,
        vcekDer: vcekDer,
        chainPem: chainPem,
        nowUnix: now.toUtc().millisecondsSinceEpoch ~/ 1000,
        policy: g.SnpPolicy(minTcb: _toRust(policy.minTcb)),
        tlsSpkiSha256: tlsSpkiSha256,
        hpkeKey: hpkeKey,
      );
    } on Object catch (e) {
      return p.SnpVerdict(
        reportOk: false,
        chainOk: false,
        vcekMatchesReport: false,
        signatureOk: false,
        policyOk: false,
        tlsBound: false,
        hpkeBound: false,
        errors: ['Prüfmodul: ${e.runtimeType}'],
      );
    }
    return p.SnpVerdict(
      reportOk: v.reportOk,
      chainOk: v.chainOk,
      vcekMatchesReport: v.vcekMatchesReport,
      signatureOk: v.signatureOk,
      policyOk: v.policyOk,
      tlsBound: v.tlsBound,
      hpkeBound: v.hpkeBound,
      product: v.product,
      info: v.info == null ? null : _info(v.info!),
      errors: v.errors,
    );
  }

  static g.SnpTcb _toRust(p.SnpTcb t) => g.SnpTcb(
    bootloader: t.bootloader,
    tee: t.tee,
    snp: t.snp,
    microcode: t.microcode,
  );

  static p.SnpReportInfo _info(g.SnpReportInfo i) => p.SnpReportInfo(
    version: i.version,
    vmpl: i.vmpl,
    reportedTcb: p.SnpTcb(
      bootloader: i.reportedTcb.bootloader,
      tee: i.reportedTcb.tee,
      snp: i.reportedTcb.snp,
      microcode: i.reportedTcb.microcode,
    ),
    measurementHex: i.measurementHex,
    reportDataHex: i.reportDataHex,
    chipIdHex: i.chipIdHex,
  );
}
