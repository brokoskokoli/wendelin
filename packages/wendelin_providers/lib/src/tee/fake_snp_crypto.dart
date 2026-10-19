import 'dart:typed_data';

import 'snp_crypto.dart';

/// [SnpCrypto] for tests: returns the configured [verdict] and records the
/// last call.
final class FakeSnpCrypto implements SnpCrypto {
  /// Creates the fake; by default every stage is green.
  FakeSnpCrypto({SnpVerdict? verdict, SnpReportInfo? info})
    : verdict = verdict ?? _green,
      info = info ?? _info;

  /// Answer of [verify].
  SnpVerdict verdict;

  /// Answer of [reportInfo].
  SnpReportInfo info;

  /// Number of [verify] calls.
  int verifies = 0;

  /// Policy of the last [verify] call.
  SnpPolicy? lastPolicy;

  /// Expected TLS hash of the last [verify] call.
  Uint8List? lastTls;

  /// Time of the last [verify] call.
  DateTime? lastNow;

  static const _tcb = SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 84);
  static const _info = SnpReportInfo(
    version: 3,
    vmpl: 0,
    reportedTcb: _tcb,
    measurementHex: '00',
    reportDataHex: '00',
    chipIdHex: '00',
  );
  static const _green = SnpVerdict(
    reportOk: true,
    chainOk: true,
    vcekMatchesReport: true,
    signatureOk: true,
    policyOk: true,
    tlsBound: true,
    hpkeBound: true,
    product: 'Genoa',
    info: _info,
  );

  @override
  SnpReportInfo reportInfo(Uint8List report) {
    if (report.isEmpty) throw ArgumentError('Report leer');
    return info;
  }

  @override
  Future<SnpVerdict> verify({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required DateTime now,
    required SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  }) async {
    verifies++;
    lastPolicy = policy;
    lastTls = tlsSpkiSha256;
    lastNow = now;
    return verdict;
  }
}
