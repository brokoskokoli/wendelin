import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// Echtes NRAS-Token (2026-10-18) und der zugehörige öffentliche NVIDIA-Schlüssel.
const _nonce =
    '75b040ace9638a02cde08c76511c28c7f4ed40af4d97b6afed837805df831eab';
final _iat = DateTime.fromMillisecondsSinceEpoch(
  1792318698 * 1000,
  isUtc: true,
);

List<Object?> get _signed =>
    jsonDecode(File('test/fixtures/tee/nras_signed.json').readAsStringSync())
        as List<Object?>;
String get _jwks =>
    File('test/fixtures/tee/nras_jwks_subset.json').readAsStringSync();
String get _token => (_signed.first! as List)[1]! as String;

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Map<String, Object?> _part(String t, int i) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(t.split('.')[i]))),
) as Map<String, Object?>;

/// [token] with an edited header or claims and the original signature.
String _edit(
  String token, {
  int part = 1,
  required void Function(Map<String, Object?>) f,
}) {
  final parts = token.split('.');
  final m = _part(token, part);
  f(m);
  parts[part] = _b64(utf8.encode(jsonEncode(m)));
  return parts.join('.');
}

String _flipSignature(String token) {
  final parts = token.split('.');
  final sig = base64Url.decode(base64Url.normalize(parts[2]));
  sig[10] ^= 1;
  parts[2] = _b64(sig);
  return parts.join('.');
}

class _Jwks {
  _Jwks([this.body, this.status = 200]);
  String? body;
  int status;
  int calls = 0;
  http.Client get client => MockClient((r) async {
    calls++;
    expect(r.url.host, 'nras.attestation.nvidia.com');
    return http.Response(body ?? _jwks, status);
  });
}

NrasTokenVerifier _verifier(
  _Jwks jwks, {
  DateTime? now,
  Duration maxAge = const Duration(hours: 1),
  Duration minRefetch = Duration.zero,
}) {
  final clock = now ?? _iat.add(const Duration(minutes: 1));
  return NrasTokenVerifier(
    jwks: NrasJwks(
      client: jwks.client,
      clock: () => clock,
      maxAge: maxAge,
      minRefetch: minRefetch,
    ),
    clock: () => clock,
  );
}

Future<String> _reason(Future<Object?> f) async {
  try {
    await f;
  } on NrasJwtException catch (e) {
    return e.reason;
  }
  return 'accepted';
}

