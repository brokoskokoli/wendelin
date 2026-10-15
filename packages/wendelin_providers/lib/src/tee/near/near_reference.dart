import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../attestation_crypto.dart';
import '../e2ee_reference.dart';
import 'near_crypto.dart';

/// Slow, plain-Dart [NearCrypto] for tests, fakes and demo mode, byte
/// compatible with the Rust module (the contract suite proves it with a
/// vector made by PyNaCl/libsodium). **Not for production**: not
/// constant-time.
final class NearReferenceCrypto implements NearCrypto {
  /// Creates the reference; [random] only for tests.
  NearReferenceCrypto({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static final _p = (BigInt.one << 255) - BigInt.from(19);
  static final _mask32 = 0xffffffff;

  Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  @override
  NearIdentity nearGenerateIdentity() => identityFromSeed(_bytes(32));

  /// The identity of an Ed25519 [seed].
  static NearIdentity identityFromSeed(Uint8List seed) {
    final secret =
        Uint8List.fromList(crypto.sha512.convert(seed).bytes.sublist(0, 32))
          ..[0] &= 248
          ..[31] &= 127
          ..[31] |= 64;
    // The Ed25519 public key needs point multiplication on the twisted
    // Edwards curve; the reference derives it from the X25519 public key
    // by the inverse map only when asked (see [edPublicFromSeed]).
    return NearIdentity(secret: secret, public: edPublicFromSeed(seed));
  }

  /// Ed25519 public key of [seed] (RFC 8032, BigInt).
  static Uint8List edPublicFromSeed(Uint8List seed) {
    final h = crypto.sha512.convert(seed).bytes;
    final a = Uint8List.fromList(h.sublist(0, 32))
      ..[0] &= 248
      ..[31] &= 127
      ..[31] |= 64;
    var k = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      k = (k << 8) | BigInt.from(a[i]);
    }
    final point = _mulBase(k);
    return _encodePoint(point);
  }

  // --- Ed25519 points (extended coordinates are not needed: affine, slow) ---

  static final _d = (BigInt.from(-121665) * _inv(BigInt.from(121666))) % _p;
  static BigInt _inv(BigInt x) => x.modPow(_p - BigInt.two, _p);

  static final _bx = BigInt.parse(
    '15112221349535400772501151409588531511454012693041857206046113283949847762202',
  );
  static final _by = BigInt.parse(
    '46316835694926478169428394003475163141307993866256225615783033603165251855960',
  );

  static (BigInt, BigInt) _add((BigInt, BigInt) p, (BigInt, BigInt) q) {
    final (x1, y1) = p;
    final (x2, y2) = q;
    final t = _d * x1 * x2 * y1 * y2 % _p;
    final x = (x1 * y2 + x2 * y1) * _inv(BigInt.one + t) % _p;
    final y = (y1 * y2 + x1 * x2) * _inv(BigInt.one - t) % _p;
    return (x, y);
  }

  static (BigInt, BigInt) _mulBase(BigInt k) {
    var result = (BigInt.zero, BigInt.one);
    var addend = (_bx, _by);
    var n = k;
    while (n > BigInt.zero) {
      if ((n & BigInt.one) == BigInt.one) result = _add(result, addend);
      addend = _add(addend, addend);
      n >>= 1;
    }
    return result;
  }

  static Uint8List _encodePoint((BigInt, BigInt) p) {
    final (x, y) = p;
    final out = Uint8List(32);
    var v = y;
    for (var i = 0; i < 32; i++) {
      out[i] = (v & BigInt.from(255)).toInt();
      v >>= 8;
    }
    if (x.isOdd) out[31] |= 0x80;
    return out;
  }

  /// X25519 public key for an Ed25519 public key: `u = (1 + y) / (1 - y)`.
  static Uint8List edToX25519(Uint8List ed) {
    if (ed.length != 32) {
      throw const E2eeCryptoException('Empfängerschlüssel: 32 Byte erwartet');
    }
    var y = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(i == 31 ? ed[i] & 0x7f : ed[i]);
    }
    final denom = (BigInt.one - y) % _p;
    if (denom == BigInt.zero) {
      throw const E2eeCryptoException('Empfängerschlüssel ungültig');
    }
    var u = (BigInt.one + y) * _inv(denom) % _p;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (u & BigInt.from(255)).toInt();
      u >>= 8;
    }
    return out;
  }

  @override
  String nearEncrypt(Uint8List recipientEd25519, Uint8List plaintext) =>
      encryptWith(recipientEd25519, _bytes(32), _bytes(24), plaintext);

  /// Encrypts with a fixed ephemeral seed and nonce (test vectors).
  static String encryptWith(
    Uint8List recipientEd25519,
    Uint8List ephSeed,
    Uint8List nonce,
    Uint8List plaintext,
  ) {
    final peer = edToX25519(recipientEd25519);
    final basepoint = Uint8List(32)..[0] = 9;
    final ephPublic = E2eeReference.x25519(ephSeed, basepoint);
    final key = _key(ephSeed, peer);
    final sealed = _seal(key, nonce, plaintext);
    return _hex([...ephPublic, ...nonce, ...sealed]);
  }

  @override
  Uint8List nearDecrypt(Uint8List secret, String wireHex) {
    final text = wireHex.startsWith('0x') ? wireHex.substring(2) : wireHex;
    if (text.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(text)) {
      throw const E2eeCryptoException('Chiffre ist kein Hex');
    }
    final wire = Uint8List.fromList([
      for (var i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ]);
    if (wire.length < 32 + 24 + 16) {
      throw const E2eeCryptoException('Chiffre zu kurz');
    }
    if (secret.length != 32) {
      throw const E2eeCryptoException('Privatschlüssel: 32 Byte erwartet');
    }
    final key = _key(secret, Uint8List.sublistView(wire, 0, 32));
    return _open(
      key,
      Uint8List.sublistView(wire, 32, 56),
      Uint8List.sublistView(wire, 56),
    );
  }

  static String _hex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _key(Uint8List secret, Uint8List peer) {
    final shared = E2eeReference.x25519(secret, peer);
    if (shared.every((b) => b == 0)) {
      throw const E2eeCryptoException('Schlüsselvereinbarung ungültig');
    }
    final prk = crypto.Hmac(crypto.sha256, Uint8List(32)).convert(shared).bytes;
    return Uint8List.fromList(
      crypto.Hmac(
        crypto.sha256,
        prk,
      ).convert([...'ed25519_encryption'.codeUnits, 1]).bytes,
    );
  }

  // --- XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha, RFC 8439) ---------------

  static int _rotl(int v, int n) => ((v << n) | (v >> (32 - n))) & _mask32;

  static void _quarter(List<int> s, int a, int b, int c, int d) {
    s[a] = (s[a] + s[b]) & _mask32;
    s[d] = _rotl(s[d] ^ s[a], 16);
    s[c] = (s[c] + s[d]) & _mask32;
    s[b] = _rotl(s[b] ^ s[c], 12);
    s[a] = (s[a] + s[b]) & _mask32;
    s[d] = _rotl(s[d] ^ s[a], 8);
    s[c] = (s[c] + s[d]) & _mask32;
    s[b] = _rotl(s[b] ^ s[c], 7);
  }

  static List<int> _initState(Uint8List key, int counter, Uint8List n12) {
    int le(List<int> b, int o) =>
        b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
    return [
      0x61707865, 0x3320646e, 0x79622d32, 0x6b206574, //
      for (var i = 0; i < 8; i++) le(key, 4 * i),
      counter,
      le(n12, 0), le(n12, 4), le(n12, 8),
    ];
  }

  static void _rounds(List<int> s) {
    for (var i = 0; i < 10; i++) {
      _quarter(s, 0, 4, 8, 12);
      _quarter(s, 1, 5, 9, 13);
      _quarter(s, 2, 6, 10, 14);
      _quarter(s, 3, 7, 11, 15);
      _quarter(s, 0, 5, 10, 15);
      _quarter(s, 1, 6, 11, 12);
      _quarter(s, 2, 7, 8, 13);
      _quarter(s, 3, 4, 9, 14);
    }
  }

  static Uint8List _block(Uint8List key, int counter, Uint8List n12) {
    final init = _initState(key, counter, n12);
    final s = List<int>.of(init);
    _rounds(s);
    final out = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      final v = (s[i] + init[i]) & _mask32;
      out[4 * i] = v & 0xff;
      out[4 * i + 1] = (v >> 8) & 0xff;
      out[4 * i + 2] = (v >> 16) & 0xff;
      out[4 * i + 3] = (v >> 24) & 0xff;
    }
    return out;
  }

  static Uint8List _hchacha(Uint8List key, Uint8List n16) {
    int le(List<int> b, int o) =>
        b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
    final s = <int>[
      0x61707865, 0x3320646e, 0x79622d32, 0x6b206574, //
      for (var i = 0; i < 8; i++) le(key, 4 * i),
      for (var i = 0; i < 4; i++) le(n16, 4 * i),
    ];
    _rounds(s);
    final out = Uint8List(32);
    final words = [...s.sublist(0, 4), ...s.sublist(12, 16)];
    for (var i = 0; i < 8; i++) {
      out[4 * i] = words[i] & 0xff;
      out[4 * i + 1] = (words[i] >> 8) & 0xff;
      out[4 * i + 2] = (words[i] >> 16) & 0xff;
      out[4 * i + 3] = (words[i] >> 24) & 0xff;
    }
    return out;
  }

  static Uint8List _xor(Uint8List key, Uint8List n12, Uint8List data) {
    final out = Uint8List(data.length);
    for (var off = 0; off < data.length; off += 64) {
      final ks = _block(key, 1 + off ~/ 64, n12);
      for (var i = 0; i < 64 && off + i < data.length; i++) {
        out[off + i] = data[off + i] ^ ks[i];
      }
    }
    return out;
  }

  static BigInt _leBig(List<int> b) {
    var r = BigInt.zero;
    for (var i = b.length - 1; i >= 0; i--) {
      r = (r << 8) | BigInt.from(b[i]);
    }
    return r;
  }

  static Uint8List _poly1305(Uint8List key32, List<int> msg) {
    final r =
        _leBig(key32.sublist(0, 16)) &
        BigInt.parse('0ffffffc0ffffffc0ffffffc0fffffff', radix: 16);
    final s = _leBig(key32.sublist(16));
    final prime = (BigInt.one << 130) - BigInt.from(5);
    var acc = BigInt.zero;
    for (var i = 0; i < msg.length; i += 16) {
      final end = min(i + 16, msg.length);
      final chunk = [...msg.sublist(i, end), 1];
      acc = (acc + _leBig(chunk)) * r % prime;
    }
    var tag = (acc + s) & ((BigInt.one << 128) - BigInt.one);
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = (tag & BigInt.from(255)).toInt();
      tag >>= 8;
    }
    return out;
  }

  static List<int> _macData(Uint8List ct) {
    final pad = (16 - ct.length % 16) % 16;
    final lens = ByteData(16)..setUint64(8, ct.length, Endian.little);
    return [...ct, ...List.filled(pad, 0), ...lens.buffer.asUint8List()];
  }

  static (Uint8List, Uint8List) _subkeyAndNonce(Uint8List key, Uint8List n24) {
    final sub = _hchacha(key, Uint8List.sublistView(n24, 0, 16));
    final n12 = Uint8List(12)..setRange(4, 12, n24.sublist(16));
    return (sub, n12);
  }

  static Uint8List _seal(Uint8List key, Uint8List n24, Uint8List pt) {
    final (sub, n12) = _subkeyAndNonce(key, n24);
    final polyKey = _block(sub, 0, n12).sublist(0, 32);
    final ct = _xor(sub, n12, pt);
    final tag = _poly1305(Uint8List.fromList(polyKey), _macData(ct));
    return Uint8List.fromList([...ct, ...tag]);
  }

  static Uint8List _open(Uint8List key, Uint8List n24, Uint8List sealed) {
    const fail = E2eeCryptoException('Entschlüsselung fehlgeschlagen');
    if (sealed.length < 16) throw fail;
    final (sub, n12) = _subkeyAndNonce(key, n24);
    final ct = Uint8List.sublistView(sealed, 0, sealed.length - 16);
    final polyKey = _block(sub, 0, n12).sublist(0, 32);
    final tag = _poly1305(Uint8List.fromList(polyKey), _macData(ct));
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ sealed[sealed.length - 16 + i];
    }
    if (diff != 0) throw fail;
    return _xor(sub, n12, ct);
  }
}
