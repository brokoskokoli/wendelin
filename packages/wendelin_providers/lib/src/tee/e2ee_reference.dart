import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'attestation_crypto.dart';
import 'codec.dart';

/// Slow, plain-Dart implementation of the field encryption of Phala E2EE v2
/// (suite `x25519-aes-256-gcm-hkdf-sha256`, see `E2eeProtocolV2`) for tests,
/// the fake crypto and demo mode. It is byte-compatible with the Rust module
/// (`native/attest/src/e2ee.rs`); the contract suite proves that with a
/// vector made by an independent implementation (Node.js `crypto`).
/// **Not for production**: not constant-time.
abstract final class E2eeReference {
  static final _random = Random.secure();
  static final _p = (BigInt.one << 255) - BigInt.from(19);
  static final _a24 = BigInt.from(121665);

  /// A fresh X25519 key pair.
  static E2eeKeypair generateKeypair() => keypairFromSeed(
    Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256))),
  );

  /// The key pair for [seed] (raw secret, 32 bytes).
  static E2eeKeypair keypairFromSeed(Uint8List seed) {
    final basepoint = Uint8List(32)..[0] = 9;
    return E2eeKeypair(
      secret: Uint8List.fromList(seed),
      public: _x25519(seed, basepoint),
    );
  }

  /// Encrypts like `e2ee::encrypt` with an optional fixed ephemeral seed and
  /// GCM nonce (test vectors).
  static String encrypt(
    Uint8List recipientPublic,
    Uint8List plaintext,
    Uint8List aad, {
    Uint8List? ephemeralSeed,
    Uint8List? nonce,
  }) {
    if (recipientPublic.length != 32) {
      throw const E2eeCryptoException('Empfängerschlüssel: 32 Byte erwartet');
    }
    final eph = keypairFromSeed(
      ephemeralSeed ??
          Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256))),
    );
    final n =
        nonce ??
        Uint8List.fromList(List.generate(12, (_) => _random.nextInt(256)));
    final key = _key(eph.secret, recipientPublic);
    final sealed = _gcm(key, n, plaintext, aad, encrypt: true);
    return AttestCodec.hex([...eph.public, ...n, ...sealed]);
  }

  /// Decrypts a wire value; throws [E2eeCryptoException] on any problem.
  static Uint8List decrypt(Uint8List secret, String wireHex, Uint8List aad) {
    final Uint8List wire;
    try {
      wire = AttestCodec.unhex(
        wireHex.startsWith('0x') ? wireHex.substring(2) : wireHex,
      );
    } on FormatException {
      throw const E2eeCryptoException('Chiffre ist kein Hex');
    }
    if (wire.length < 60) throw const E2eeCryptoException('Chiffre zu kurz');
    if (secret.length != 32) {
      throw const E2eeCryptoException('Privatschlüssel: 32 Byte erwartet');
    }
    final key = _key(secret, wire.sublist(0, 32));
    return _gcm(
      key,
      wire.sublist(32, 44),
      wire.sublist(44),
      aad,
      encrypt: false,
    );
  }

  static Uint8List _key(Uint8List secret, Uint8List peer) {
    final shared = _x25519(secret, peer);
    if (shared.every((b) => b == 0)) {
      throw const E2eeCryptoException('Schlüsselvereinbarung ungültig');
    }
    // HKDF-SHA256, no salt (= 32 zero bytes), info "aci.e2ee.v2.x25519", L = 32.
    final prk = crypto.Hmac(crypto.sha256, Uint8List(32)).convert(shared).bytes;
    final info = 'aci.e2ee.v2.x25519'.codeUnits;
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, prk).convert([...info, 1]).bytes,
    );
  }

  // --- X25519 (RFC 7748) ---------------------------------------------------

  static BigInt _le(List<int> b) {
    var r = BigInt.zero;
    for (var i = b.length - 1; i >= 0; i--) {
      r = (r << 8) | BigInt.from(b[i]);
    }
    return r;
  }

  /// X25519 (RFC 7748) for the other reference implementations of this package.
  static Uint8List x25519(Uint8List scalar, Uint8List point) =>
      _x25519(scalar, point);

  static Uint8List _x25519(Uint8List scalar, Uint8List point) {
    if (scalar.length != 32 || point.length != 32) {
      throw const E2eeCryptoException('X25519: 32 Byte erwartet');
    }
    final k = Uint8List.fromList(scalar)
      ..[0] &= 248
      ..[31] &= 127
      ..[31] |= 64;
    final kk = _le(k);
    final x1 = _le(point) & ((BigInt.one << 255) - BigInt.one);
    var x2 = BigInt.one;
    var z2 = BigInt.zero;
    var x3 = x1;
    var z3 = BigInt.one;
    var swap = 0;
    for (var t = 254; t >= 0; t--) {
      final kt = ((kk >> t) & BigInt.one).toInt();
      swap ^= kt;
      if (swap == 1) {
        (x2, x3) = (x3, x2);
        (z2, z3) = (z3, z2);
      }
      swap = kt;
      final a = (x2 + z2) % _p;
      final aa = (a * a) % _p;
      final b = (x2 - z2) % _p;
      final bb = (b * b) % _p;
      final e = (aa - bb) % _p;
      final c = (x3 + z3) % _p;
      final d = (x3 - z3) % _p;
      final da = (d * a) % _p;
      final cb = (c * b) % _p;
      final s = (da + cb) % _p;
      final df = (da - cb) % _p;
      x3 = (s * s) % _p;
      z3 = (x1 * ((df * df) % _p)) % _p;
      x2 = (aa * bb) % _p;
      z2 = (e * ((aa + _a24 * e) % _p)) % _p;
    }
    if (swap == 1) {
      (x2, x3) = (x3, x2);
      (z2, z3) = (z3, z2);
    }
    var r = (x2 * z2.modPow(_p - BigInt.two, _p)) % _p;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (r & BigInt.from(255)).toInt();
      r >>= 8;
    }
    return out;
  }

  // --- AES-256-GCM -----------------------------------------------------------

  static Uint8List _gcm(
    Uint8List key,
    Uint8List nonce,
    Uint8List input,
    Uint8List aad, {
    required bool encrypt,
  }) {
    final aes = _Aes(key);
    final h = aes.block(Uint8List(16));
    final ct = encrypt ? null : input.sublist(0, input.length - 16);
    if (!encrypt && input.length < 16) {
      throw const E2eeCryptoException('Entschlüsselung fehlgeschlagen');
    }
    final data = encrypt ? input : ct!;
    final j0 = Uint8List(16)
      ..setRange(0, 12, nonce)
      ..[15] = 1;
    final counter = Uint8List.fromList(j0);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i += 16) {
      _inc(counter);
      final ks = aes.block(counter);
      for (var j = 0; j < 16 && i + j < data.length; j++) {
        out[i + j] = data[i + j] ^ ks[j];
      }
    }
    final tag = _tag(aes, h, j0, aad, encrypt ? out : data);
    if (encrypt) return Uint8List.fromList([...out, ...tag]);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ input[input.length - 16 + i];
    }
    if (diff != 0) {
      throw const E2eeCryptoException('Entschlüsselung fehlgeschlagen');
    }
    return out;
  }

  static void _inc(Uint8List c) {
    for (var i = 15; i >= 12; i--) {
      c[i] = (c[i] + 1) & 0xff;
      if (c[i] != 0) break;
    }
  }

  static Uint8List _tag(
    _Aes aes,
    Uint8List h,
    Uint8List j0,
    Uint8List aad,
    Uint8List ct,
  ) {
    var y = Uint8List(16);
    Uint8List ghash(Uint8List y, List<int> bytes) {
      for (var i = 0; i < bytes.length; i += 16) {
        final block = Uint8List(16);
        for (var j = 0; j < 16 && i + j < bytes.length; j++) {
          block[j] = bytes[i + j];
        }
        for (var j = 0; j < 16; j++) {
          y[j] ^= block[j];
        }
        y = _mul(y, h);
      }
      return y;
    }

    y = ghash(y, aad);
    y = ghash(y, ct);
    final lens = Uint8List(16);
    final a = aad.length * 8;
    final c = ct.length * 8;
    for (var i = 0; i < 8; i++) {
      lens[7 - i] = (a >> (8 * i)) & 0xff;
      lens[15 - i] = (c >> (8 * i)) & 0xff;
    }
    y = ghash(y, lens);
    final e = aes.block(j0);
    return Uint8List.fromList([for (var i = 0; i < 16; i++) y[i] ^ e[i]]);
  }

  /// Multiplication in GF(2^128) as in NIST SP 800-38D.
  static Uint8List _mul(Uint8List x, Uint8List y) {
    final z = Uint8List(16);
    final v = Uint8List.fromList(y);
    for (var i = 0; i < 128; i++) {
      if ((x[i >> 3] >> (7 - (i & 7))) & 1 == 1) {
        for (var j = 0; j < 16; j++) {
          z[j] ^= v[j];
        }
      }
      final lsb = v[15] & 1;
      for (var j = 15; j > 0; j--) {
        v[j] = (v[j] >> 1) | ((v[j - 1] & 1) << 7);
      }
      v[0] >>= 1;
      if (lsb == 1) v[0] ^= 0xe1;
    }
    return z;
  }
}

