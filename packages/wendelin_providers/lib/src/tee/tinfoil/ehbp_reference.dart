import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../attestation_crypto.dart';
import '../e2ee_reference.dart';
import 'ehbp_crypto.dart';

/// Slow, plain-Dart [EhbpCrypto] for tests, fakes and demo mode, byte
/// compatible with the Rust module (`native/attest/src/ehbp.rs`): RFC 9180
/// HPKE (mode base, DHKEM(X25519), HKDF-SHA256, AES-256-GCM) with info
/// `ehbp request`, plus the response side. The contract suite proves the
/// HPKE part with a vector of the CFRG test-vector set and the response part
/// with the vectors of the protocol reference. **Not for production**: not
/// constant-time.
final class EhbpReferenceCrypto implements EhbpCrypto {
  /// Creates the reference; [random] and [ephemeralSecret] only for tests.
  EhbpReferenceCrypto({Random? random, this.ephemeralSecret})
    : _random = random ?? Random.secure();

  final Random _random;

  /// Fixed ephemeral X25519 secret (test vectors); random if `null`.
  final Uint8List? ephemeralSecret;

  static const _frame = 64 * 1024;
  static const _kem = [0x00, 0x20];
  static const _suite = [0x00, 0x20, 0x00, 0x01, 0x00, 0x02];

  static Uint8List _cat(List<List<int>> parts) =>
      Uint8List.fromList([for (final p in parts) ...p]);

  static Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

