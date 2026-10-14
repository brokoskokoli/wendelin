import 'dart:convert';
import 'dart:typed_data';

import 'attestation_crypto.dart';
import 'codec.dart';
import 'e2ee_reference.dart';
import 'e2ee_v2.dart';

/// The service refuses an E2EE request (HTTP 400 with an OpenAI error whose
/// `type` is [type]).
final class E2eeRejection implements Exception {
  /// Creates the rejection.
  const E2eeRejection(this.type, this.message);

  /// `e2ee_*` error type.
  final String type;

  /// Message.
  final String message;

  /// The body the service answers with.
  String get body => jsonEncode({
    'error': {'type': type, 'message': message},
  });

  @override
  String toString() => 'E2eeRejection($type)';
}

/// The server side of Phala E2EE v2 for tests and device-test fixtures: it
/// decrypts requests like the gateway and encrypts answers to the client key.
/// Real cipher ([E2eeReference]), strict checks of headers, timestamp, nonce
/// replay and of the fields, so a client bug shows up as the error the real
/// service would answer.
final class FakeE2eeService {
  /// Creates a service with its own key (fixed by default).
  FakeE2eeService({E2eeKeypair? key, DateTime Function()? now})
    : key =
          key ??
          E2eeReference.keypairFromSeed(
            Uint8List.fromList(List.filled(32, 0x42)),
          ),
      _now = now ?? DateTime.now;

  /// The service key pair (the public part goes into the keyset).
  final E2eeKeypair key;

  final DateTime Function() _now;
  final Set<String> _seen = {};

  /// Hex of the public key.
  String get publicKeyHex => AttestCodec.hex(key.public);

  /// Opens a request: checks the headers and decrypts [body]. Throws
  /// [E2eeRejection] like the real service.
  FakeE2eeExchange open(Map<String, String> requestHeaders, Uint8List body) {
    final h = {
      for (final e in requestHeaders.entries) e.key.toLowerCase(): e.value,
    };
    String need(String name) =>
        h[name] ??
        (throw E2eeRejection('e2ee_header_missing', 'Header $name fehlt'));
    if (h.containsKey('x-signing-algo')) {
      throw const E2eeRejection(
        'e2ee_invalid_version',
        'X-Signing-Algo ist der Legacy-Pfad',
      );
    }
    if (need('x-e2ee-version') != E2eeProtocolV2.version) {
      throw const E2eeRejection('e2ee_invalid_version', 'Version');
    }
    final nonce = need('x-e2ee-nonce');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce)) {
      throw const E2eeRejection('e2ee_invalid_nonce', 'Nonce');
    }
    final ts = int.tryParse(need('x-e2ee-timestamp'));
    final nowS = _now().millisecondsSinceEpoch ~/ 1000;
    if (ts == null || (nowS - ts).abs() > E2eeProtocolV2.maxClockSkewSeconds) {
      throw const E2eeRejection('e2ee_invalid_timestamp', 'Zeitstempel');
    }
    final Uint8List client;
    try {
      client = AttestCodec.unhex(need('x-client-pub-key'));
    } on FormatException {
      throw const E2eeRejection('e2ee_invalid_public_key', 'Client-Key');
    }
    if (client.length != 32) {
      throw const E2eeRejection('e2ee_invalid_public_key', 'Client-Key');
    }
    if (need('x-model-pub-key').toLowerCase() != publicKeyHex) {
      throw const E2eeRejection('e2ee_model_key_mismatch', 'Modell-Key');
    }
    if (!_seen.add('${AttestCodec.hex(client)}:$nonce')) {
      throw const E2eeRejection('e2ee_replay_detected', 'Nonce schon benutzt');
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    } on Object {
      throw const E2eeRejection('e2ee_decryption_failed', 'Body unlesbar');
    }
    final model = json['model'];
    if (model is! String) {
      throw const E2eeRejection('e2ee_invalid_payload_model', 'model');
    }
    final exchange = FakeE2eeExchange._(this, client, model, nonce, ts);
    exchange.plainBody = exchange._decryptRequest(json);
    exchange.plainBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(exchange.plainBody)),
    );
    return exchange;
  }
}

/// One opened request of [FakeE2eeService] and the means to answer it.
final class FakeE2eeExchange {
  FakeE2eeExchange._(
    this._service,
    this._client,
    this.model,
    this.nonce,
    this.timestamp,
  );

  final FakeE2eeService _service;
  final Uint8List _client;

  /// The request's `model`.
  final String model;

