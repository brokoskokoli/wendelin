import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'p384_support.dart';

// Edge cases of the ES384 check that a real token cannot reach: forged keys
// and signatures built with the test arithmetic in p384_support.dart.

final _iat = DateTime.fromMillisecondsSinceEpoch(
  1792318698 * 1000,
  isUtc: true,
);

Map<String, Object?> get _realKey =>
    ((jsonDecode(
                  File('test/fixtures/tee/nras_jwks_subset.json')
                      .readAsStringSync(),
                ) as Map)['keys']
                as List)
            .first
        as Map<String, Object?>;

String get _realToken =>
    ((jsonDecode(
              File('test/fixtures/tee/nras_signed.json').readAsStringSync(),
            ) as List).first
            as List)[1]
        as String;

BigInt _coord(String name) => bytesToInt(
  base64Url.decode(base64Url.normalize(_realKey[name]! as String)),
);

Future<String> _reason(Future<Object?> f) async {
  try {
    await f;
  } on NrasJwtException catch (e) {
    return e.reason;
  }
  return 'accepted';
}

NrasTokenVerifier _verifierFor(
  String jwks, {
  DateTime? now,
  Duration maxAge = const Duration(hours: 1),
  Duration minRefetch = Duration.zero,
  int Function()? calls,
}) {
  final clock = now ?? _iat.add(const Duration(minutes: 1));
  return NrasTokenVerifier(
    jwks: NrasJwks(
      client: MockClient((_) async => http.Response(jwks, 200)),
      clock: () => clock,
      maxAge: maxAge,
      minRefetch: minRefetch,
    ),
    clock: () => clock,
  );
}

void main() {
  final msg = utf8.encode('m');

  group('P384: r/s im Bereich', () {
    test('s + n und s = n werden abgelehnt, (r, s) gilt', () {
      final f = smallSForgery(msg);
      bool ok(BigInt r, BigInt s) => P384.verify(
        x: f.q.$1,
        y: f.q.$2,
        message: msg,
        signature: [...intTo48(r), ...intTo48(s)],
      );
      expect(ok(f.r, f.s), isTrue);
      expect(ok(f.r, f.s + p384N), isFalse);
      expect(ok(f.r, p384N), isFalse);
      expect(ok(f.r, BigInt.zero), isFalse);
    });

    test('r = n und r = 0 werden abgelehnt', () {
      final f = smallSForgery(msg);
      for (final r in [p384N, BigInt.zero]) {
        expect(
          P384.verify(
            x: f.q.$1,
            y: f.q.$2,
            message: msg,
            signature: [...intTo48(r), ...intTo48(f.s)],
          ),
          isFalse,
        );
      }
    });
  });

  group('P384: Punkt auf der Kurve', () {
    test('Punkt neben der Kurve mit „gültiger“ Signatur wird abgelehnt', () {
      final f = offCurveForgery(msg);
      expect(P384.onCurve(f.q.$1, f.q.$2), isFalse);
      expect(
        P384.verify(
          x: f.q.$1,
          y: f.q.$2,
          message: msg,
          signature: [...intTo48(f.r), ...intTo48(f.r)],
        ),
        isFalse,
      );
    });

    test('echter Schlüssel, y + p (gleiche Zahl mod p) → abgelehnt', () {
      final parts = _realToken.split('.');
      final sig = base64Url.decode(base64Url.normalize(parts[2]));
      final message = ascii.encode('${parts[0]}.${parts[1]}');
      final x = _coord('x');
      final y = _coord('y');
      expect(P384.verify(x: x, y: y, message: message, signature: sig), isTrue);
      expect(
        P384.verify(x: x, y: y + p384P, message: message, signature: sig),
        isFalse,
      );
      expect(
        P384.verify(x: x + p384P, y: y, message: message, signature: sig),
        isFalse,
      );
      expect(
        P384.verify(x: x, y: y + BigInt.one, message: message, signature: sig),
        isFalse,
      );
    });
  });

  group('NrasTokenVerifier mit eigenem Schlüssel: Zeitfenster', () {
    final key = TestKey(BigInt.parse('c0ffee' * 8, radix: 16));
    final now = _iat.add(const Duration(minutes: 1));
    final sec = now.millisecondsSinceEpoch ~/ 1000;

    Map<String, Object?> claims({int? nbf, int? iat}) => {
      'iss': 'https://nras.attestation.nvidia.com',
      'exp': sec + 600,
      'nbf': ?nbf,
      'iat': ?iat,
    };

    Future<String> check(Map<String, Object?> c) =>
        _reason(_verifierFor(key.jwk, now: now).verify(key.token(c)));

    test('Kontrolle: Token mit eigenem Schlüssel gilt', () async {
      expect(await check(claims(nbf: sec - 5, iat: sec - 5)), 'accepted');
    });

    test('nur nbf in der Zukunft → jwt_expired', () async {
      expect(
        await check(claims(nbf: sec + 3600, iat: sec - 5)),
        NrasJwtReason.expired,
      );
      expect(await check(claims(nbf: sec + 3600)), NrasJwtReason.expired);
    });

    test('nur iat in der Zukunft → jwt_expired', () async {
      expect(
        await check(claims(nbf: sec - 5, iat: sec + 3600)),
        NrasJwtReason.expired,
      );
      expect(await check(claims(iat: sec + 3600)), NrasJwtReason.expired);
    });

    test('nbf/iat innerhalb der Toleranz gelten', () async {
      expect(await check(claims(nbf: sec + 100, iat: sec + 100)), 'accepted');
    });
  });
}
