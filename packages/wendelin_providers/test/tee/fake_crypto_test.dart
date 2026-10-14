import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tee_support.dart';

// Self-signed EC certificate (public data, the key was discarded) and the
// SPKI hash `openssl x509 -pubkey | openssl pkey -pubin -outform der |
// openssl dgst -sha256` computed.
const _certHex =
    '3082016d30820114a0030201020214588a3cc3013fcfaefa6f2085a5ebfd542765e802300a06082a8648ce3d040302301c311a301806035504030c1173706b692d746573742e696e76616c69643020170d3236313031343033303231365a180f32313236303932303033303231365a301c311a301806035504030c1173706b692d746573742e696e76616c69643059301306072a8648ce3d020106082a8648ce3d03010703420004c7a88331a6b79c7158dca39d37118b9be3e79257cf693e23f5839e82f1cd4f32750fb31f92844d8356d20cf0cb5f7bd4e3420a1ca778390cbc4fdc91ce5e3451a3323030301d0603551d0e04160414b589b60479222ba48b0d199c547656db9759b49b300f0603551d130101ff040530030101ff300a06082a8648ce3d04030203470030440220255772734d15937c87517609e8096b197510cd968e447dea9b0fd84ba4d22cf90220145dac02b5e03c06dc1986022b5d189008dff6fb358028ad1225d2c3e8aa124f';
const _spkiHex =
    'aa32913c1e44284bdb2f1367e67b95ad6664f07d6bd8a9f9e133fe46e4e3b749';

/// The quote and collateral of the probe for the contract suite.
QuoteCase probeQuoteCase() {
  final doc = teeJson('gateway_attestation');
  final ev = (doc['attestation']! as Map)['evidence']! as Map;
  return QuoteCase(
    quote: AttestCodec.unhex(ev['quote']! as String),
    collateral: QuoteCollateral(
      Uint8List.fromList(
        File('test/fixtures/tee/collateral_pcs.json').readAsBytesSync(),
      ),
    ),
    now: probeNow,
    reportDataHex: ev['quote_report_data']! as String,
    rtmr3Hex: _rtmr3Hex(doc),
  );
}

String _rtmr3Hex(Map<String, Object?> doc) {
  // RTMR3 as the fake reads it from the quote: offset 48 + 472.
  final ev = (doc['attestation']! as Map)['evidence']! as Map;
  final q = AttestCodec.unhex(ev['quote']! as String);
  return AttestCodec.hex(q.sublist(48 + 472, 48 + 472 + 48));
}

void main() {
  attestationCryptoContract(
    FakeAttestationCrypto.new,
    name: 'FakeAttestationCrypto',
    quoteCase: probeQuoteCase(),
    spkiCase: SpkiCase(AttestCodec.unhex(_certHex), _spkiHex),
    verifiesQuoteSignatures: false,
  );

  test('Fake: Aufrufzähler und Fehler konfigurierbar', () async {
    final c = FakeAttestationCrypto(
      collateralError: const CollateralUnavailableException('x'),
    );
    await expectLater(
      c.collateralFor(Uint8List(0)),
      throwsA(isA<CollateralUnavailableException>()),
    );
    expect(c.collateralCalls, 1);
    await expectLater(
      FakeAttestationCrypto().verifyQuote(
        Uint8List(10),
        QuoteCollateral(Uint8List(0)),
        probeNow,
      ),
      throwsA(isA<QuoteVerificationException>()),
    );
  });
}
