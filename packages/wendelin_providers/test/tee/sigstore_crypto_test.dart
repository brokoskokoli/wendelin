import 'package:test/test.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  test('allOk needs every stage and no errors', () async {
    final fake = FakeSigstoreCrypto();
    final ok = await fake.verifyRelease(
      bundleJson: '{}',
      repo: 'o/r',
      tag: 'v1',
      digestHex: 'ab',
      reportMeasurementHex: 'cd',
    );
    expect(ok.allOk, isTrue);
    expect(fake.verifies, 1);
    expect(fake.last, (
      repo: 'o/r',
      tag: 'v1',
      digestHex: 'ab',
      measurementHex: 'cd',
    ));

    SigstoreVerdict with_({
      bool dsse = true,
      bool chain = true,
      bool identity = true,
      bool rekor = true,
      bool measurement = true,
      List<String> errors = const [],
    }) => SigstoreVerdict(
      dsseOk: dsse,
      chainOk: chain,
      identityOk: identity,
      rekorOk: rekor,
      measurementOk: measurement,
      errors: errors,
    );
    expect(with_().allOk, isTrue);
    expect(with_(dsse: false).allOk, isFalse);
    expect(with_(chain: false).allOk, isFalse);
    expect(with_(identity: false).allOk, isFalse);
    expect(with_(rekor: false).allOk, isFalse);
    expect(with_(measurement: false).allOk, isFalse);
    expect(with_(errors: ['x']).allOk, isFalse);
  });
}
