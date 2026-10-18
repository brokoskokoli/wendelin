import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Minimal P-384 arithmetic for tests only (signing, forging edge cases).
typedef Pt = (BigInt, BigInt);

final p384P = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe'
  'ffffffff0000000000000000ffffffff',
  radix: 16,
);
final p384N = BigInt.parse(
  'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf'
  '581a0db248b0a77aecec196accc52973',
  radix: 16,
);
final p384B = BigInt.parse(
  'b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875a'
  'c656398d8a2ed19d2a85c8edd3ec2aef',
  radix: 16,
);
final p384G = (
  BigInt.parse(
    'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
    '5502f25dbf55296c3a545e3872760ab7',
    radix: 16,
  ),
  BigInt.parse(
    '3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c0'
    '0a60b1ce1d7e819d7a431d7c90ea0e5f',
    radix: 16,
  ),
);

Pt? ecAdd(Pt? a, Pt? b) {
  if (a == null) return b;
  if (b == null) return a;
  final BigInt l;
  if (a.$1 == b.$1) {
    if ((a.$2 + b.$2) % p384P == BigInt.zero) return null;
    l =
        ((BigInt.from(3) * a.$1 * a.$1 - BigInt.from(3)) *
            (BigInt.two * a.$2).modInverse(p384P)) %
        p384P;
  } else {
    l = ((b.$2 - a.$2) * (b.$1 - a.$1).modInverse(p384P)) % p384P;
  }
  final x = (l * l - a.$1 - b.$1) % p384P;
  return (x, (l * (a.$1 - x) - a.$2) % p384P);
}

Pt? ecMul(BigInt k, Pt point) {
  Pt? r;
  Pt? q = point;
  var rest = k;
  while (rest > BigInt.zero) {
    if (rest.isOdd) r = ecAdd(r, q);
    q = ecAdd(q, q);
    rest >>= 1;
  }
  return r;
}

Pt ecNeg(Pt a) => (a.$1, (p384P - a.$2) % p384P);

BigInt bytesToInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));

List<int> intTo48(BigInt v) => [
  for (var i = 47; i >= 0; i--) ((v >> (8 * i)) & BigInt.from(255)).toInt(),
];

BigInt hashOf(List<int> message) =>
    bytesToInt(crypto.sha384.convert(message).bytes);

/// Own test key pair.
class TestKey {
  TestKey(this.d) : pub = ecMul(d, p384G)!;
  final BigInt d;
  final Pt pub;

  String get jwk => jsonEncode({
    'keys': [
      {
        'kty': 'EC',
        'crv': 'P-384',
        'kid': 'test-kid',
        'x': base64Url.encode(intTo48(pub.$1)).replaceAll('=', ''),
        'y': base64Url.encode(intTo48(pub.$2)).replaceAll('=', ''),
      },
    ],
  });

  /// Raw r||s signature (fixed nonce k: tests only).
  List<int> sign(List<int> message) {
    final k = BigInt.parse('1234567890abcdef' * 3, radix: 16);
    final r = ecMul(k, p384G)!.$1 % p384N;
    final s = (k.modInverse(p384N) * (hashOf(message) + r * d)) % p384N;
    return [...intTo48(r), ...intTo48(s)];
  }

  /// Compact JWT (ES384, kid `test-kid`) with [claims].
  String token(Map<String, Object?> claims) {
    String enc(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final signing =
        '${enc({'alg': 'ES384', 'kid': 'test-kid'})}.${enc(claims)}';
    final sig = sign(utf8.encode(signing));
    return '$signing.${base64Url.encode(sig).replaceAll('=', '')}';
  }
}

/// A public key [q] (not on the curve, usually) with which (r, s = r) is a
/// valid signature of [message]: only the group formulas are exercised, so a
/// verifier without the on-curve check accepts it.
({Pt q, BigInt r}) offCurveForgery(List<int> message) {
  final e = hashOf(message);
  for (var r = BigInt.from(1000); ; r += BigInt.one) {
    final a = ecMul(e * r.modInverse(p384N) % p384N, p384G)!;
    for (var x0 = BigInt.from(7); x0 < BigInt.from(500); x0 += BigInt.one) {
      final rhs = (r + x0 + a.$1) % p384P;
      final root = rhs.modPow((p384P + BigInt.one) >> 2, p384P);
      if (root * root % p384P != rhs) continue;
      final y = (a.$2 - root * (a.$1 - x0)) % p384P;
      final q = (x0, y);
      final sum = ecAdd(a, q);
      if (sum == null || sum.$1 % p384N != r) continue;
      final onCurve =
          y * y % p384P == (x0 * x0 * x0 - BigInt.from(3) * x0 + p384B) % p384P;
      if (onCurve) continue;
      return (q: q, r: r);
    }
  }
}

/// A key and signature (r, s) with a tiny s, so that (r, s + n) fits into
/// 48 bytes and is the same signature modulo n.
({Pt q, BigInt r, BigInt s}) smallSForgery(List<int> message) {
  final e = hashOf(message);
  final s = BigInt.from(5);
  for (var x = BigInt.from(2); ; x += BigInt.one) {
    final rhs = (x * x * x - BigInt.from(3) * x + p384B) % p384P;
    final y = rhs.modPow((p384P + BigInt.one) >> 2, p384P);
    if (y * y % p384P != rhs) continue;
    final big = (x, y);
    final w = s.modInverse(p384N);
    final u1 = e * w % p384N;
    final u2 = x * w % p384N;
    final rest = ecAdd(big, ecNeg(ecMul(u1, p384G)!));
    final q = ecMul(u2.modInverse(p384N), rest!)!;
    return (q: q, r: x, s: s);
  }
}
