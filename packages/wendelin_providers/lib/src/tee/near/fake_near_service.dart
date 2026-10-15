import 'dart:convert';
import 'dart:typed_data';

import '../codec.dart';
import 'near_crypto.dart';
import 'near_reference.dart';

/// The service refuses a NEAR E2EE request (HTTP 400, `Decryption failed`).
final class NearRejection implements Exception {
  /// Creates the rejection.
  const NearRejection(this.message);

  /// Message.
  final String message;

  /// The body the service answers with.
  String get body => jsonEncode({
    'error': {'message': message, 'type': 'invalid_request_error'},
  });

  @override
  String toString() => 'NearRejection($message)';
}

/// The server side of the NEAR AI E2EE protocol for tests and device-test
/// fixtures: it decrypts requests like the inference proxy and encrypts
/// answers to the client key. Real cipher ([NearReferenceCrypto]). Unlike the
/// real service (which lets undecryptable fields pass as plaintext) it is
/// **strict**: a field that must be encrypted but is not is rejected, so a
/// client bug shows up as a test failure.
final class FakeNearService {
  /// Creates a service with its own Ed25519 identity (fixed by default).
  FakeNearService({Uint8List? seed})
    : identity = NearReferenceCrypto.identityFromSeed(
        seed ?? Uint8List.fromList(List.filled(32, 0x03)),
      );

  /// The service identity (`public` = Ed25519 key of the attestation).
  final NearIdentity identity;

  final _crypto = NearReferenceCrypto();

  /// Hex of the Ed25519 public key.
  String get publicKeyHex => AttestCodec.hex(identity.public);

  /// Decrypts a request; throws [NearRejection] like the service.
  NearExchange open(Map<String, String> headers, Uint8List body) {
    String? h(String name) => headers.entries
        .where((e) => e.key.toLowerCase() == name.toLowerCase())
        .map((e) => e.value)
        .firstOrNull;
    if (h('X-Signing-Algo') != 'ed25519' ||
        h('X-Encryption-Version') != '2' ||
        h('X-Encrypt-All-Fields') != 'true' ||
        h('X-Model-Pub-Key') != publicKeyHex) {
      throw const NearRejection('Encryption headers missing or wrong');
    }
    final client = h('X-Client-Pub-Key');
    final Uint8List clientKey;
    try {
      clientKey = AttestCodec.unhex(client ?? '');
    } on FormatException {
      throw const NearRejection('Invalid client key');
    }
    if (clientKey.length != 32) throw const NearRejection('Invalid client key');
    final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    String dec(Object? v) {
      if (v is! String || v.isEmpty) {
        throw const NearRejection('Encrypted field missing');
      }
      try {
        return utf8.decode(_crypto.nearDecrypt(identity.secret, v));
      } on Object {
        throw const NearRejection('Decryption failed');
      }
    }

    void decField(Map<String, Object?> o, String k) {
      if (o[k] is String && (o[k]! as String).isNotEmpty) o[k] = dec(o[k]);
    }

    for (final m in (json['messages']! as List<Object?>)) {
      final msg = m! as Map<String, Object?>;
      if (msg['content'] is String && (msg['content']! as String).isNotEmpty) {
        final text = dec(msg['content']);
        Object? parsed;
        try {
          parsed = jsonDecode(text);
        } on FormatException {
          parsed = null;
        }
        msg['content'] = parsed is List<Object?> ? parsed : text;
      }
      for (final c in (msg['tool_calls'] as List<Object?>? ?? const [])) {
        final f =
            (c! as Map<String, Object?>)['function']! as Map<String, Object?>;
        decField(f, 'name');
        decField(f, 'arguments');
      }
      decField(msg, 'name');
    }
    for (final t in (json['tools'] as List<Object?>? ?? const [])) {
      final f =
          (t! as Map<String, Object?>)['function']! as Map<String, Object?>;
      decField(f, 'name');
      decField(f, 'description');
      if (f['parameters'] is! String) {
        throw const NearRejection('Tool parameters not encrypted');
      }
      f['parameters'] = jsonDecode(dec(f['parameters']));
    }
    final choice = json['tool_choice'];
    if (choice is Map<String, Object?>) {
      decField(choice['function']! as Map<String, Object?>, 'name');
    }
    return NearExchange._(this, clientKey, json, utf8.decode(body));
  }
}

/// One decrypted request and the way back.
final class NearExchange {
  NearExchange._(this._service, this._client, this.request, this.wireBody);

  final FakeNearService _service;
  final Uint8List _client;

  /// The decrypted request.
  final Map<String, Object?> request;

  /// The request as it was on the wire.
  final String wireBody;

  String _enc(String s) =>
      _service._crypto.nearEncrypt(_client, Uint8List.fromList(utf8.encode(s)));

  void _sealMessage(Map<String, Object?> msg) {
    for (final k in ['content', 'reasoning', 'reasoning_content', 'refusal']) {
      if (msg[k] case final String s when s.isNotEmpty) msg[k] = _enc(s);
    }
    for (final c in (msg['tool_calls'] as List<Object?>? ?? const [])) {
      final f = (c! as Map<String, Object?>)['function'];
      if (f is Map<String, Object?>) {
        for (final k in ['name', 'arguments']) {
          if (f[k] case final String s when s.isNotEmpty) f[k] = _enc(s);
        }
      }
    }
  }

  /// Encrypts a plain chat-completions JSON ([streaming]: one chunk).
  String sealJson(String plain, {bool streaming = false}) {
    final json = jsonDecode(plain) as Map<String, Object?>;
    for (final c in (json['choices'] as List<Object?>? ?? const [])) {
      final m = (c! as Map<String, Object?>)[streaming ? 'delta' : 'message'];
      if (m is Map<String, Object?>) _sealMessage(m);
    }
    return jsonEncode(json);
  }

  /// Encrypts every `data: {...}` event of a plain SSE body.
  String sealSse(String plain) => plain
      .split('\n')
      .map(
        (l) => l.startsWith('data: {')
            ? 'data: ${sealJson(l.substring(6), streaming: true)}'
            : l,
      )
      .join('\n');
}