  static Uint8List _expand(List<int> prk, List<int> info, int length) {
    final out = BytesBuilder();
    var t = <int>[];
    for (var i = 1; out.length < length; i++) {
      t = _hmac(prk, [...t, ...info, i]);
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  static List<int> _label(List<int> suiteId, String label) => [
    ...'HPKE-v1'.codeUnits,
    ...suiteId,
    ...label.codeUnits,
  ];

  static Uint8List _lExtract(
    List<int> suiteId,
    List<int> salt,
    String label,
    List<int> ikm,
  ) => _hmac(salt.isEmpty ? Uint8List(32) : salt, [
    ..._label(suiteId, label),
    ...ikm,
  ]);

  static Uint8List _lExpand(
    List<int> suiteId,
    List<int> prk,
    String label,
    List<int> info,
    int length,
  ) => _expand(prk, [
    (length >> 8) & 0xff,
    length & 0xff,
    ..._label(suiteId, label),
    ...info,
  ], length);

  /// The X25519 public key of [secret].
  static Uint8List publicKey(Uint8List secret) =>
      E2eeReference.keypairFromSeed(secret).public;

  /// The HPKE sender context for [serverPublic] with the ephemeral
  /// [secret]; exposed for the contract suite.
  static EhbpSenderContext setupSender(
    Uint8List serverPublic,
    Uint8List secret,
    List<int> info,
  ) {
    final enc = publicKey(secret);
    final dh = E2eeReference.x25519(secret, serverPublic);
    return _schedule(dh, _cat([enc, serverPublic]), enc, info);
  }

  /// The HPKE receiver context (server side, tests).
  static EhbpSenderContext setupReceiver(
    Uint8List serverSecret,
    Uint8List enc,
    List<int> info,
  ) {
    final dh = E2eeReference.x25519(serverSecret, enc);
    return _schedule(dh, _cat([enc, publicKey(serverSecret)]), enc, info);
  }

  static EhbpSenderContext _schedule(
    Uint8List dh,
    Uint8List kemContext,
    Uint8List enc,
    List<int> info,
  ) {
    if (dh.every((b) => b == 0)) {
      throw const E2eeCryptoException('Schlüsselvereinbarung ungültig');
    }
    final kemId = [...'KEM'.codeUnits, ..._kem];
    final eae = _lExtract(kemId, const [], 'eae_prk', dh);
    final shared = _lExpand(kemId, eae, 'shared_secret', kemContext, 32);
    final id = [...'HPKE'.codeUnits, ..._suite];
    final pskIdHash = _lExtract(id, const [], 'psk_id_hash', const []);
    final infoHash = _lExtract(id, const [], 'info_hash', info);
    final context = _cat([
      [0],
      pskIdHash,
      infoHash,
    ]);
    final secret = _lExtract(id, shared, 'secret', const []);
    return EhbpSenderContext._(
      enc: enc,
      key: _lExpand(id, secret, 'key', context, 32),
      baseNonce: _lExpand(id, secret, 'base_nonce', context, 12),
      exporterSecret: _lExpand(id, secret, 'exp', context, 32),
      sharedSecret: shared,
    );
  }

  @override
  EhbpBinding bindKeyConfig(Uint8List keyConfig, Uint8List reportData) {
    final pk = parseKeyConfig(keyConfig);
    if (reportData.length != 64) {
      throw const E2eeCryptoException('report_data muss 64 Byte haben');
    }
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= pk[i] ^ reportData[32 + i];
    }
    if (diff != 0) {
      throw const E2eeCryptoException(
        'HPKE-Schlüssel gehört nicht zum attestierten Report',
      );
    }
    return EhbpBinding(tlsSpkiSha256: reportData.sublist(0, 32));
  }

  /// The server key of a 41-byte key configuration; throws unless it is
  /// exactly `key_id 0 / X25519 / HKDF-SHA256 / AES-256-GCM`.
  static Uint8List parseKeyConfig(Uint8List cfg) {
    const ok = [0, 0, 0x20];
    const suites = [0, 4, 0, 1, 0, 2];
    if (cfg.length != 41 ||
        !_eq(cfg.sublist(0, 3), ok) ||
        !_eq(cfg.sublist(35), suites)) {
      throw const E2eeCryptoException('Schlüsselkonfiguration nicht erlaubt');
    }
    return cfg.sublist(3, 35);
  }

  /// A key configuration for [serverPublic].
  static Uint8List keyConfig(Uint8List serverPublic) => _cat([
    [0, 0, 0x20],
    serverPublic,
    [0, 4, 0, 1, 0, 2],
  ]);

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  EhbpSealed beginRequest(
    Uint8List keyConfig,
    Uint8List reportData,
    Uint8List plaintext,
  ) {
    bindKeyConfig(keyConfig, reportData);
    if (plaintext.isEmpty) {
      throw const E2eeCryptoException('leerer Body wird nicht verschlüsselt');
    }
    final secret =
        ephemeralSecret ??
        Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));
    final ctx = setupSender(
      parseKeyConfig(keyConfig),
      secret,
      'ehbp request'.codeUnits,
    );
    final body = BytesBuilder();
    for (var i = 0; i < plaintext.length; i += _frame) {
      final chunk = plaintext.sublist(i, min(i + _frame, plaintext.length));
      final ct = ctx.seal(chunk, const []);
      body
        ..add(_len(ct.length))
        ..add(ct);
    }
    return EhbpSealed(
      encapsulatedKey: ctx.enc,
      body: body.toBytes(),
      session: _Session(ctx.enc, ctx.export('ehbp response'.codeUnits, 32)),
    );
  }

  static Uint8List _len(int n) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, n);

  /// The decoder of an answer (also used by the fake service to build
  /// answers: same key schedule).
  static EhbpReferenceDecoder decoder(
    Uint8List exportedSecret,
    Uint8List enc,
    Uint8List responseNonce,
  ) => EhbpReferenceDecoder._derive(exportedSecret, enc, responseNonce);
}

final class _Session implements EhbpSession {
  _Session(this._enc, this._secret);
  final Uint8List _enc;
  final Uint8List _secret;

  @override
  EhbpDecoder responseDecoder(Uint8List responseNonce) =>
      EhbpReferenceCrypto.decoder(_secret, _enc, responseNonce);
}

/// An HPKE context with the operations EHBP needs.
final class EhbpSenderContext {
  EhbpSenderContext._({
    required this.enc,
    required this.key,
    required this.baseNonce,
    required this._exporterSecret,
    required this.sharedSecret,
  });

  /// The encapsulated key.
  final Uint8List enc;

  /// The KEM shared secret (contract vector).
  final Uint8List sharedSecret;

  /// The AEAD key (contract vector).
  final Uint8List key;

  /// The base nonce (contract vector).
  final Uint8List baseNonce;
  final Uint8List _exporterSecret;
  int _seq = 0;

  /// Seals with the next sequence number.
  Uint8List seal(Uint8List plaintext, List<int> aad) {
    final nonce = Uint8List.fromList(baseNonce);
    for (var i = 0; i < 8; i++) {
      nonce[11 - i] ^= (_seq >> (8 * i)) & 0xff;
    }
    _seq++;
    return E2eeReference.aesGcm(
      key,
      nonce,
      plaintext,
      Uint8List.fromList(aad),
      encrypt: true,
    );
  }