void main() {
  group('NrasTokenVerifier mit echtem NVIDIA-Token', () {
    test('gültige ES384-Signatur → Claims aus dem geprüften Token', () async {
      final claims = await _verifier(_Jwks()).verify(_token);
      expect(claims['x-nvidia-overall-att-result'], isTrue);
      expect(claims['eat_nonce'], _nonce);
    });

    test('Signatur verändert → jwt_signature', () async {
      expect(
        await _reason(_verifier(_Jwks()).verify(_flipSignature(_token))),
        NrasJwtReason.signature,
      );
    });

    test(
      'Claims verändert (Ergebnis auf false/andere Nonce) → jwt_signature',
      () async {
        for (final f in <void Function(Map<String, Object?>)>[
          (m) => m['x-nvidia-overall-att-result'] = false,
          (m) => m['eat_nonce'] = 'ab' * 32,
          (m) => m['exp'] = 9999999999,
        ]) {
          expect(
            await _reason(_verifier(_Jwks()).verify(_edit(_token, f: f))),
            NrasJwtReason.signature,
          );
        }
      },
    );

    test('Signatur eines anderen Tokens → jwt_signature', () async {
      final other = _token.split('.');
      final parts = _edit(_token, f: (m) => m['jti'] = 'x').split('.');
      expect(
        await _reason(
          _verifier(_Jwks()).verify('${parts[0]}.${parts[1]}.${other[2]}'),
        ),
        NrasJwtReason.signature,
      );
    });

    test('alg none/HS256/fehlend → jwt_alg, nie akzeptiert', () async {
      for (final alg in ['none', 'HS256', 'ES256', null]) {
        final t = _edit(
          _token,
          part: 0,
          f: (m) => alg == null ? m.remove('alg') : m['alg'] = alg,
        );
        expect(
          await _reason(_verifier(_Jwks()).verify(t)),
          NrasJwtReason.algorithm,
        );
      }
      expect(
        await _reason(
          _verifier(_Jwks())
              .verify('${_token.split('.')[0]}.${_token.split('.')[1]}.'),
        ),
        NrasJwtReason.signature,
      );
    });

    test('unlesbar → jwt_malformed', () async {
      for (final t in ['', 'a.b', 'a.b.c.d', '!!.!!.!!']) {
        expect(
          await _reason(_verifier(_Jwks()).verify(t)),
          NrasJwtReason.malformed,
        );
      }
      expect(
        await _reason(
          _verifier(_Jwks())
              .verify(_edit(_token, part: 0, f: (m) => m.remove('kid'))),
        ),
        NrasJwtReason.malformed,
      );
    });

    test('abgelaufen oder noch nicht gültig → jwt_expired', () async {
      final exp = DateTime.fromMillisecondsSinceEpoch(
        1792322298 * 1000,
        isUtc: true,
      );
      expect(
        await _reason(
          _verifier(
            _Jwks(),
            now: exp.add(const Duration(minutes: 3)),
          ).verify(_token),
        ),
        NrasJwtReason.expired,
      );
      // Innerhalb der Toleranz noch gültig.
      expect(
        await _reason(
          _verifier(
            _Jwks(),
            now: exp.add(const Duration(minutes: 1)),
          ).verify(_token),
        ),
        'accepted',
      );
      expect(
        await _reason(
          _verifier(
            _Jwks(),
            now: _iat.subtract(const Duration(minutes: 10)),
          ).verify(_token),
        ),
        NrasJwtReason.expired,
      );
    });

    test('fremder Aussteller → jwt_issuer', () async {
      final v = NrasTokenVerifier(
        jwks: NrasJwks(client: _Jwks().client, clock: () => _iat),
        clock: () => _iat,
        issuer: 'https://evil.example',
      );
      expect(await _reason(v.verify(_token)), NrasJwtReason.issuer);
    });
  });

  group('NrasJwks', () {
    test('Cache: zweite Prüfung ohne neuen Abruf; nach maxAge neu', () async {
      final jwks = _Jwks();
      var now = _iat.add(const Duration(minutes: 1));
      final v = NrasTokenVerifier(
        jwks: NrasJwks(client: jwks.client, clock: () => now),
        clock: () => now,
      );
      await v.verify(_token);
      await v.verify(_token);
      expect(jwks.calls, 1);
      now = now.add(const Duration(minutes: 30));
      await v.verify(_token);
      expect(jwks.calls, 1);
      now = now.add(const Duration(hours: 1));
      // Token inzwischen abgelaufen, aber der Abruf geschieht vorher.
      await _reason(v.verify(_token));
      expect(jwks.calls, 2);
    });

    test('unbekannte kid → einmal neu laden, danach akzeptiert', () async {
      final jwks = _Jwks('{"keys":[]}');
      final v = _verifier(jwks);
      expect(await _reason(v.verify(_token)), NrasJwtReason.jwksUnavailable);
      jwks.body = null;
      expect(await _reason(v.verify(_token)), 'accepted');
      expect(jwks.calls, 2);
    });

    test('kid auch nach dem Neuladen unbekannt → jwt_unknown_kid', () async {
      final other = _jwks.replaceAll('01a45dc1', 'deadbeef');
      final jwks = _Jwks(other);
      expect(
        await _reason(_verifier(jwks).verify(_token)),
        NrasJwtReason.unknownKey,
      );
      expect(jwks.calls, 1);
    });

    test(
      'Neuladen höchstens alle minRefetch (kein Flut durch falsche kid)',
      () async {
        final jwks = _Jwks(_jwks.replaceAll('01a45dc1', 'deadbeef'));
        final v = _verifier(jwks, minRefetch: const Duration(minutes: 5));
        for (var i = 0; i < 4; i++) {
          expect(await _reason(v.verify(_token)), NrasJwtReason.unknownKey);
        }
        expect(jwks.calls, 1);
      },
    );

    test(
      'JWKS nicht abrufbar (HTTP 500, kein JSON, Netz) → jwks_unavailable',
      () async {
        for (final jwks in [_Jwks('x', 500), _Jwks('kein json')]) {
          expect(
            await _reason(_verifier(jwks).verify(_token)),
            NrasJwtReason.jwksUnavailable,
          );
        }
        final down = NrasTokenVerifier(
          jwks: NrasJwks(
            client: MockClient(
              (_) async => throw const SocketException('down'),
            ),
          ),
          clock: () => _iat,
        );
        expect(
          await _reason(down.verify(_token)),
          NrasJwtReason.jwksUnavailable,
        );
      },
    );

    test('Schlüssel nicht auf der Kurve wird nicht übernommen', () async {
      final bad = jsonDecode(_jwks) as Map<String, Object?>;
      ((bad['keys']! as List).first as Map)['y'] = _b64(
        Uint8List(48)..[47] = 1,
      );
      expect(
        await _reason(_verifier(_Jwks(jsonEncode(bad))).verify(_token)),
        NrasJwtReason.jwksUnavailable,
      );
    });
  });

  group('P384', () {
    test('Randfälle: Länge, r/s = 0 oder ≥ n, Punkt nicht auf der Kurve', () {
      final key = ((jsonDecode(_jwks) as Map)['keys'] as List).first as Map;
      BigInt n(String s) => BigInt.parse(
        hex(base64Url.decode(base64Url.normalize(s))),
        radix: 16,
      );
      final x = n(key['x'] as String);
      final y = n(key['y'] as String);
      final msg = utf8.encode('m');
      expect(P384.onCurve(x, y), isTrue);
      expect(P384.onCurve(x, y + BigInt.one), isFalse);
      expect(
        P384.verify(x: x, y: y, message: msg, signature: Uint8List(95)),
        isFalse,
      );
      expect(
        P384.verify(x: x, y: y, message: msg, signature: Uint8List(96)),
        isFalse,
      );
      expect(
        P384.verify(
          x: x,
          y: y,
          message: msg,
          signature: Uint8List(96)..fillRange(0, 96, 0xff),
        ),
        isFalse,
      );
      expect(
        P384.verify(
          x: x,
          y: y + BigInt.one,
          message: msg,
          signature: Uint8List(96)
            ..[47] = 1
            ..[95] = 1,
        ),
        isFalse,
      );
    });
  });
}

String hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
