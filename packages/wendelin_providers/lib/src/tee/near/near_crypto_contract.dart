import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../attestation_crypto.dart';
import '../codec.dart';
import 'near_crypto.dart';

/// Server identity of the frozen vector: Ed25519 seed 32 × 0x03 (secret =
/// libsodium's X25519 secret for it).
const _serverEdPublic =
    'ed4928c628d1c2c6eae90338905995612959273a5c63f93636c14614ac8737d1';
const _serverX25519Secret =
    '98aebbb178a551876bfaf8e1e530dac6aaf6c2ea1c8f8406a3ab37dfb40fbc65';

/// Made with PyNaCl/libsodium + `cryptography` (ephemeral seed 32 × 0x07,
/// nonce 24 × 0x09, plaintext `Hallo Wendelin`), identical to
/// `native/attest/tests/near_e2ee_vector.txt`.
const _frozenWire =
    '13be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d'
    '09090909090909090909090909090909090909090909090982755ea61f78d221'
    '23854dfc6ef13c545297ec07efa51ff1cae7d5ea9009';

/// Contract of [NearCrypto]: every implementation (Rust, reference) must
/// pass it; the vector was made by an independent implementation.
void nearCryptoContract(NearCrypto Function() create, {required String name}) {
  group('NearCrypto $name', () {
    late NearCrypto crypto;
    setUp(() => crypto = create());

    Uint8List u(String s) => Uint8List.fromList(utf8.encode(s));

    test('opens the independently made frozen vector', () {
      final plain = crypto.nearDecrypt(
        AttestCodec.unhex(_serverX25519Secret),
        _frozenWire,
      );
      expect(utf8.decode(plain), 'Hallo Wendelin');
    });

    test(
      'round trip with a fresh identity, lower-case hex, fresh each time',
      () {
        final id = crypto.nearGenerateIdentity();
        expect(id.public, hasLength(32));
        expect(id.secret, hasLength(32));
        for (final text in ['', 'Hallo Wörld', 'x' * 5000]) {
          final wire = crypto.nearEncrypt(id.public, u(text));
          expect(wire, matches(RegExp(r'^[0-9a-f]+$')));
          expect(wire.length, 2 * (72 + utf8.encode(text).length));
          expect(utf8.decode(crypto.nearDecrypt(id.secret, wire)), text);
        }
        expect(
          crypto.nearEncrypt(id.public, u('x')),
          isNot(crypto.nearEncrypt(id.public, u('x'))),
        );
      },
    );

    test('encrypts to the libsodium conversion of the Ed25519 key', () {
      final wire = crypto.nearEncrypt(
        AttestCodec.unhex(_serverEdPublic),
        u('ok'),
      );
      expect(
        utf8.decode(
          crypto.nearDecrypt(AttestCodec.unhex(_serverX25519Secret), wire),
        ),
        'ok',
      );
    });

    test('wrong key, flipped bits and truncation fail without details', () {
      final id = crypto.nearGenerateIdentity();
      final other = crypto.nearGenerateIdentity();
      final wire = crypto.nearEncrypt(id.public, u('geheim'));
      expect(
        () => crypto.nearDecrypt(other.secret, wire),
        throwsA(isA<E2eeCryptoException>()),
      );
      final bytes = AttestCodec.unhex(wire);
      for (final pos in [0, 40, bytes.length - 1]) {
        final bad = Uint8List.fromList(bytes)..[pos] ^= 1;
        expect(
          () => crypto.nearDecrypt(id.secret, AttestCodec.hex(bad)),
          throwsA(isA<E2eeCryptoException>()),
          reason: 'byte $pos',
        );
      }
      expect(
        () => crypto.nearDecrypt(id.secret, wire.substring(0, wire.length - 2)),
        throwsA(isA<E2eeCryptoException>()),
      );
    });

    test('malformed input and low-order recipients are errors', () {
      final id = crypto.nearGenerateIdentity();
      for (final bad in ['zz', 'abcd', '00' * 80]) {
        expect(
          () => crypto.nearDecrypt(id.secret, bad),
          throwsA(isA<E2eeCryptoException>()),
        );
      }
      expect(
        () => crypto.nearEncrypt(Uint8List(5), u('x')),
        throwsA(isA<E2eeCryptoException>()),
      );
      expect(
        () => crypto.nearEncrypt(Uint8List(32)..[0] = 1, u('x')),
        throwsA(isA<E2eeCryptoException>()),
      );
    });
  });
}