/// AES-256 block encryption (FIPS 197).
final class _Aes {
  _Aes(Uint8List key) {
    final w = List<int>.filled(240, 0)..setRange(0, 32, key);
    var rcon = 1;
    for (var i = 8; i < 60; i++) {
      var t = w.sublist((i - 1) * 4, i * 4);
      if (i % 8 == 0) {
        t = [_sbox[t[1]] ^ rcon, _sbox[t[2]], _sbox[t[3]], _sbox[t[0]]];
        rcon = _xtime(rcon);
      } else if (i % 8 == 4) {
        t = [for (final b in t) _sbox[b]];
      }
      for (var j = 0; j < 4; j++) {
        w[i * 4 + j] = w[(i - 8) * 4 + j] ^ t[j];
      }
    }
    _round = Uint8List.fromList(w);
  }

  late final Uint8List _round;

  static int _xtime(int a) => ((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  static final Uint8List _sbox = () {
    final s = Uint8List(256);
    var p = 1;
    var q = 1;
    int rotl(int x, int n) => ((x << n) | (x >> (8 - n))) & 0xff;
    do {
      p = (p ^ ((p << 1) & 0xff) ^ ((p & 0x80) != 0 ? 0x1b : 0)) & 0xff;
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xff;
      if ((q & 0x80) != 0) q ^= 0x09;
      s[p] =
          (q ^ rotl(q, 1) ^ rotl(q, 2) ^ rotl(q, 3) ^ rotl(q, 4) ^ 0x63) & 0xff;
    } while (p != 1);
    s[0] = 0x63;
    return s;
  }();

  Uint8List block(Uint8List input) {
    var s = Uint8List.fromList(input);
    void addKey(int r) {
      for (var i = 0; i < 16; i++) {
        s[i] ^= _round[r * 16 + i];
      }
    }

    void subShift() {
      final t = Uint8List(16);
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          t[r + 4 * c] = _sbox[s[r + 4 * ((c + r) % 4)]];
        }
      }
      s = t;
    }

    void mix() {
      for (var c = 0; c < 4; c++) {
        final a = [for (var r = 0; r < 4; r++) s[4 * c + r]];
        for (var r = 0; r < 4; r++) {
          s[4 * c + r] =
              _xtime(a[r]) ^
              (_xtime(a[(r + 1) % 4]) ^ a[(r + 1) % 4]) ^
              a[(r + 2) % 4] ^
              a[(r + 3) % 4];
        }
      }
    }

    addKey(0);
    for (var r = 1; r < 14; r++) {
      subShift();
      mix();
      addKey(r);
    }
    subShift();
    addKey(14);
    return s;
  }
}
