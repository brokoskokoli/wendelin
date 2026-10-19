import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../codec.dart';
import 'ehbp_reference.dart';

/// The server side of EHBP for tests and device-test fixtures: it decrypts
/// requests like the Tinfoil router and encrypts answers with the keys of
/// the protocol. Real cipher ([EhbpReferenceCrypto]); strict: a request
/// that is not a valid EHBP body is rejected.
final class FakeEhbpService {
  /// Creates a service with its own X25519 key (fixed by default).
  FakeEhbpService({Uint8List? secret, Uint8List? tlsPin})
    : secret = secret ?? Uint8List.fromList(List.filled(32, 0x42)),
      tlsSpkiSha256 = tlsPin ?? Uint8List.fromList(List.filled(32, 0x11));

  /// X25519 secret of the service.
  final Uint8List secret;

  /// SHA-256 of the TLS SPKI the service claims.
  final Uint8List tlsSpkiSha256;

  /// X25519 public key.
  Uint8List get publicKey => EhbpReferenceCrypto.publicKey(secret);

  /// What `/.well-known/hpke-keys` serves.
  Uint8List get keyConfig => EhbpReferenceCrypto.keyConfig(publicKey);

  /// The `report_data` an attestation of this service carries.
  Uint8List get reportData =>
      Uint8List.fromList([...tlsSpkiSha256, ...publicKey]);

  /// Decrypts a request; throws [FormatException] if it is not EHBP.
  FakeEhbpExchange open(Map<String, String> headers, Uint8List body) {
    final hex = headers.entries
        .where((e) => e.key.toLowerCase() == 'ehbp-encapsulated-key')
        .map((e) => e.value)
        .firstOrNull;
    if (hex == null) throw const FormatException('Ehbp-Encapsulated-Key fehlt');
    final enc = AttestCodec.unhex(hex);
    final ctx = EhbpReferenceCrypto.setupReceiver(
      secret,
      enc,
      'ehbp request'.codeUnits,
    );
    final plain = BytesBuilder();
    var p = 0;
    final view = ByteData.sublistView(body);
    while (p < body.length) {
      final len = view.getUint32(p);
      if (len == 0) {
        p += 4;
        continue;
      }
      plain.add(ctx.open(body.sublist(p + 4, p + 4 + len), const []));
      p += 4 + len;
    }
    return FakeEhbpExchange._(
      enc,
      ctx.export('ehbp response'.codeUnits, 32),
      plain.toBytes(),
    );
  }
}

/// One decrypted request and the way back.
final class FakeEhbpExchange {
  FakeEhbpExchange._(this._enc, this._secret, this.plainBody);

  final Uint8List _enc;
  final Uint8List _secret;

  /// The decrypted request body.
  final Uint8List plainBody;

  /// The decrypted request as JSON.
  Map<String, Object?> get request =>
      jsonDecode(utf8.decode(plainBody)) as Map<String, Object?>;

  /// An encrypted answer: one frame per element of [frames]; returns the
  /// header value and the wire body.
  ({String nonceHex, Uint8List body}) seal(
    List<Uint8List> frames, {
    Uint8List? nonce,
  }) {
    final n =
        nonce ??
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
    final d = EhbpReferenceCrypto.decoder(_secret, _enc, n);
    return (nonceHex: AttestCodec.hex(n), body: d.sealFrames(frames));
  }

  /// Encrypts [text] (e.g. an SSE body), cut into frames of [frameSize].
  ({String nonceHex, Uint8List body}) sealText(
    String text, {
    int frameSize = 40,
  }) {
    final bytes = utf8.encode(text);
    return seal([
      for (var i = 0; i < bytes.length; i += frameSize)
        Uint8List.fromList(bytes.sublist(i, min(i + frameSize, bytes.length))),
    ]);
  }
}
