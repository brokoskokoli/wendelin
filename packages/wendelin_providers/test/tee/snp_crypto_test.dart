import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  const tcb = SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 84);

  test('SnpTcb compares by component and prints dotted', () {
    expect(tcb, const SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 84));
    expect(
      tcb,
      isNot(const SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 85)),
    );
    expect(tcb.hashCode, tcb.hashCode);
    expect(tcb.toString(), '10.0.23.84');
  });

  test('allOk needs every stage and no errors', () async {
    final fake = FakeSnpCrypto();
    final ok = await fake.verify(
      report: Uint8List(1),
      vcekDer: Uint8List(1),
      chainPem: '',
      now: DateTime.utc(2026, 10, 18),
      policy: const SnpPolicy(minTcb: tcb),
      tlsSpkiSha256: Uint8List(32),
      hpkeKey: Uint8List(32),
    );
    expect(ok.allOk, isTrue);
    expect(ok.product, 'Genoa');
    expect(fake.verifies, 1);
    expect(fake.lastPolicy!.minTcb, tcb);
    expect(fake.lastNow, DateTime.utc(2026, 10, 18));

    SnpVerdict with_({
      bool report = true,
      bool chain = true,
      bool vcek = true,
      bool sig = true,
      bool policy = true,
      bool tls = true,
      bool hpke = true,
      List<String> errors = const [],
    }) => SnpVerdict(
      reportOk: report,
      chainOk: chain,
      vcekMatchesReport: vcek,
      signatureOk: sig,
      policyOk: policy,
      tlsBound: tls,
      hpkeBound: hpke,
      errors: errors,
    );
    expect(with_().allOk, isTrue);
    for (final v in [
      with_(report: false),
      with_(chain: false),
      with_(vcek: false),
      with_(sig: false),
      with_(policy: false),
      with_(tls: false),
      with_(hpke: false),
      with_(errors: ['x']),
    ]) {
      expect(v.allOk, isFalse);
    }
  });

  test('fake reportInfo answers and rejects empty input', () {
    final fake = FakeSnpCrypto();
    expect(fake.reportInfo(Uint8List(1)).reportedTcb, tcb);
    expect(() => fake.reportInfo(Uint8List(0)), throwsArgumentError);
  });
}
