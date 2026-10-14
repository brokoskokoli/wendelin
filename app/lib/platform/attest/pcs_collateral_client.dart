import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'attest_backend.dart';
import 'generated/collateral.dart';

/// Holt das Quote-Kollateral von Intel PCS über den App-HTTP-Client (kein Netz im Rust-Crate).
/// Der Rust-Teil sagt, was zu holen ist (FMSPC, CA, Root-CRL-URL) und setzt die Antworten zusammen.
final class PcsCollateralClient {
  /// Erstellt den Client.
  PcsCollateralClient({
    required this.client,
    required this.backend,
    this.baseUrl = 'https://api.trustedservices.intel.com',
    this.timeout = const Duration(seconds: 20),
  });

  /// HTTP-Client der App.
  final http.Client client;

  /// Rust-Funktionen.
  final AttestBackend backend;

  /// Intel PCS (Wurzel ohne Pfad).
  final String baseUrl;

  /// Zeitlimit je Abruf.
  final Duration timeout;

  /// Abruf des Kollaterals zu [quote] als `QuoteCollateralV3`-JSON.
  Future<String> fetch(Uint8List quote) async {
    final req = await backend.collateralRequest(quote);
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final pckCrl = await _get(
      '$base/sgx/certification/v4/pckcrl?ca=${req.ca}&encoding=der',
    );
    final tcb = await _get(
      '$base/${req.tee}/certification/v4/tcb?fmspc=${req.fmspc}&update=standard',
    );
    final qe = await _get(
      '$base/${req.tee}/certification/v4/qe/identity?update=standard',
    );
    final qeChain = _header(qe, 'sgx-enclave-identity-issuer-chain');
    final rootCrl = await _get(await backend.rootCrlUrl(qeChain));
    return backend.buildCollateral(
      CollateralParts(
        pckCrl: pckCrl.bodyBytes,
        pckCrlIssuerChain: _header(pckCrl, 'sgx-pck-crl-issuer-chain'),
        rootCaCrl: rootCrl.bodyBytes,
        tcbInfoBody: tcb.body,
        tcbInfoIssuerChain: _header(
          tcb,
          'sgx-tcb-info-issuer-chain',
          alt: 'tcb-info-issuer-chain',
        ),
        qeIdentityBody: qe.body,
        qeIdentityIssuerChain: qeChain,
      ),
    );
  }

  Future<http.Response> _get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PcsException(
        'Kollateral-Abruf fehlgeschlagen: HTTP ${r.statusCode} (${Uri.parse(url).path})',
      );
    }
    return r;
  }

  String _header(http.Response r, String name, {String? alt}) {
    final v = r.headers[name] ?? (alt == null ? null : r.headers[alt]);
    if (v == null) throw PcsException('Kollateral-Antwort ohne Header $name');
    return Uri.decodeComponent(v);
  }
}

/// Kollateral konnte nicht beschafft werden (Netz, HTTP-Status, fehlende Header).
final class PcsException implements Exception {
  /// Erstellt die Ausnahme.
  const PcsException(this.message);

  /// Beschreibung ohne Nutzdaten.
  final String message;

  @override
  String toString() => 'PcsException: $message';
}
