import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tee_gateway.dart';

/// Rust check module, but the receipt's Ed25519 signature counts as valid
/// (the recorded receipts are rebuilt with the real hashes, see above) and
/// the E2EE key of the recording (whose secret nobody has) is swapped for the
/// fixture gateway's key. The cipher itself is the real Rust code.
final class ReceiptSignatureSubstitute implements AttestationCrypto {
  ReceiptSignatureSubstitute(this._rust, this._service);

  final AttestationCrypto _rust;
  final FakeE2eeService _service;

  @override
  E2eeKeypair e2eeGenerateKeypair() => _rust.e2eeGenerateKeypair();

  @override
  String e2eeEncrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad,
  ) => _rust.e2eeEncrypt(
    _hex(recipientPublic) == fixtureServiceKeyHex
        ? _service.key.public
        : recipientPublic,
    plaintext,
    aad,
  );

  @override
  Uint8List e2eeDecrypt(Uint8List secret, String wireHex, Uint8List aad) =>
      _rust.e2eeDecrypt(secret, wireHex, aad);

  @override
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  ) => _rust.verifyQuote(quote, collateral, now);

  @override
  Future<QuoteCollateral> collateralFor(Uint8List quote) =>
      _rust.collateralFor(quote);

  @override
  bool verifyEd25519(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) => true;

  @override
  Uint8List sha256(Uint8List data) => _rust.sha256(data);

  @override
  Uint8List sha384(Uint8List data) => _rust.sha384(data);

  @override
  Uint8List spkiSha256(Uint8List certificateDer) {
    // The recording's gateway certificate no longer exists; its stand-in
    // maps to the recorded pin, every other certificate is hashed for real.
    if (listEquals(certificateDer, fixtureGatewayCertificate)) {
      return Uint8List.fromList([
        for (var i = 0; i < fixtureGatewayPin.length; i += 2)
          int.parse(fixtureGatewayPin.substring(i, i + 2), radix: 16),
      ]);
    }
    return _rust.spkiSha256(certificateDer);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
