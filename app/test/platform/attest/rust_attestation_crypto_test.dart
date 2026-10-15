import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PanicException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/generated/quote.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../support/fake_attest_backend.dart';

QuoteInfo _info(
  FakeAttestBackend b, {
  bool ok = true,
  String status = 'UpToDate',
  String? error,
}) => QuoteInfo(
  ok: ok,
  error: error,
  tcbStatus: status,
  advisoryIds: const ['INTEL-SA-1'],
  mrTd: b.quoteResult.mrTd,
  rtMr0: b.quoteResult.rtMr0,
  rtMr1: b.quoteResult.rtMr1,
  rtMr2: b.quoteResult.rtMr2,
  rtMr3: b.quoteResult.rtMr3,
  reportData: b.quoteResult.reportData,
);

void main() {
  late Directory dir;
  late FakeAttestBackend backend;
  late CollateralCache cache;
  var now = DateTime.utc(2026, 10, 14);
  var netUp = true;
  var fetches = 0;
  final quote = Uint8List.fromList([1, 2, 3]);
  String text(QuoteCollateral c) => utf8.decode(c.json);

  RustAttestationCrypto build() {
    final client = MockClient((req) async {
      fetches++;
      if (!netUp) throw const SocketException('offline');
      final p = req.url.path;
      return http.Response(
        p.endsWith('.der') ? 'R' : '{}',
        200,
        headers: const {
          'sgx-pck-crl-issuer-chain': 'a',
          'sgx-tcb-info-issuer-chain': 'b',
          'sgx-enclave-identity-issuer-chain': 'c',
        },
      );
    });
    return RustAttestationCrypto(
      backend: backend,
      pcs: PcsCollateralClient(client: client, backend: backend),
      cache: cache,
      clock: () => now,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('attest-crypto');
    backend = FakeAttestBackend(nextUpdateIso: '2026-11-12T22:38:12Z');
    now = DateTime.utc(2026, 10, 14);
    cache = CollateralCache(dir: dir, now: () => now);
    netUp = true;
    fetches = 0;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'holt Kollateral einmal und bedient weitere Aufrufe aus dem Cache',
    () async {
      final c = build();
      final a = await c.collateralFor(quote);
      expect(a.validUntil, DateTime.utc(2026, 11, 12, 22, 38, 12));
      expect(fetches, 4);
      final b = await c.collateralFor(quote);
      expect(text(b), text(a));
      expect(fetches, 4, reason: 'zweiter Aufruf ohne Netz');
    },
  );

  test('erneuert bei weniger als 3 Tagen Restlaufzeit, behält Cache bei Netzfehler', () async {
    final c = build();
    final a = await c.collateralFor(quote);
    now = DateTime.utc(2026, 11, 10); // 2 Tage 22 h vor nextUpdate
    backend.nextUpdateIso = '2026-12-10T00:00:00Z';
    final b = await c.collateralFor(quote);
    expect(text(b), isNot(text(a)));
    expect(b.validUntil, DateTime.utc(2026, 12, 10));
    now = DateTime.utc(2026, 12, 8);
    netUp = false;
    expect(text(await c.collateralFor(quote)), text(b));
  });

  test('ohne Cache und Netz: CollateralUnavailableException; abgelaufener Cache zählt nicht', () async {
    final c = build();
    netUp = false;
    await expectLater(
      c.collateralFor(quote),
      throwsA(isA<CollateralUnavailableException>()),
    );
    netUp = true;
    await c.collateralFor(quote);
    now = DateTime.utc(2026, 11, 13);
    netUp = false;
    await expectLater(
      c.collateralFor(quote),
      throwsA(isA<CollateralUnavailableException>()),
    );
  });

  test('PCS-Fehler nennt den Grund ohne Nutzdaten', () async {
    final c = RustAttestationCrypto(
      backend: backend,
      pcs: PcsCollateralClient(
        client: MockClient((_) async => http.Response('x', 503)),
        backend: backend,
      ),
      cache: cache,
      clock: () => now,
    );
    await expectLater(
      c.collateralFor(quote),
      throwsA(
        isA<CollateralUnavailableException>().having(
          (e) => e.reason,
          'reason',
          contains('503'),
        ),
      ),
    );
  });

  test(
    'verifyQuote reicht Unix-Sekunden an Rust und bildet die Felder ab',
    () async {
      final c = build();
      final at = DateTime.utc(2026, 10, 14, 12);
      final v = await c.verifyQuote(
        quote,
        QuoteCollateral(Uint8List.fromList(utf8.encode('{}'))),
        at,
      );
      expect(backend.lastNow, at.millisecondsSinceEpoch ~/ 1000);
      expect(v.tcbStatus, TcbStatus.upToDate);
      expect(v.advisoryIds, ['INTEL-SA-1']);
      expect(v.rtmr3, hasLength(48));
      expect(v.rtmr3.first, 3);
      expect(v.reportData, hasLength(64));
    },
  );

  test('ungültiger Quote, unbekannter Status und Rust-Fehler werfen QuoteVerificationException', () async {
    final c = build();
    final col = QuoteCollateral(Uint8List(0));
    backend.quoteResult = _info(backend, ok: false, error: 'Signatur');
    await expectLater(
      c.verifyQuote(quote, col, now),
      throwsA(
        isA<QuoteVerificationException>().having(
          (e) => e.reason,
          'reason',
          'Signatur',
        ),
      ),
    );
    backend.quoteResult = _info(backend, ok: false);
    await expectLater(
      c.verifyQuote(quote, col, now),
      throwsA(isA<QuoteVerificationException>()),
    );
    backend.quoteResult = _info(backend, status: 'Neu');
    await expectLater(
      c.verifyQuote(quote, col, now),
      throwsA(isA<QuoteVerificationException>()),
    );
    backend.throwOnVerify = true;
    await expectLater(
      c.verifyQuote(quote, col, now),
      throwsA(isA<QuoteVerificationException>()),
    );
  });

  test('TDRelaunchAdvised wird auf eigene Statuswerte abgebildet', () async {
    final c = build();
    final col = QuoteCollateral(Uint8List(0));
    const names = {
      'TDRelaunchAdvised': TcbStatus.relaunchAdvised,
      'TDRelaunchAdvisedConfigurationNeeded':
          TcbStatus.relaunchAdvisedConfigurationNeeded,
    };
    for (final e in names.entries) {
      backend.quoteResult = _info(backend, status: e.key);
      final v = await c.verifyQuote(quote, col, now);
      expect(v.tcbStatus, e.value);
      expect(v.advisoryIds, contains('INTEL-SA-1'));
    }
  });

  test('PanicException aus Rust wird zur QuoteVerificationException', () async {
    final c = build();
    final col = QuoteCollateral(Uint8List(0));
    backend.panic = PanicException('boom');
    await expectLater(
      c.verifyQuote(quote, col, now),
      throwsA(isA<QuoteVerificationException>()),
    );
    expect(
      () => c.verifyEd25519(Uint8List(32), Uint8List(1), Uint8List(64)),
      throwsA(isA<QuoteVerificationException>()),
    );
    expect(
      () => c.sha256(Uint8List(1)),
      throwsA(isA<QuoteVerificationException>()),
    );
    expect(
      () => c.sha384(Uint8List(1)),
      throwsA(isA<QuoteVerificationException>()),
    );
  });

  test('alle TCB-Stufen werden abgebildet', () async {
    final c = build();
    final col = QuoteCollateral(Uint8List(0));
    const names = {
      'UpToDate': TcbStatus.upToDate,
      'SWHardeningNeeded': TcbStatus.swHardeningNeeded,
      'ConfigurationNeeded': TcbStatus.configurationNeeded,
      'ConfigurationAndSWHardeningNeeded':
          TcbStatus.configurationAndSwHardeningNeeded,
      'OutOfDate': TcbStatus.outOfDate,
      'OutOfDateConfigurationNeeded': TcbStatus.outOfDateConfigurationNeeded,
      'Revoked': TcbStatus.revoked,
    };
    for (final e in names.entries) {
      backend.quoteResult = _info(backend, status: e.key);
      expect((await c.verifyQuote(quote, col, now)).tcbStatus, e.value);
    }
  });

  test(
    'Hashes, Ed25519 und SPKI gehen an Rust, SPKI-Fehler ist FormatException',
    () {
      final c = build();
      expect(c.sha256(Uint8List(5)), [5]);
      expect(c.sha384(Uint8List(5)), [5, 384 % 256]);
      expect(c.spkiSha256(Uint8List(7)), [7, 1]);
      expect(
        c.verifyEd25519(Uint8List(32), Uint8List(1), Uint8List(64)),
        isTrue,
      );
      expect(
        c.verifyEd25519(Uint8List(31), Uint8List(1), Uint8List(64)),
        isFalse,
      );
      backend.throwOnSpki = true;
      expect(() => c.spkiSha256(Uint8List(7)), throwsFormatException);
    },
  );

  test(
    'E2EE-Aufrufe gehen an Rust, Fehler und Panics werden E2eeCryptoException',
    () {
      final c = build();
      final pair = c.e2eeGenerateKeypair();
      expect(pair.public, hasLength(32));
      expect(
        c.e2eeEncrypt(pair.public, Uint8List(3), Uint8List(1)),
        hasLength(66),
      );
      expect(c.e2eeDecrypt(pair.secret, 'abcd', Uint8List(1)), [4]);
      expect(
        () => c.e2eeDecrypt(pair.secret, '', Uint8List(1)),
        throwsA(isA<E2eeCryptoException>()),
      );
      backend.panic = PanicException('boom');
      expect(c.e2eeGenerateKeypair, throwsA(isA<E2eeCryptoException>()));
      expect(
        () => c.e2eeEncrypt(pair.public, Uint8List(1), Uint8List(1)),
        throwsA(isA<E2eeCryptoException>()),
      );
      expect(
        () => c.e2eeDecrypt(pair.secret, 'ab', Uint8List(1)),
        throwsA(isA<E2eeCryptoException>()),
      );
    },
  );

  test(
    'NEAR-Aufrufe gehen an Rust, Fehler und Panics werden E2eeCryptoException',
    () {
      final c = build();
      final id = c.nearGenerateIdentity();
      expect(id.public, hasLength(32));
      expect(id.secret, hasLength(32));
      expect(c.nearEncrypt(id.public, Uint8List(3)), hasLength(150));
      expect(c.nearDecrypt(id.secret, 'abcd'), [4]);
      expect(
        () => c.nearDecrypt(id.secret, ''),
        throwsA(isA<E2eeCryptoException>()),
      );
      backend.panic = PanicException('boom');
      expect(c.nearGenerateIdentity, throwsA(isA<E2eeCryptoException>()));
      expect(
        () => c.nearEncrypt(id.public, Uint8List(1)),
        throwsA(isA<E2eeCryptoException>()),
      );
      expect(
        () => c.nearDecrypt(id.secret, 'ab'),
        throwsA(isA<E2eeCryptoException>()),
      );
    },
  );
}
