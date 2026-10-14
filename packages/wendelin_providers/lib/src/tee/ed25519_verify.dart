import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Ed25519 signature verification (RFC 8032) in plain BigInt arithmetic.
///
/// Slow (affine coordinates) and not constant-time: only for the test fake
/// (`FakeAttestationCrypto`). The app uses the Rust implementation (WP47).
abstract final class Ed25519Reference {
  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _l =
      (BigInt.one << 252) +
      BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d =
      (-BigInt.from(121665) * BigInt.from(121666).modInverse(_p)) % _p;
  static final BigInt _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) >> 2, _p);
  static final (BigInt, BigInt) _base = _decodePoint(
    _encodeY(BigInt.from(4) * BigInt.from(5).modInverse(_p) % _p, even: true),
  )!;

  static Uint8List _encodeY(BigInt y, {required bool even}) {
    final out = _toLe(y, 32);
    if (!even) out[31] |= 0x80;
    return out;
  }

  static Uint8List _toLe(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = 0; i < len; i++) {
      out[i] = (x & BigInt.from(255)).toInt();
      x >>= 8;
    }
    return out;
  }

  static BigInt _fromLe(List<int> b) {
    var v = BigInt.zero;
    for (var i = b.length - 1; i >= 0; i--) {
      v = (v << 8) | BigInt.from(b[i]);
    }
    return v;
  }

  static (BigInt, BigInt)? _decodePoint(Uint8List b) {
    if (b.length != 32) return null;
    final sign = (b[31] >> 7) & 1;
    final y = _fromLe([...b.sublist(0, 31), b[31] & 0x7f]);
    if (y >= _p) return null;
    final y2 = y * y % _p;
    final x2 = (y2 - BigInt.one) * (_d * y2 + BigInt.one).modInverse(_p) % _p;
    var x = x2.modPow((_p + BigInt.from(3)) >> 3, _p);
    if ((x * x - x2) % _p != BigInt.zero) x = x * _sqrtM1 % _p;
    if ((x * x - x2) % _p != BigInt.zero) return null;
    if (x == BigInt.zero && sign == 1) return null;
    if ((x.isOdd ? 1 : 0) != sign) x = _p - x;
    return (x, y);
  }

  static (BigInt, BigInt) _add((BigInt, BigInt) a, (BigInt, BigInt) b) {
    final (x1, y1) = a;
    final (x2, y2) = b;
    final t = _d * x1 * x2 % _p * y1 % _p * y2 % _p;
    final x3 = (x1 * y2 + x2 * y1) % _p * (BigInt.one + t).modInverse(_p) % _p;
    final y3 =
        (y1 * y2 + x1 * x2) % _p * ((BigInt.one - t) % _p).modInverse(_p) % _p;
    return (x3, y3);
  }

  static (BigInt, BigInt) _mul(BigInt k, (BigInt, BigInt) point) {
    var result = (BigInt.zero, BigInt.one);
    var addend = point;
    var n = k;
    while (n > BigInt.zero) {
      if (n.isOdd) result = _add(result, addend);
      addend = _add(addend, addend);
      n >>= 1;
    }
    return result;
  }

  /// Whether [signature] (64 bytes) over [message] is valid for
  /// [publicKey] (32 bytes). Never throws.
  static bool verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) {
    if (publicKey.length != 32 || signature.length != 64) return false;
    final a = _decodePoint(publicKey);
    final r = _decodePoint(Uint8List.fromList(signature.sublist(0, 32)));
    if (a == null || r == null) return false;
    final s = _fromLe(signature.sublist(32));
    if (s >= _l) return false;
    final h =
        _fromLe(
          crypto.sha512.convert([
            ...signature.sublist(0, 32),
            ...publicKey,
            ...message,
          ]).bytes,
        ) %
        _l;
    final left = _mul(s, _base);
    final right = _add(r, _mul(h, a));
    return left.$1 == right.$1 && left.$2 == right.$2;
  }
}
