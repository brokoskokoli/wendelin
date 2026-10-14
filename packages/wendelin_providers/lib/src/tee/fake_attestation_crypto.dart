import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'attestation_crypto.dart';
import 'e2ee_reference.dart';
import 'ed25519_verify.dart';

/// [AttestationCrypto] for tests and demo mode: real hash functions and a
/// real (slow) Ed25519 verification and E2EE ([E2eeReference]), but **no** check of the quote's
/// signature chain: [verifyQuote] only reads the TD report fields of a
/// TDX v4 quote and returns the configured [tcbStatus].
final class FakeAttestationCrypto implements AttestationCrypto {
  /// Creates the fake.
  FakeAttestationCrypto({
    this.tcbStatus = TcbStatus.upToDate,
    this.advisoryIds = const [],
    this.quoteError,
    this.collateralError,
    this.ed25519Result,
  });

  /// TCB status every verified quote gets.
  TcbStatus tcbStatus;

  /// Advisories of the verdict.
  List<String> advisoryIds;

  /// If set, [verifyQuote] throws this.
  QuoteVerificationException? quoteError;

  /// If set, [collateralFor] throws this.
  CollateralUnavailableException? collateralError;

  /// `null` = verify Ed25519 for real; otherwise forced result (to test
  /// receipts that were built in a test and cannot be signed).
  bool? ed25519Result;

  /// Number of [verifyQuote] calls.
  int verifyQuoteCalls = 0;

  /// Number of [collateralFor] calls.
  int collateralCalls = 0;

  static const _header = 48;
  static const _rtmr3 = _header + 472;
  static const _reportData = _header + 520;

  @override
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  ) async {
    verifyQuoteCalls++;
    if (quoteError case final e?) throw e;
    if (quote.length < _reportData + 64) {
      throw const QuoteVerificationException('Quote zu kurz');
    }
    return QuoteVerdict(
      tcbStatus: tcbStatus,
      advisoryIds: advisoryIds,
      reportData: Uint8List.fromList(
        quote.sublist(_reportData, _reportData + 64),
      ),
      rtmr3: Uint8List.fromList(quote.sublist(_rtmr3, _rtmr3 + 48)),
    );
  }

  @override
  Future<QuoteCollateral> collateralFor(Uint8List quote) async {
    collateralCalls++;
    if (collateralError case final e?) throw e;
    return QuoteCollateral(Uint8List(0));
  }

  @override
  bool verifyEd25519(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) => ed25519Result ?? Ed25519Reference.verify(publicKey, message, signature);

  @override
  Uint8List sha256(Uint8List data) =>
      Uint8List.fromList(crypto.sha256.convert(data).bytes);

  @override
  Uint8List sha384(Uint8List data) =>
      Uint8List.fromList(crypto.sha384.convert(data).bytes);

  @override
  E2eeKeypair e2eeGenerateKeypair() => E2eeReference.generateKeypair();

  @override
  String e2eeEncrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad,
  ) => E2eeReference.encrypt(recipientPublic, plaintext, aad);

  @override
  Uint8List e2eeDecrypt(Uint8List secret, String wireHex, Uint8List aad) =>
      E2eeReference.decrypt(secret, wireHex, aad);

  @override
  Uint8List spkiSha256(Uint8List certificateDer) {
    // Certificate ::= SEQUENCE { tbs SEQUENCE { [0] version?, serial,
    // sigAlg, issuer, validity, subject, spki, … }, … }
    final cert = _Tlv.read(certificateDer, 0);
    final tbs = _Tlv.read(certificateDer, cert.valueStart);
    var pos = tbs.valueStart;
    var tlv = _Tlv.read(certificateDer, pos);
    if (tlv.tag == 0xa0) {
      pos = tlv.end;
    }
    for (var i = 0; i < 5; i++) {
      // serial, sigAlg, issuer, validity, subject
      pos = _Tlv.read(certificateDer, pos).end;
    }
    tlv = _Tlv.read(certificateDer, pos);
    return sha256(Uint8List.sublistView(certificateDer, pos, tlv.end));
  }
}

final class _Tlv {
  _Tlv(this.tag, this.valueStart, this.end);

  final int tag;
  final int valueStart;
  final int end;

  static _Tlv read(Uint8List b, int pos) {
    try {
      final tag = b[pos];
      var len = b[pos + 1];
      var start = pos + 2;
      if (len & 0x80 != 0) {
        final n = len & 0x7f;
        len = 0;
        for (var i = 0; i < n; i++) {
          len = (len << 8) | b[start + i];
        }
        start += n;
      }
      if (start + len > b.length) throw const FormatException('DER zu kurz');
      return _Tlv(tag, start, start + len);
    } on RangeError {
      throw const FormatException('DER unlesbar');
    }
  }
}