  /// Opens with the next sequence number (receiver side).
  Uint8List open(Uint8List ciphertext, List<int> aad) {
    final nonce = Uint8List.fromList(baseNonce);
    for (var i = 0; i < 8; i++) {
      nonce[11 - i] ^= (_seq >> (8 * i)) & 0xff;
    }
    final out = E2eeReference.aesGcm(
      key,
      nonce,
      ciphertext,
      Uint8List.fromList(aad),
      encrypt: false,
    );
    _seq++;
    return out;
  }

  /// RFC 9180 `Export`.
  Uint8List export(List<int> context, int length) =>
      EhbpReferenceCrypto._lExpand(
        [...'HPKE'.codeUnits, ...EhbpReferenceCrypto._suite],
        _exporterSecret,
        'sec',
        context,
        length,
      );
}

/// Response keys and frame decoder (SPEC §4.3, §4.4.1), plain Dart.
final class EhbpReferenceDecoder implements EhbpDecoder {
  EhbpReferenceDecoder._(this.key, this.nonceBase);

  factory EhbpReferenceDecoder._derive(
    Uint8List secret,
    Uint8List enc,
    Uint8List nonce,
  ) {
    if (secret.length != 32 || enc.length != 32 || nonce.length != 32) {
      throw const E2eeCryptoException('Längen von Secret, enc oder Nonce');
    }
    final prk = EhbpReferenceCrypto._hmac([...enc, ...nonce], secret);
    return EhbpReferenceDecoder._(
      EhbpReferenceCrypto._expand(prk, 'key'.codeUnits, 32),
      EhbpReferenceCrypto._expand(prk, 'nonce'.codeUnits, 12),
    );
  }

  /// Response AEAD key (contract vector).
  final Uint8List key;

  /// Response base nonce (contract vector).
  final Uint8List nonceBase;

  static const _maxChunk = 64 * 1024 * 1024;
  final _buf = BytesBuilder();
  Uint8List _pending = Uint8List(0);
  int _seq = 0;
  bool _failed = false;
  bool _finished = false;

  /// The nonce of sequence number [seq] (base XOR counter).
  Uint8List nonceFor(int seq) {
    final n = Uint8List.fromList(nonceBase);
    for (var i = 0; i < 8; i++) {
      n[11 - i] ^= (seq >> (8 * i)) & 0xff;
    }
    return n;
  }

  Never _fail(String code) {
    _failed = true;
    _pending = Uint8List(0);
    throw E2eeCryptoException(code);
  }

  @override
  Uint8List push(Uint8List data) {
    if (_failed) throw const E2eeCryptoException('DECODER_FAILED');
    if (_finished) throw const E2eeCryptoException('DECODER_FINISHED');
    _buf.clear();
    _pending = Uint8List.fromList([..._pending, ...data]);
    final out = BytesBuilder();
    var pos = 0;
    while (_pending.length - pos >= 4) {
      final len = _pending.buffer.asByteData().getUint32(pos);
      if (len > _maxChunk) _fail('CHUNK_TOO_LARGE');
      if (len == 0) {
        pos += 4;
        continue;
      }
      if (_pending.length - pos < 4 + len) break;
      final ct = _pending.sublist(pos + 4, pos + 4 + len);
      try {
        out.add(
          E2eeReference.aesGcm(
            key,
            nonceFor(_seq),
            ct,
            Uint8List(0),
            encrypt: false,
          ),
        );
      } on E2eeCryptoException {
        _fail('AEAD_DECRYPT_FAILED');
      }
      _seq++;
      pos += 4 + len;
    }
    _pending = _pending.sublist(pos);
    return out.toBytes();
  }

  @override
  void finish() {
    if (_failed) throw const E2eeCryptoException('DECODER_FAILED');
    if (_pending.isNotEmpty) _fail('FRAMING_TRUNCATED');
    _finished = true;
  }

  /// Seals [plaintext] frames like the server does (fake service).
  Uint8List sealFrames(List<Uint8List> frames, {int firstSeq = 0}) {
    final out = BytesBuilder();
    var seq = firstSeq;
    for (final f in frames) {
      final ct = E2eeReference.aesGcm(
        key,
        nonceFor(seq++),
        f,
        Uint8List(0),
        encrypt: true,
      );
      out
        ..add(EhbpReferenceCrypto._len(ct.length))
        ..add(ct);
    }
    return out.toBytes();
  }
}