  /// The request's nonce.
  final String nonce;

  /// The request's timestamp.
  final int timestamp;

  /// The decrypted request body (what the real gateway hashes for the
  /// receipt, see [plainBytes]).
  late final Map<String, Object?> plainBody;

  /// Compact serialisation of [plainBody].
  late final Uint8List plainBytes;

  /// Response headers of a properly encrypted answer.
  Map<String, String> get responseHeaders => {
    'x-e2ee-applied': 'true',
    'x-e2ee-version': E2eeProtocolV2.version,
    'x-e2ee-algo': E2eeProtocolV2.algo,
  };

  Map<String, Object?> _decryptRequest(Map<String, Object?> body) {
    final messages = body['messages'];
    if (messages is! List<Object?>) {
      throw const E2eeRejection('e2ee_decryption_failed', 'messages');
    }
    var count = 0;
    String dec(String wire, String field) {
      count++;
      try {
        return utf8.decode(
          E2eeReference.decrypt(
            _service.key.secret,
            wire,
            E2eeProtocolV2.requestAad(
              field: field,
              model: model,
              nonce: nonce,
              ts: timestamp,
            ),
          ),
        );
      } on Object {
        throw E2eeRejection('e2ee_decryption_failed', 'Feld $field');
      }
    }

    final out = <Object?>[];
    for (final (i, m) in messages.indexed) {
      final msg = {...(m! as Map<String, Object?>)};
      final c = msg['content'];
      final field = 'messages.$i.content';
      if (c is String) {
        final text = dec(c, field);
        msg['content'] = text.trimLeft().startsWith('[')
            ? (jsonDecode(text) as List<Object?>)
            : text;
      } else if (c is List<Object?>) {
        msg['content'] = [
          for (final (j, part) in c.indexed)
            _decryptPart(part! as Map<String, Object?>, '$field.$j', dec),
        ];
      }
      out.add(msg);
    }
    if (count == 0) {
      throw const E2eeRejection(
        'e2ee_decryption_failed',
        'nichts entschlüsselt',
      );
    }
    return {...body, 'messages': out};
  }

  Map<String, Object?> _decryptPart(
    Map<String, Object?> p,
    String field,
    String Function(String, String) dec,
  ) {
    switch (p['type']) {
      case 'text' when p['text'] is String:
        return {...p, 'text': dec(p['text']! as String, '$field.text')};
      case 'image_url' when p['image_url'] is Map<String, Object?>:
        final i = p['image_url']! as Map<String, Object?>;
        return {
          ...p,
          'image_url': {
            ...i,
            'url': dec(i['url']! as String, '$field.image_url.url'),
          },
        };
      case 'input_audio' when p['input_audio'] is Map<String, Object?>:
        final a = p['input_audio']! as Map<String, Object?>;
        return {
          ...p,
          'input_audio': {
            ...a,
            'data': dec(a['data']! as String, '$field.input_audio.data'),
          },
        };
      default:
        return p;
    }
  }

  /// Encrypts one response field to the client key.
  String encryptField(String field, String id, String text) =>
      E2eeReference.encrypt(
        _client,
        Uint8List.fromList(utf8.encode(text)),
        E2eeProtocolV2.responseAad(
          field: field,
          id: id,
          model: model,
          nonce: nonce,
          ts: timestamp,
        ),
      );

  /// Encrypts the `content`/`reasoning`/`reasoning_content` of every delta of
  /// the plain SSE text [sse] like the real gateway (empty `content` is
  /// removed); everything else is passed on unchanged.
  String sealSse(String sse) {
    final out = StringBuffer();
    for (final line in const LineSplitter().convert(sse)) {
      if (!line.startsWith('data:') || line.trim() == 'data: [DONE]') {
        out.write('$line\n');
        continue;
      }
      final json = jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
      final id = json['id'] as String? ?? '';
      for (final (position, choice)
          in ((json['choices'] as List?) ?? const []).indexed) {
        final c = choice! as Map<String, Object?>;
        final delta = c['delta'];
        if (delta is! Map<String, Object?>) continue;
        final index = c['index'] as int? ?? position;
        for (final name in E2eeProtocolV2.deltaFields) {
          final v = delta[name];
          if (v is! String) continue;
          if (v.isEmpty) {
            delta.remove(name);
          } else {
            delta[name] = encryptField('choices.$index.delta.$name', id, v);
          }
        }
      }
      out.write('data: ${jsonEncode(json)}\n');
    }
    return out.toString();
  }
}
