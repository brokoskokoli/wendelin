import 'dart:convert';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../../common/chat_wire.dart';
import '../attestation_crypto.dart';
import '../codec.dart';
import '../tls_pin_gate.dart';
import 'ehbp_crypto.dart';

/// Header and size constants of EHBP (SPEC v0.4.1,
/// `tinfoilsh/encrypted-http-body-protocol`).
abstract final class EhbpProtocol {
  /// Request header with the HPKE encapsulated key (hex, 32 bytes).
  static const encapsulatedKeyHeader = 'Ehbp-Encapsulated-Key';

  /// Response header with the response nonce (hex, exactly 32 bytes).
  static const responseNonceHeader = 'ehbp-response-nonce';

  /// Length of the response nonce in bytes.
  static const responseNonceLength = 32;
}

/// The attested key material a request is encrypted to: the key
/// configuration served at `/.well-known/hpke-keys` and the 64 bytes
/// `report_data` of the verified SNP report (TLS pin ‖ HPKE key).
final class EhbpTarget {
  /// Creates a target.
  const EhbpTarget({required this.keyConfig, required this.reportData});

  /// The 41-byte key configuration (RFC 9458 §3).
  final Uint8List keyConfig;

  /// `report_data` of the verified report.
  final Uint8List reportData;
}

/// Hands out [TinfoilEhbpWire]s. Every request is bound to the attested key
/// first (`EhbpCrypto.bindKeyConfig`), and the TLS pin from the same report
/// goes to [tlsPin] before anything is sent. Without a target, with a key
/// that is not the attested one or on any error nothing is sent and there is
/// never a plaintext fallback (K28).
final class TinfoilEhbpCodec implements ChatWireCodec {
  /// Creates the codec. [target] yields the verified key material of the
  /// current attested session, or `null` if there is none.
  TinfoilEhbpCodec({required this.crypto, required this.target, this.tlsPin});

  /// Cipher primitives.
  final EhbpCrypto crypto;

  /// The verified key material, `null` = no valid session.
  final EhbpTarget? Function() target;

  /// Pin state of the enforcing HTTP client (WP61).
  final TlsPinGate? tlsPin;

  @override
  Future<ChatWire> begin({required String model}) async {
    final t = target();
    if (t == null) {
      throw const AttestationFailedException(
        'Kein geprüfter Verschlüsselungsschlüssel des Anbieters, '
        'Anfrage nicht gesendet',
        stage: 'e2ee.key',
      );
    }
    final EhbpBinding binding;
    try {
      binding = crypto.bindKeyConfig(t.keyConfig, t.reportData);
    } on E2eeCryptoException {
      throw const AttestationFailedException(
        'Verschlüsselungsschlüssel gehört nicht zur geprüften Enklave, '
        'Anfrage nicht gesendet',
        stage: 'bind.hpke',
      );
    }
    tlsPin?.expect(AttestCodec.hex(binding.tlsSpkiSha256));
    return TinfoilEhbpWire(crypto: crypto, target: t);
  }
}

/// One encrypted exchange (one HTTP attempt): the whole body goes out as an
/// EHBP stream, the answer bytes are decrypted before the SSE parser.
final class TinfoilEhbpWire implements BytesChatWire {
  /// Starts an exchange.
  TinfoilEhbpWire({required this.crypto, required this.target});

  /// Cipher primitives.
  final EhbpCrypto crypto;

  /// The attested key material.
  final EhbpTarget target;

  EhbpSealed? _sealed;
  EhbpDecoder? _decoder;

  AttestationFailedException _fail(String stage, String message) =>
      AttestationFailedException(message, stage: stage);

  @override
  Map<String, String> get headers {
    final sealed = _sealed;
    if (sealed == null) {
      throw StateError('Header erst nach sealBytes');
    }
    return {
      EhbpProtocol.encapsulatedKeyHeader: AttestCodec.hex(
        sealed.encapsulatedKey,
      ),
    };
  }

  @override
  SealedBody seal(Map<String, Object?> body) =>
      throw UnsupportedError('Binärer Body: sealBytes verwenden');

