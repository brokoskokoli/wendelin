import 'dart:typed_data';

import 'generated/api.dart' as api;
import 'generated/collateral.dart';
import 'generated/e2ee.dart';
import 'generated/frb_generated.dart';
import 'generated/quote.dart';
import 'generated/report.dart';

/// Die Rust-Funktionen aus `native/attest`, als Schnittstelle für Tests ohne native Bibliothek.
abstract interface class AttestBackend {
  /// FMSPC, CA und TEE-Art eines Quotes.
  Future<CollateralRequest> collateralRequest(Uint8List quote);

  /// URL der Root-CA-CRL.
  Future<String> rootCrlUrl(String qeIdentityIssuerChain);

  /// Setzt PCS-Antworten zu Kollateral-JSON zusammen.
  Future<String> buildCollateral(CollateralParts parts);

  /// Frühestes `nextUpdate` (ISO-8601).
  Future<String> nextUpdate(String collateralJson);

  /// Prüft einen Quote.
  Future<QuoteInfo> verifyQuote(
    Uint8List quote,
    String collateralJson,
    int nowUnix,
  );

  /// Prüft einen ACI-Bericht vollständig.
  Future<Verdict> verifyReport(
    String reportJson,
    String nonceHex,
    String collateralJson,
    int nowUnix,
  );

  /// Prüft die Signatur einer Quittung.
  Future<ReceiptVerdict> verifyReceipt(String receiptJson, String reportJson);

  /// Ed25519.
  bool ed25519(Uint8List pk, Uint8List msg, Uint8List sig);

  /// SHA-256.
  Uint8List sha256(Uint8List data);

  /// SHA-384.
  Uint8List sha384(Uint8List data);

  /// SPKI-Hash eines Zertifikats.
  Uint8List spkiSha256(Uint8List der);

  /// Frisches X25519-Paar (E2EE).
  E2eeKeypair e2eeGenerateKeypair();

  /// Feldverschlüsselung (Hex-Wire-Format); wirft bei Fehlern.
  String e2eeEncrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad,
  );

  /// Feldentschlüsselung; wirft bei Fehlern.
  Uint8List e2eeDecrypt(Uint8List secret, String wireHex, Uint8List aad);
}

/// Echte Anbindung über `flutter_rust_bridge`; [init] lädt `libwendelin_attest.so`.
final class FrbAttestBackend implements AttestBackend {
  FrbAttestBackend._();

  static FrbAttestBackend? _instance;

  /// Lädt die native Bibliothek einmalig und liefert das Backend.
  static Future<FrbAttestBackend> init() async {
    if (_instance case final i?) return i;
    await AttestNative.init();
    return _instance = FrbAttestBackend._();
  }

  @override
  Future<CollateralRequest> collateralRequest(Uint8List quote) =>
      api.collateralRequest(quote: quote);

  @override
  Future<String> rootCrlUrl(String chain) =>
      api.rootCrlUrl(qeIdentityIssuerChain: chain);

  @override
  Future<String> buildCollateral(CollateralParts parts) =>
      api.buildCollateral(parts: parts);

  @override
  Future<String> nextUpdate(String json) =>
      api.collateralNextUpdate(collateralJson: json);

  @override
  Future<QuoteInfo> verifyQuote(Uint8List quote, String json, int nowUnix) =>
      api.verifyQuote(
        quote: quote,
        collateralJson: json,
        nowUnix: BigInt.from(nowUnix),
      );

  @override
  Future<Verdict> verifyReport(
    String report,
    String nonce,
    String json,
    int nowUnix,
  ) => api.verifyAciReport(
    reportJson: report,
    nonceHex: nonce,
    collateralJson: json,
    nowUnix: BigInt.from(nowUnix),
  );

  @override
  Future<ReceiptVerdict> verifyReceipt(String receipt, String report) =>
      api.verifyAciReceipt(receiptJson: receipt, reportJson: report);

  @override
  bool ed25519(Uint8List pk, Uint8List msg, Uint8List sig) =>
      api.verifyEd25519(publicKey: pk, message: msg, signature: sig);

  @override
  Uint8List sha256(Uint8List data) => api.sha256(data: data);

  @override
  Uint8List sha384(Uint8List data) => api.sha384(data: data);

  @override
  Uint8List spkiSha256(Uint8List der) => api.spkiSha256(certificateDer: der);

  @override
  E2eeKeypair e2eeGenerateKeypair() => api.e2EeGenerateKeypair();

  @override
  String e2eeEncrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad,
  ) => api.e2EeEncrypt(
    recipientPublic: recipientPublic,
    plaintext: plaintext,
    aad: aad,
  );

  @override
  Uint8List e2eeDecrypt(Uint8List secret, String wireHex, Uint8List aad) =>
      api.e2EeDecrypt(secret: secret, wireHex: wireHex, aad: aad);
}
