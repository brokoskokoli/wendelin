import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'attestation_crypto.dart';
import 'codec.dart';

/// Request AAD of the published test vector (`spec/e2ee-v2-test-vectors.md`).
const e2eeFrozenAad =
    '{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"messages.0.content",'
    '"model":"demo-model","nonce":"000102030405060708090a0b0c0d0e0f1011121314'
    '15161718191a1b1c1d1e1f","purpose":"aci.e2ee.request.v2","ts":1750000000}';

/// Ciphertext of "Hallo Wendelin" under [e2eeFrozenAad] for the service key
/// of seed 32 x 0x03, made with Node.js `crypto` (independent of Rust).
const e2eeFrozenWire =
    '13be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d'
    '090909090909090909090909'
    '1e69f266bbbdd6899f377027147350819b3b31b348825eba8685be0c516c';

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

    test('E2EE: Rundlauf, AAD-Bindung und Fehlerfälle', () async {
      final c = await create();
      final service = c.e2eeGenerateKeypair();
      expect(service.public, hasLength(32));
      expect(service.secret, hasLength(32));
      final aad = text('{"field":"messages.0.content"}');
      for (final plain in ['', 'Hallo Wörld', 'x' * 300]) {
        final data = Uint8List.fromList(utf8.encode(plain));
        final wire = c.e2eeEncrypt(service.public, data, aad);
        expect(wire, matches(RegExp(r'^[0-9a-f]+$')));
        expect(wire.length, 2 * (60 + data.length));
        expect(c.e2eeDecrypt(service.secret, wire, aad), data);
        expect(c.e2eeDecrypt(service.secret, '0x$wire', aad), data);
      }
      final one = c.e2eeEncrypt(service.public, text('a'), aad);
      expect(c.e2eeEncrypt(service.public, text('a'), aad), isNot(one));
      throwsE2ee(void Function() f) =>
          expect(f, throwsA(isA<E2eeCryptoException>()));
      throwsE2ee(() => c.e2eeDecrypt(service.secret, one, text('andere AAD')));
      throwsE2ee(() => c.e2eeDecrypt(c.e2eeGenerateKeypair().secret, one, aad));
      final flipped =
          '${one.substring(0, one.length - 1)}'
          '${one.endsWith('0') ? '1' : '0'}';
      throwsE2ee(() => c.e2eeDecrypt(service.secret, flipped, aad));
      throwsE2ee(() => c.e2eeDecrypt(service.secret, 'zz', aad));
      throwsE2ee(() => c.e2eeDecrypt(service.secret, 'abcd', aad));
      throwsE2ee(() => c.e2eeEncrypt(Uint8List(32), text('x'), aad));
      throwsE2ee(() => c.e2eeEncrypt(Uint8List(5), text('x'), aad));
    });

    test(
      'E2EE: eingefrorener Vektor einer unabhängigen Implementierung',
      () async {
        // Node.js crypto: Service-Seed 32 x 0x03, Ephemeral-Seed 32 x 0x07,
        // GCM-Nonce 12 x 0x09, AAD = Request-AAD des Spec-Vektors.
        final c = await create();
        final plain = c.e2eeDecrypt(
          Uint8List.fromList(List.filled(32, 3)),
          e2eeFrozenWire,
          text(e2eeFrozenAad),
        );
        expect(utf8.decode(plain), 'Hallo Wendelin');
      },
    );

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
