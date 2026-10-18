import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/attest/generated/snp.dart' as g;
import 'package:wendelin/platform/attest/rust_snp_crypto.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../support/fake_attest_backend.dart';

void main() {
  const tcb = SnpTcb(bootloader: 9, tee: 1, snp: 22, microcode: 80);

  Future<SnpVerdict> run(RustSnpCrypto c) => c.verify(
    report: Uint8List(1),
    vcekDer: Uint8List(1),
    chainPem: '',
    now: DateTime.utc(2026, 10, 18, 12),
    policy: const SnpPolicy(minTcb: tcb),
    tlsSpkiSha256: Uint8List(32),
    hpkeKey: Uint8List(32),
  );

  test('verify maps policy and time to Rust and the verdict back', () async {
    final b = FakeAttestBackend();
    final v = await run(RustSnpCrypto(b));
    expect(v.allOk, isTrue);
    expect(v.product, 'Genoa');
    expect(b.lastSnpNow, 1792324800);
    expect(b.lastSnpPolicy!.minTcb.bootloader, 9);
    expect(b.lastSnpPolicy!.minTcb.tee, 1);
    expect(b.lastSnpPolicy!.minTcb.snp, 22);
    expect(b.lastSnpPolicy!.minTcb.microcode, 80);
  });

  test('red stages and info carry through', () async {
    final b = FakeAttestBackend()
      ..snpVerdict = g.SnpVerdict(
        reportOk: true,
        chainOk: false,
        vcekMatchesReport: true,
        signatureOk: true,
        policyOk: false,
        tlsBound: true,
        hpkeBound: false,
        errors: const ['Kette: x'],
        info: FakeAttestBackend().snpInfo,
      );
    final v = await run(RustSnpCrypto(b));
    expect(v.allOk, isFalse);
    expect(v.chainOk, isFalse);
    expect(v.policyOk, isFalse);
    expect(v.hpkeBound, isFalse);
    expect(v.errors, ['Kette: x']);
    expect(v.info!.reportedTcb.microcode, 84);
  });

  test('reportInfo converts and a Rust panic becomes a red verdict', () async {
    final b = FakeAttestBackend();
    final c = RustSnpCrypto(b);
    final i = c.reportInfo(Uint8List(1));
    expect(i.version, 3);
    expect(i.chipIdHex, 'cc');
    b.panic = StateError('boom');
    final v = await run(c);
    expect(v.allOk, isFalse);
    expect(v.errors.single, 'Prüfmodul: StateError');
    expect(v.errors.single, isNot(contains('boom')));
  });
}
