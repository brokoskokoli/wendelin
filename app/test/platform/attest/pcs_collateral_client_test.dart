import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';

import '../../support/fake_attest_backend.dart';

void main() {
  final quote = Uint8List(4);
  late FakeAttestBackend backend;
  final seen = <String>[];

  http.Response ok(String body, {Map<String, String> headers = const {}}) =>
      http.Response(body, 200, headers: headers);

  MockClient server({
    int failWith = 0,
    bool skipHeader = false,
    bool altTcbHeader = false,
  }) => MockClient((req) async {
    seen.add(req.url.toString());
    final p = req.url.path;
    if (failWith != 0 && p.contains('qe/identity')) {
      return http.Response('x', failWith);
    }
    if (p.endsWith('/pckcrl')) {
      return ok('CRL', headers: {'sgx-pck-crl-issuer-chain': 'A%0AB%20C'});
    }
    if (p.endsWith('/tcb')) {
      return ok(
        '{"tcbInfo":{},"signature":"00"}',
        headers: skipHeader
            ? {}
            : {
                altTcbHeader
                        ? 'tcb-info-issuer-chain'
                        : 'sgx-tcb-info-issuer-chain':
                    'T',
              },
      );
    }
    if (p.endsWith('/qe/identity')) {
      return ok('{}', headers: {'sgx-enclave-identity-issuer-chain': 'Q%2B'});
    }
    if (p.endsWith('/root.der')) return ok('ROOT');
    return http.Response('?', 404);
  });

  setUp(() {
    backend = FakeAttestBackend();
    seen.clear();
  });

  test(
    'ruft PCK-CRL, TCB, QE-Identität und Root-CRL ab und setzt sie zusammen',
    () async {
      final c = PcsCollateralClient(client: server(), backend: backend);
      expect(await c.fetch(quote), '{"built":1}');
      expect(seen, [
        'https://api.trustedservices.intel.com/sgx/certification/v4/pckcrl?ca=platform&encoding=der',
        'https://api.trustedservices.intel.com/tdx/certification/v4/tcb?fmspc=00806F050000&update=standard',
        'https://api.trustedservices.intel.com/tdx/certification/v4/qe/identity?update=standard',
        'https://certs.example/root.der',
      ]);
      final p = backend.lastParts!;
      expect(p.pckCrlIssuerChain, 'A\nB C', reason: 'Header sind URL-kodiert');
      expect(p.qeIdentityIssuerChain, 'Q+');
      expect(p.tcbInfoIssuerChain, 'T');
      expect(String.fromCharCodes(p.pckCrl), 'CRL');
      expect(String.fromCharCodes(p.rootCaCrl), 'ROOT');
      expect(p.tcbInfoBody, contains('tcbInfo'));
    },
  );

  test('akzeptiert den alternativen TCB-Header', () async {
    final c = PcsCollateralClient(
      client: server(altTcbHeader: true),
      backend: backend,
    );
    await c.fetch(quote);
    expect(backend.lastParts!.tcbInfoIssuerChain, 'T');
  });

  test(
    'HTTP-Fehler und fehlende Header ergeben PcsException ohne Nutzdaten',
    () async {
      await expectLater(
        PcsCollateralClient(
          client: server(failWith: 503),
          backend: backend,
        ).fetch(quote),
        throwsA(
          isA<PcsException>().having(
            (e) => e.message,
            'message',
            allOf(contains('503'), contains('/qe/identity')),
          ),
        ),
      );
      await expectLater(
        PcsCollateralClient(
          client: server(skipHeader: true),
          backend: backend,
        ).fetch(quote),
        throwsA(
          isA<PcsException>().having(
            (e) => e.message,
            'message',
            contains('sgx-tcb-info-issuer-chain'),
          ),
        ),
      );
    },
  );

  test('Basis-URL mit Schrägstrich am Ende wird bereinigt', () async {
    final c = PcsCollateralClient(
      client: server(),
      backend: backend,
      baseUrl: 'https://pccs.example/',
    );
    await c.fetch(quote);
    expect(seen.first, startsWith('https://pccs.example/sgx/'));
  });
}
