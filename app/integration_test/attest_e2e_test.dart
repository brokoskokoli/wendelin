// Gerätetest (WP47): Rust-Prüfmodul `native/attest` über flutter_rust_bridge auf dem Emulator,
// mit den echten Probe-Daten aus WP43 (`support/tee_fixtures.g.dart`).
//
// Nur auf dem Emulator, mit explizitem Serial, z. B.:
//   flutter test integration_test/attest_e2e_test.dart -d emulator-5554
// Mit --dart-define=ATTEST_LIVE=true holt ein weiterer Test das Kollateral wirklich von Intel PCS
// (kostenlos, kein Schlüssel).
// Die Prüfzeiten stehen als `attest-verify ...` im Testlog.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'support/tee_fixtures.g.dart';

const _live = bool.fromEnvironment('ATTEST_LIVE');
const _nonce =
    'abababababababababababababababababababababababababababababababab';

/// Prüfzeitpunkt der Fixtures (Kollateral gültig bis 2026-11-12).
final _fixtureCollateral = QuoteCollateral(
  Uint8List.fromList(utf8.encode(collateralPcs)),
  validUntil: DateTime.utc(2026, 11, 12, 22, 38, 12),
);

final _now = DateTime.fromMillisecondsSinceEpoch(
  1791934700 * 1000,
  isUtc: true,
);

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late RustAttestationCrypto crypto;
  late FrbAttestBackend backend;
  late Directory tmp;
  final report = jsonDecode(gatewayAttestation) as Map<String, dynamic>;
  final collateral = jsonDecode(collateralPcs) as Map<String, dynamic>;
  final evidence =
      (report['attestation'] as Map<String, dynamic>)['evidence']
          as Map<String, dynamic>;
  final quote = _bytes(evidence['quote'] as String);

  /// PCS-Attrappe, die Antworten aus dem Fixture-Kollateral baut (Header URL-kodiert).
  MockClient pcsFromFixture() => MockClient((req) async {
    String chain(String k) => Uri.encodeComponent(collateral[k] as String);
    final p = req.url.path;
    if (p.endsWith('/pckcrl')) {
      return http.Response.bytes(
        _bytes(collateral['pck_crl'] as String),
        200,
        headers: {'sgx-pck-crl-issuer-chain': chain('pck_crl_issuer_chain')},
      );
    }
    if (p.endsWith('/tcb')) {
      return http.Response(
        jsonEncode({
          'tcbInfo': jsonDecode(collateral['tcb_info'] as String),
          'signature': collateral['tcb_info_signature'],
        }),
        200,
        headers: {'sgx-tcb-info-issuer-chain': chain('tcb_info_issuer_chain')},
      );
    }
    if (p.endsWith('/qe/identity')) {
      return http.Response(
        jsonEncode({
          'enclaveIdentity': jsonDecode(collateral['qe_identity'] as String),
          'signature': collateral['qe_identity_signature'],
        }),
        200,
        headers: {
          'sgx-enclave-identity-issuer-chain': chain(
            'qe_identity_issuer_chain',
          ),
        },
      );
    }
    if (p.endsWith('.der')) {
      return http.Response.bytes(
        _bytes(collateral['root_ca_crl'] as String),
        200,
      );
    }
    return http.Response('?', 404);
  });

  setUpAll(() async {
    backend = await FrbAttestBackend.init();
    tmp = Directory.systemTemp.createTempSync('attest-e2e');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    crypto = RustAttestationCrypto(
      backend: backend,
      pcs: PcsCollateralClient(client: pcsFromFixture(), backend: backend),
      cache: CollateralCache(
        dir: Directory('${tmp.path}/c${DateTime.now().microsecondsSinceEpoch}'),
        now: () => _now,
      ),
      clock: () => _now,
    );
  });

  // Vertragssuite des Ports (WP46) gegen die echte Rust-Prüfung.
  String hexOf(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  final spkiPem = RegExp(
    r'-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----',
  ).allMatches(collateral['tcb_info_issuer_chain'] as String).last.group(1)!;
  attestationCryptoContract(
    () => crypto,
    name: 'RustAttestationCrypto',
    quoteCase: QuoteCase(
      quote: quote,
      collateral: _fixtureCollateral,
      now: _now,
      reportDataHex: evidence['quote_report_data'] as String,
      rtmr3Hex: hexOf(quote.sublist(48 + 472, 48 + 472 + 48)),
    ),
    spkiCase: SpkiCase(
      base64.decode(spkiPem.replaceAll(RegExp(r'\s'), '')),
      'a0af031289f5d5d4132f9186068a7fc13628633ba235777472e29b6b6c67a49e',
    ),
  );

  test('Fixture-Quote ist grün, TCB UpToDate, report_data gebunden', () async {
    final c = _fixtureCollateral;
    final v = await crypto.verifyQuote(quote, c, _now);
    expect(v.tcbStatus, TcbStatus.upToDate);
    expect(v.reportData, hasLength(64));
    expect(v.rtmr3, hasLength(48));
    expect(v.reportData.sublist(32), everyElement(0));
  });

  test(
    'manipulierte Quote und abgelaufenes Kollateral werden abgelehnt',
    () async {
      final bad = Uint8List.fromList(quote)..[600] ^= 1;
      await expectLater(
        crypto.verifyQuote(bad, _fixtureCollateral, _now),
        throwsA(isA<QuoteVerificationException>()),
      );
      await expectLater(
        crypto.verifyQuote(
          quote,
          _fixtureCollateral,
          DateTime.utc(2026, 11, 13),
        ),
        throwsA(isA<QuoteVerificationException>()),
        reason: 'Kollateral nach nextUpdate abgelaufen',
      );
    },
  );

  test('Kollateral aus (simulierten) PCS-Antworten wird von Rust zusammengesetzt und verifiziert', () async {
    final c = await crypto.collateralFor(quote);
    expect(c.validUntil, DateTime.utc(2026, 11, 12, 22, 38, 12));
    expect(
      (await crypto.verifyQuote(quote, c, _now)).tcbStatus,
      TcbStatus.upToDate,
    );
    // zweiter Aufruf aus dem Dateicache
    expect((await crypto.collateralFor(quote)).json, c.json);
  });

  test('Ed25519 gültig und ungültig (RFC 8032, Test 2)', () {
    final pk = _bytes(
      '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
    );
    final sig = _bytes(
      '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
    );
    expect(crypto.verifyEd25519(pk, Uint8List.fromList([0x72]), sig), isTrue);
    expect(crypto.verifyEd25519(pk, Uint8List.fromList([0x73]), sig), isFalse);
    expect(
      crypto.verifyEd25519(pk, Uint8List.fromList([0x72]), Uint8List(10)),
      isFalse,
    );
  });

  test('SHA-256, SHA-384 und SPKI-Hash eines bekannten Zertifikats (Intel SGX Root CA)', () {
    String hex(Uint8List b) =>
        b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    final abc = Uint8List.fromList(utf8.encode('abc'));
    expect(
      hex(crypto.sha256(abc)),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(hex(crypto.sha384(abc)).substring(0, 16), 'cb00753f45a35e8b');
    final pem = RegExp(
      r'-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----',
    ).allMatches(collateral['tcb_info_issuer_chain'] as String).last.group(1)!;
    final der = base64.decode(pem.replaceAll(RegExp(r'\s'), ''));
    expect(
      hex(crypto.spkiSha256(der)),
      'a0af031289f5d5d4132f9186068a7fc13628633ba235777472e29b6b6c67a49e',
    );
    expect(
      () => crypto.spkiSha256(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });

  test('ACI-Bericht und Quittung vollständig, Prüfzeit gemessen', () async {
    final times = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      final v = await backend.verifyReport(
        gatewayAttestation,
        _nonce,
        collateralPcs,
        _now.millisecondsSinceEpoch ~/ 1000,
      );
      sw.stop();
      times.add(sw.elapsedMicroseconds);
      expect(v.errors, isEmpty);
      expect([
        v.keysetDigestOk,
        v.reportDataOk,
        v.quoteReportDataOk,
        v.quoteOk,
        v.rtmr3ReplayOk,
        v.composeHashOk,
        v.keysetNotExpired,
        v.tlsBindingListed,
      ], everyElement(isTrue));
    }
    final qs = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      await crypto.verifyQuote(quote, _fixtureCollateral, _now);
      qs.add((sw..stop()).elapsedMicroseconds);
    }
    times.sort();
    qs.sort();
    // ignore: avoid_print
    print(
      'attest-verify report_ms_median=${times[5] / 1000} report_ms_max=${times.last / 1000} '
      'quote_ms_median=${qs[5] / 1000} quote_ms_max=${qs.last / 1000} abi=${defaultTargetPlatform.name}',
    );
    final r = await backend.verifyReceipt(receipt, gatewayAttestation);
    expect(r.signatureOk && r.keysetMatches, isTrue);
    final bad = await backend.verifyReceipt(
      receipt.replaceFirst('glm-5.3-flash', 'glm-5.3-flasH'),
      gatewayAttestation,
    );
    expect(bad.signatureOk, isFalse);
    final nonce = await backend.verifyReport(
      gatewayAttestation,
      'cd' * 32,
      collateralPcs,
      _now.millisecondsSinceEpoch ~/ 1000,
    );
    expect(nonce.reportDataOk, isFalse);
  });

  test('Live: Kollateral von Intel PCS holen und Quote prüfen', () async {
    final client = http.Client();
    addTearDown(client.close);
    final live = RustAttestationCrypto(
      backend: backend,
      pcs: PcsCollateralClient(client: client, backend: backend),
      cache: CollateralCache(
        dir: Directory('${tmp.path}/live'),
        now: DateTime.now,
      ),
      clock: DateTime.now,
    );
    final sw = Stopwatch()..start();
    final c = await live.collateralFor(quote);
    // ignore: avoid_print
    print(
      'attest-collateral ms=${sw.elapsedMilliseconds} bytes=${c.json.length} nextUpdate=${c.validUntil}',
    );
    // Der Fixture-Quote ist alt; das heutige Kollateral darf ihn ablehnen, muss aber lesbar sein.
    try {
      await live.verifyQuote(quote, c, DateTime.now());
    } on QuoteVerificationException catch (e) {
      // ignore: avoid_print
      print('attest-live verify: ${e.reason}');
    }
  }, skip: !_live);
}
