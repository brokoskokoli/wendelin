import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/attest/generated/sigstore.dart' as g;
import 'package:wendelin/platform/attest/rust_sigstore_crypto.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../support/fake_attest_backend.dart';

void main() {
  Future<SigstoreVerdict> run(RustSigstoreCrypto c) => c.verifyRelease(
    bundleJson: '{}',
    repo: 'o/r',
    tag: 'v1',
    digestHex: 'ab',
    reportMeasurementHex: 'cd',
  );

  test(
    'verifyRelease passes the arguments and maps the verdict back',
    () async {
      final b = FakeAttestBackend();
      final v = await run(RustSigstoreCrypto(b));
      expect(v.allOk, isTrue);
      expect(b.lastRelease, ('o/r', 'v1', 'ab', 'cd'));
      expect(v.releaseTag, 'v1');
      expect(v.integratedTime, 1792024828);
    },
  );

  test('red stages carry through', () async {
    final b = FakeAttestBackend()
      ..sigstoreVerdict = g.SigstoreVerdict(
        dsseOk: true,
        chainOk: true,
        identityOk: false,
        rekorOk: true,
        measurementOk: false,
        snpMeasurementHex: 'ee',
        releaseTag: '',
        integratedTime: BigInt.zero,
        errors: const ['identity: x'],
      );
    final v = await run(RustSigstoreCrypto(b));
    expect(v.allOk, isFalse);
    expect(v.identityOk, isFalse);
    expect(v.measurementOk, isFalse);
    expect(v.snpMeasurementHex, 'ee');
    expect(v.errors, ['identity: x']);
  });

  test('a Rust panic becomes a red verdict without details', () async {
    final b = FakeAttestBackend()..panic = StateError('boom');
    final v = await run(RustSigstoreCrypto(b));
    expect(v.allOk, isFalse);
    expect(v.errors.single, 'Prüfmodul: StateError');
    expect(v.errors.single, isNot(contains('boom')));
  });
}