  @override
  SealedBytes sealBytes(Map<String, Object?> body) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    try {
      _sealed = crypto.beginRequest(target.keyConfig, target.reportData, plain);
    } on E2eeCryptoException {
      throw _fail('e2ee.request', 'Verschlüsselung fehlgeschlagen');
    }
    return SealedBytes(wire: _sealed!.body, plain: plain);
  }

  /// The value of `Ehbp-Response-Nonce`, `null` if the header is missing.
  String? _nonceHeader(Map<String, String> headers) => headers.entries
      .where((e) => e.key.toLowerCase() == EhbpProtocol.responseNonceHeader)
      .map((e) => e.value)
      .firstOrNull;

  /// Derives the decoder from the header value; any problem is a closed
  /// failure (no decoder, nothing falls through as plaintext).
  EhbpDecoder _derive(String? value) {
    final sealed = _sealed;
    if (sealed == null) throw StateError('Antwort vor sealBytes');
    Uint8List? nonce;
    if (value != null && value.length == 2 * EhbpProtocol.responseNonceLength) {
      try {
        nonce = AttestCodec.unhex(value);
      } on FormatException {
        nonce = null;
      }
    }
    if (nonce == null) {
      throw _fail(
        'e2ee.response',
        'Antwort ist nicht verschlüsselt (Ehbp-Response-Nonce fehlt oder '
            'ist ungültig), verworfen',
      );
    }
    try {
      return sealed.session.responseDecoder(nonce);
    } on E2eeCryptoException {
      throw _fail('e2ee.response', 'Antwortschlüssel nicht ableitbar');
    } finally {
      // The request secret is only needed to derive the answer keys.
      sealed.session.dispose();
    }
  }

  /// A successful answer must carry `Ehbp-Response-Nonce` (exactly 32 bytes
  /// of hex); without it the body is not encrypted and is refused.
  @override
  void checkHead(Map<String, String> headers) {
    if (_sealed == null) throw StateError('checkHead vor sealBytes');
    _decoder = _derive(_nonceHeader(headers));
  }

  @override
  Stream<List<int>> openBody(Stream<List<int>> raw) {
    final decoder = _decoder;
    if (decoder == null) {
      throw _fail('e2ee.response', 'Antwort ohne geprüften Kopf, verworfen');
    }
    return _decrypt(decoder, raw);
  }

  /// Error answers: with a response nonce (SPEC §5.1/5.2) they are
  /// encrypted like successful ones and a violation is a closed failure.
  /// Without one (§5.3) the body is unauthenticated: only a shortened
  /// diagnostic marked as such is returned.
  @override
  Stream<List<int>> openErrorBody(
    Map<String, String> headers,
    Stream<List<int>> raw,
  ) async* {
    final value = _nonceHeader(headers);
    if (value != null) {
      yield* _decrypt(_derive(value), raw);
      return;
    }
    _sealed?.session.dispose();
    final bytes = <int>[];
    await for (final chunk in raw) {
      bytes.addAll(chunk);
      if (bytes.length >= _diagnosticBytes) break;
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.length > _diagnosticChars) {
      text = '${text.substring(0, _diagnosticChars)}…';
    }
    yield utf8.encode('$unauthenticatedBodyPrefix$text');
  }

  static const _diagnosticBytes = 1024;
  static const _diagnosticChars = 200;

  Stream<List<int>> _decrypt(
    EhbpDecoder decoder,
    Stream<List<int>> raw,
  ) async* {
    try {
      await for (final chunk in raw) {
        final plain = decoder.push(
          chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        );
        if (plain.isNotEmpty) yield plain;
      }
      decoder.finish();
    } on E2eeCryptoException {
      throw _fail(
        'e2ee.response',
        'Antwort nicht authentisch oder abgeschnitten, verworfen',
      );
    } finally {
      decoder.dispose();
    }
  }

  /// The events are already plain after [openBody].
  @override
  SseEvent open(SseEvent event) => event;
}
