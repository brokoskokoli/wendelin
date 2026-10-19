import '../snp_crypto.dart';

/// Fixed decisions of the Tinfoil attestation (ADR 0020).
abstract final class TinfoilPolicy {
  /// Repository whose signed release the router measurement must belong to.
  static const repo = 'tinfoilsh/confidential-model-router';

  /// Lowest accepted `reported_tcb`: set one step below the recording
  /// (bootloader 10, SNP 23, microcode 84) on purpose, so a firmware
  /// update of AMD does not lock the user out while a rollback to a
  /// vulnerable firmware is refused. TEE SPL is not constrained (0).
  static const minTcb = SnpTcb(bootloader: 9, tee: 0, snp: 22, microcode: 80);

  /// [minTcb] as the policy of `SnpCrypto.verify`.
  static const snpPolicy = SnpPolicy(minTcb: minTcb);

  /// AMD products whose ARK is pinned and whose TCB layout is supported
  /// (Turin follows, WP76 notes), in the order they are tried.
  static const products = ['Genoa', 'Milan'];

  /// Document format of `/.well-known/tinfoil-attestation`.
  static const attestationFormat =
      'https://tinfoil.sh/predicate/sev-snp-guest/v2';

  /// Largest accepted SNP report (v3 is 1184 bytes).
  static const maxReportBytes = 4096;
}
