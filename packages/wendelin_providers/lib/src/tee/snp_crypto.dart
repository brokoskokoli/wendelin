import 'dart:typed_data';

/// TCB components (one byte each) of an AMD SEV-SNP `reported_tcb`.
final class SnpTcb {
  /// Creates a TCB value.
  const SnpTcb({
    required this.bootloader,
    required this.tee,
    required this.snp,
    required this.microcode,
  });

  /// Boot loader SPL.
  final int bootloader;

  /// TEE SPL.
  final int tee;

  /// SNP firmware SPL.
  final int snp;

  /// Microcode SPL.
  final int microcode;

  @override
  bool operator ==(Object other) =>
      other is SnpTcb &&
      other.bootloader == bootloader &&
      other.tee == tee &&
      other.snp == snp &&
      other.microcode == microcode;

  @override
  int get hashCode => Object.hash(bootloader, tee, snp, microcode);

  @override
  String toString() => '$bootloader.$tee.$snp.$microcode';
}

/// Minimum requirements for an SNP report. Debug guests, VMPL != 0 and
/// non-VCEK signatures are always rejected.
final class SnpPolicy {
  /// Creates a policy.
  const SnpPolicy({required this.minTcb});

  /// Lowest accepted `reported_tcb`, component by component.
  final SnpTcb minTcb;
}

/// Parsed fields of an SNP report (no verification).
final class SnpReportInfo {
  /// Creates the info.
  const SnpReportInfo({
    required this.version,
    required this.vmpl,
    required this.reportedTcb,
    required this.measurementHex,
    required this.reportDataHex,
    required this.chipIdHex,
  });

  /// Report version (2 or 3 today).
  final int version;

  /// Privilege level of the guest that requested the report.
  final int vmpl;

  /// TCB the VCEK was derived for.
  final SnpTcb reportedTcb;

  /// SHA-384 launch measurement, hex.
  final String measurementHex;

  /// The 64 `report_data` bytes, hex.
  final String reportDataHex;

  /// 64-byte chip id, hex (selects the VCEK at the AMD KDS).
  final String chipIdHex;
}

/// Result per stage of the SNP verification; each stage is evaluated on its
/// own, so a red stage never hides the others.
final class SnpVerdict {
  /// Creates a verdict.
  const SnpVerdict({
    required this.reportOk,
    required this.chainOk,
    required this.vcekMatchesReport,
    required this.signatureOk,
    required this.policyOk,
    required this.tlsBound,
    required this.hpkeBound,
    this.product,
    this.info,
    this.errors = const [],
  });

  /// Report layout, version and signature algorithm are readable.
  final bool reportOk;

  /// VCEK -> ASK -> ARK valid at the check time, ARK pinned.
  final bool chainOk;

  /// VCEK belongs to the chip and `reported_tcb` of the report.
  final bool vcekMatchesReport;

  /// ECDSA P-384 signature of the report under the VCEK.
  final bool signatureOk;

  /// No debug, VMPL 0, VCEK-signed, TCB minimum met.
  final bool policyOk;

  /// `report_data[0..32]` equals the expected TLS SPKI hash.
  final bool tlsBound;

  /// `report_data[32..64]` equals the expected HPKE key.
  final bool hpkeBound;

  /// AMD product of the pinned root (`Milan`, `Genoa`, `Turin`).
  final String? product;

  /// Report fields, when readable.
  final SnpReportInfo? info;

  /// Hard failures (German, no key material).
  final List<String> errors;

  /// All stages green and no errors.
  bool get allOk =>
      errors.isEmpty &&
      reportOk &&
      chainOk &&
      vcekMatchesReport &&
      signatureOk &&
      policyOk &&
      tlsBound &&
      hpkeBound;
}

/// AMD SEV-SNP verification of a Tinfoil router report (WP76a). Rust in the
/// app (`native/attest/src/snp.rs`), `FakeSnpCrypto` in tests. VCEK and chain
/// come from the AMD KDS (fetched by the caller); the ARK is pinned in Rust.
abstract interface class SnpCrypto {
  /// Fields of [report] without verification; throws on unreadable input.
  SnpReportInfo reportInfo(Uint8List report);

  /// Verifies [report] against [vcekDer] and [chainPem] (ASK + ARK) at [now]
  /// and binds `report_data` to [tlsSpkiSha256] and [hpkeKey].
  Future<SnpVerdict> verify({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required DateTime now,
    required SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  });
}
