import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'attestation_crypto.dart';
import 'codec.dart';

/// A real quote with its collateral for [attestationCryptoContract].
final class QuoteCase {
  /// Creates the case from the probe of 2026-10-14 (see
  /// `test/fixtures/tee/`).
  QuoteCase({
    required this.quote,
    required this.collateral,
    required this.now,
    required this.reportDataHex,
    required this.rtmr3Hex,
  });

  /// The quote.
  final Uint8List quote;

  /// Its collateral.
  final QuoteCollateral collateral;

  /// A time at which the collateral is valid.
  final DateTime now;

  /// Expected `report_data` of the verified quote (128 hex characters).
  final String reportDataHex;

  /// Expected RTMR3 (96 hex characters).
  final String rtmr3Hex;
}

/// A DER certificate with the expected SPKI hash.
final class SpkiCase {
  /// Creates the case.
  SpkiCase(this.certificateDer, this.spkiSha256Hex);

  /// X.509 certificate, DER.
  final Uint8List certificateDer;

  /// `sha256(SubjectPublicKeyInfo)` as hex (as `openssl` computes it).
  final String spkiSha256Hex;
}

/// Contract suite for every [AttestationCrypto] (the Rust implementation of
/// WP47 and the fake). [quoteCase] enables the quote tests; set
/// [verifiesQuoteSignatures] to `false` for implementations that do not
/// check the signature chain (the fake), which skips the negative cases.
void attestationCryptoContract(
  FutureOr<AttestationCrypto> Function() create, {
  String name = 'AttestationCrypto',
  QuoteCase? quoteCase,
  SpkiCase? spkiCase,
  bool verifiesQuoteSignatures = true,
}) {
  Uint8List bytes(String hex) => AttestCodec.unhex(hex);
  Uint8List text(String s) => Uint8List.fromList(s.codeUnits);

  group('$name erfüllt AttestationCrypto-Vertrag', () {
    test('sha256 und sha384: bekannte Vektoren', () async {
      final c = await create();
      expect(
        AttestCodec.hex(c.sha256(text('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        AttestCodec.hex(c.sha384(text('abc'))),
        'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed'
        '8086072ba1e7cc2358baeca134c825a7',
      );
    });

    test('Ed25519 (RFC 8032): gültig, manipuliert, ungültige Längen', () async {
      final c = await create();
      final pk = bytes(
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
      );
      final sig = bytes(
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      );
      final msg = bytes('72');
      expect(c.verifyEd25519(pk, msg, sig), isTrue);
      expect(c.verifyEd25519(pk, bytes('73'), sig), isFalse);
      final flipped = Uint8List.fromList(sig)..[10] ^= 1;
      expect(c.verifyEd25519(pk, msg, flipped), isFalse);
      expect(c.verifyEd25519(pk, msg, sig.sublist(0, 63)), isFalse);
      expect(c.verifyEd25519(pk.sublist(0, 31), msg, sig), isFalse);
    });

    if (spkiCase != null) {
      test('spkiSha256 passt zu openssl; Müll wirft FormatException', () async {
        final c = await create();
        expect(
          AttestCodec.hex(c.spkiSha256(spkiCase.certificateDer)),
          spkiCase.spkiSha256Hex,
        );
        expect(
          () => c.spkiSha256(Uint8List.fromList([1, 2, 3])),
          throwsFormatException,
        );
      });
    }

    if (quoteCase != null) {
      _quoteTests(create, quoteCase, verifiesQuoteSignatures);
    }
  });
}

void _quoteTests(
  FutureOr<AttestationCrypto> Function() create,
  QuoteCase quoteCase,
  bool verifiesQuoteSignatures,
) {
  test('verifyQuote: Report-Felder des echten Quotes', () async {
    final c = await create();
    final v = await c.verifyQuote(
      quoteCase.quote,
      quoteCase.collateral,
      quoteCase.now,
    );
    expect(AttestCodec.hex(v.reportData), quoteCase.reportDataHex);
    expect(AttestCodec.hex(v.rtmr3), quoteCase.rtmr3Hex);
  });

  if (verifiesQuoteSignatures) {
    test('verifyQuote: manipuliertes Quote wird abgelehnt', () async {
      final c = await create();
      final bad = Uint8List.fromList(quoteCase.quote);
      // Offset 568 = 48 (Header) + 520: erstes Byte von report_data im signierten
      // TD-Report-Body. (Die letzten 70 Byte des Fixture-Quotes sind Nullbyte-Auffüllung
      // hinter den Signaturdaten und werden nicht ausgewertet, siehe ADR 0017.)
      bad[48 + 520] ^= 1;
      await expectLater(
        c.verifyQuote(bad, quoteCase.collateral, quoteCase.now),
        throwsA(isA<QuoteVerificationException>()),
      );
    });

    test('verifyQuote: abgelaufenes Kollateral wird abgelehnt', () async {
      final c = await create();
      await expectLater(
        c.verifyQuote(
          quoteCase.quote,
          quoteCase.collateral,
          quoteCase.now.add(const Duration(days: 400)),
        ),
        throwsA(isA<QuoteVerificationException>()),
      );
    });
  }
}
