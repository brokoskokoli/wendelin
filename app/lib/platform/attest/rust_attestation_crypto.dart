import 'dart:convert';
import 'dart:typed_data';

import 'package:wendelin_providers/wendelin_providers.dart';

import 'attest_backend.dart';
import 'collateral_cache.dart';
import 'generated/collateral.dart';
import 'generated/quote.dart';
import 'pcs_collateral_client.dart';

/// `AttestationCrypto` über das Rust-Modul `native/attest` (WP47). Kollateral kommt aus dem Dateicache
/// (bis `nextUpdate`) oder von Intel PCS; ab weniger als [renewBefore] Restlaufzeit wird erneuert,
/// bei Netzfehler gilt der noch gültige Cache weiter.
final class RustAttestationCrypto implements AttestationCrypto, NearCrypto {
  /// Erstellt die Implementierung.
  RustAttestationCrypto({
    required this.backend,
    required this.pcs,
    required this.cache,
    required this.clock,
    this.renewBefore = const Duration(days: 3),
  });

  /// Rust-Funktionen.
  final AttestBackend backend;

  /// Abruf bei Intel PCS.
  final PcsCollateralClient pcs;

  /// Dateicache.
  final CollateralCache cache;

  /// Uhr (UTC-fähig).
  final DateTime Function() clock;

  /// Restlaufzeit, ab der erneuert wird.
  final Duration renewBefore;

  @override
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  ) async {
    final QuoteInfo r;
    try {
      r = await backend.verifyQuote(
        quote,
        utf8.decode(collateral.json),
        now.toUtc().millisecondsSinceEpoch ~/ 1000,
      );
    } on Object catch (e) {
      throw QuoteVerificationException('Prüfmodul: ${e.runtimeType}');
    }
    if (!r.ok) throw QuoteVerificationException(r.error ?? 'Quote ungültig');
    return QuoteVerdict(
      tcbStatus: _tcb(r.tcbStatus),
      reportData: r.reportData,
      rtmr3: r.rtMr3,
      advisoryIds: r.advisoryIds,
    );
  }

  static TcbStatus _tcb(String s) => switch (s) {
    'UpToDate' => TcbStatus.upToDate,
    'SWHardeningNeeded' => TcbStatus.swHardeningNeeded,
    'ConfigurationNeeded' => TcbStatus.configurationNeeded,
    'ConfigurationAndSWHardeningNeeded' =>
      TcbStatus.configurationAndSwHardeningNeeded,
    'OutOfDate' => TcbStatus.outOfDate,
    'OutOfDateConfigurationNeeded' => TcbStatus.outOfDateConfigurationNeeded,
    'Revoked' => TcbStatus.revoked,
    // Intel empfiehlt einen Neustart der TEE (neuer TCB-Stand verfügbar): rot mit eigenem Grund.
    'TDRelaunchAdvised' => TcbStatus.relaunchAdvised,
    'TDRelaunchAdvisedConfigurationNeeded' =>
      TcbStatus.relaunchAdvisedConfigurationNeeded,
    _ => throw QuoteVerificationException('unbekannter TCB-Status: $s'),
  };

  @override
  Future<QuoteCollateral> collateralFor(Uint8List quote) async {
    try {
      final CollateralRequest req = await backend.collateralRequest(quote);
      final key = '${req.tee}-${req.fmspc}-${req.ca}';
      final cached = cache.read(key);
      if (cached != null &&
          cached.validUntil!.difference(clock()) > renewBefore) {
        return cached;
      }
      try {
        final json = await pcs.fetch(quote);
        final fresh = QuoteCollateral(
          Uint8List.fromList(utf8.encode(json)),
          validUntil: DateTime.parse(await backend.nextUpdate(json)),
        );
        cache.write(key, fresh);
        return fresh;
      } on Object {
        if (cached != null) return cached;
        rethrow;
      }
    } on Object catch (e) {
      throw CollateralUnavailableException(
        e is PcsException ? e.message : 'Kollateral: ${e.runtimeType}',
      );
    }
  }

  @override
  bool verifyEd25519(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) => _sync(() => backend.ed25519(publicKey, message, signature));

  @override
  Uint8List sha256(Uint8List data) => _sync(() => backend.sha256(data));

  @override
  Uint8List sha384(Uint8List data) => _sync(() => backend.sha384(data));

  /// Ein Panic im Rust-Modul (`PanicException`) wird zum Prüffehler, nicht zum Absturz.
  static T _sync<T>(T Function() call) {
    try {
      return call();
    } on Object catch (e) {
      throw QuoteVerificationException('Prüfmodul: ${e.runtimeType}');
    }
  }

  @override
  Uint8List spkiSha256(Uint8List certificateDer) {
    try {
      return backend.spkiSha256(certificateDer);
    } on Object {
      throw const FormatException('Zertifikat nicht lesbar');
    }
  }

  @override
  E2eeKeypair e2eeGenerateKeypair() {
    try {
      final pair = backend.e2eeGenerateKeypair();
      return E2eeKeypair(secret: pair.secret, public: pair.public);
    } on Object {
      throw const E2eeCryptoException('Schlüsselerzeugung fehlgeschlagen');
    }
  }

  @override
  String e2eeEncrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad,
  ) {
    try {
      return backend.e2eeEncrypt(recipientPublic, plaintext, aad);
    } on Object {
      // No details of the Rust error: it must not carry key material.
      throw const E2eeCryptoException('Verschlüsselung fehlgeschlagen');
    }
  }

  @override
  Uint8List e2eeDecrypt(Uint8List secret, String wireHex, Uint8List aad) {
    try {
      return backend.e2eeDecrypt(secret, wireHex, aad);
    } on Object {
      throw const E2eeCryptoException('Entschlüsselung fehlgeschlagen');
    }
  }

  // --- NEAR AI (WP75) -----------------------------------------------------

  @override
  NearIdentity nearGenerateIdentity() {
    try {
      final id = backend.nearGenerateIdentity();
      return NearIdentity(secret: id.secret, public: id.public);
    } on Object {
      throw const E2eeCryptoException('Schlüsselerzeugung fehlgeschlagen');
    }
  }

  @override
  String nearEncrypt(Uint8List recipientEd25519, Uint8List plaintext) {
    try {
      return backend.nearEncrypt(recipientEd25519, plaintext);
    } on Object {
      // No details of the Rust error: it must not carry key material.
      throw const E2eeCryptoException('Verschlüsselung fehlgeschlagen');
    }
  }

  @override
  Uint8List nearDecrypt(Uint8List secret, String wireHex) {
    try {
      return backend.nearDecrypt(secret, wireHex);
    } on Object {
      throw const E2eeCryptoException('Entschlüsselung fehlgeschlagen');
    }
  }
}
