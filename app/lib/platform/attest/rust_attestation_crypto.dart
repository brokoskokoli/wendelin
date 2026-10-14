import 'dart:convert';
import 'dart:typed_data';

import 'attest_backend.dart';
import 'attestation_port.dart';
import 'collateral_cache.dart';
import 'generated/collateral.dart';
import 'generated/quote.dart';
import 'pcs_collateral_client.dart';

/// `AttestationCrypto` über das Rust-Modul `native/attest` (WP47). Kollateral kommt aus dem Dateicache
/// (bis `nextUpdate`) oder von Intel PCS; ab weniger als [renewBefore] Restlaufzeit wird erneuert,
/// bei Netzfehler gilt der noch gültige Cache weiter.
final class RustAttestationCrypto implements AttestationCrypto {
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
  ) => backend.ed25519(publicKey, message, signature);

  @override
  Uint8List sha256(Uint8List data) => backend.sha256(data);

  @override
  Uint8List sha384(Uint8List data) => backend.sha384(data);

  @override
  Uint8List spkiSha256(Uint8List certificateDer) {
    try {
      return backend.spkiSha256(certificateDer);
    } on Object {
      throw const FormatException('Zertifikat nicht lesbar');
    }
  }
}
