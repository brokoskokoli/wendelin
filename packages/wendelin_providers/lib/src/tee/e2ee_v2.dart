import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/chat_wire.dart';
import 'attestation_crypto.dart';
import 'attestation_types.dart';
import 'codec.dart';
import 'gateway_documents.dart';

/// Phala/RedPill end-to-end encryption, protocol **v2** (frozen by Phala,
/// retirement planned for 2027-02-10; v3 replaces it). Everything that is
/// specific to the protocol version lives in this file: header names, suite,
/// AAD layout and the list of encrypted fields. The raw cipher is the
/// [AttestationCrypto] port.
///
/// Source: `Dstack-TEE/private-ai-gateway` @ `57477f5d` (`spec/e2ee-v2.md`,
/// `spec/e2ee-v2-test-vectors.md`, server code `src/aci/e2ee.rs` and
/// `src/aggregator/service/e2ee_crypto.rs`); the same notes are in
/// `docs/notes/wp62-phala-e2ee-spec.md`.
///
/// What it encrypts and what not (spec §Feldliste): every string
/// `messages[].content` (or each `text`, `image_url.url` and
/// `input_audio.data` part of an array content) and, in the response, the
/// `content`, `reasoning` and `reasoning_content` of every delta. **Not
/// encrypted** (so they only have the pinned TLS of WP61): `tools`,
/// `tool_choice`, `messages[].tool_calls` and the `tool_calls` of the answer.
/// The encryption ends in the gateway CVM, not in the model TEE.
abstract final class E2eeProtocolV2 {
  /// `X-E2EE-Version`.
  static const version = '2';

  /// The suite (`algo` of the keyset entry) the client speaks.
  static const algo = 'x25519-aes-256-gcm-hkdf-sha256';

  /// `purpose` in the AAD of request fields.
  static const requestPurpose = 'aci.e2ee.request.v2';

  /// `purpose` in the AAD of response fields.
  static const responsePurpose = 'aci.e2ee.response.v2';

  /// The service accepts timestamps within this many seconds of its clock.
  static const maxClockSkewSeconds = 300;

  /// The key of the suite in [keys], chosen by `algo` (never by `key_id`).
  static E2eeKey? selectKey(Iterable<KeysetKey> keys) {
    for (final k in keys) {
      if (k.algo != algo) continue;
      try {
        final bytes = AttestCodec.unhex(
          k.publicKey.startsWith('0x') ? k.publicKey.substring(2) : k.publicKey,
        );
        if (bytes.length == 32) {
          return E2eeKey(keyId: k.keyId, algo: k.algo, publicKey: bytes);
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// AAD (RFC 8785 JSON) of a request [field].
  static Uint8List requestAad({
    required String field,
    required String model,
    required String nonce,
    required int ts,
  }) => AttestCodec.jcsBytes({
    'algo': algo,
    'field': field,
    'model': model,
    'nonce': nonce,
    'purpose': requestPurpose,
    'ts': ts,
  });

  /// AAD of a response [field]; [id] is the `id` of the chunk (or `''`),
  /// [model] the model of the *request*.
  static Uint8List responseAad({
    required String field,
    required String id,
    required String model,
    required String nonce,
    required int ts,
  }) => AttestCodec.jcsBytes({
    'algo': algo,
    'field': field,
    'id': id,
    'model': model,
    'nonce': nonce,
    'purpose': responsePurpose,
    'ts': ts,
  });

  /// The fields of a delta that are encrypted.
  static const deltaFields = ['content', 'reasoning', 'reasoning_content'];
}

/// Hands out [E2eeV2Wire]s for the attested session of an `AttestedProvider`
/// (WP62): every request gets fresh keys, nonce and timestamp. Without a
/// valid session or with an expired keyset nothing is sent (fail-closed).
final class PhalaE2eeChannel implements ChatWireCodec {
  /// Creates the channel; [randomBytes] only for tests.
  PhalaE2eeChannel({required this.crypto, Uint8List Function(int)? randomBytes})
    : _random = randomBytes ?? _secureRandom;

  /// Cipher primitives.
  final AttestationCrypto crypto;

  final Uint8List Function(int) _random;
  AttestedSession? Function()? _session;
  Clock? _clock;

  static final _secure = Random.secure();
  static Uint8List _secureRandom(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _secure.nextInt(256)));

  /// Whether an `AttestedProvider` has taken this channel.
  bool get bound => _session != null;

  /// Called by the `AttestedProvider`: where the current session comes from.
  void bind(AttestedSession? Function() session, Clock clock) {
    if (_session != null) {
      throw StateError('PhalaE2eeChannel ist schon an einen Anbieter gebunden');
    }
    _session = session;
    _clock = clock;
  }

  @override
  Future<ChatWire> begin({required String model}) async {
    final session = _session?.call();
    final key = session?.e2eeKey;
    final now = _clock?.now();
    if (session == null || key == null || now == null) {
      throw const AttestationFailedException(
        'Kein geprüfter Verschlüsselungsschlüssel des Anbieters, '
        'Anfrage nicht gesendet',
        stage: 'e2ee.key',
      );
    }
    if (!now.isBefore(session.notAfter)) {
      throw const AttestationFailedException(
        'Schlüssel des Anbieters abgelaufen, Anfrage nicht gesendet',
        stage: 'e2ee.key',
      );
    }
    return E2eeV2Wire(
      crypto: crypto,
      key: key,
      model: model,
      timestamp: now.millisecondsSinceEpoch ~/ 1000,
      nonce: AttestCodec.hex(_random(32)),
      keysetDigest: session.keysetDigest,
    );
  }
}

/// One encrypted exchange of protocol v2 (one HTTP attempt).
final class E2eeV2Wire implements ChatWire {
  /// Starts an exchange; generates the client key pair for the answer.
  E2eeV2Wire({
    required this.crypto,
    required this.key,
    required this.model,
    required this.timestamp,
    required this.nonce,
    this.keysetDigest,
  }) : _client = crypto.e2eeGenerateKeypair();

  /// Cipher primitives.
  final AttestationCrypto crypto;

  /// The attested service key.
  final E2eeKey key;

  /// The `model` of the request, byte for byte (part of every AAD).
  final String model;

  /// `X-E2EE-Timestamp` (Unix seconds).
  final int timestamp;

  /// `X-E2EE-Nonce`: 64 lower-case hex characters, fresh per request.
  final String nonce;

  /// Digest of the attested keyset; a response naming another one means the
  /// provider rolled its keys.
  final String? keysetDigest;

  final E2eeKeypair _client;

  @override
  Map<String, String> get headers => {
    'X-E2EE-Version': E2eeProtocolV2.version,
    'X-Client-Pub-Key': AttestCodec.hex(_client.public),
    'X-Model-Pub-Key': AttestCodec.hex(key.publicKey),
    'X-E2EE-Nonce': nonce,
    'X-E2EE-Timestamp': '$timestamp',
  };

  AttestationFailedException _fail(String stage, String message) =>
      AttestationFailedException(message, stage: stage);

  // --- Request ----------------------------------------------------------

  @override
  SealedBody seal(Map<String, Object?> body) {
    final messages = body['messages'];
    if (messages is! List<Object?> || messages.isEmpty) {
      throw _fail('e2ee.request', 'Anfrage ohne Nachrichten, nicht gesendet');
    }
    final plainMessages = <Object?>[];
    final sealedMessages = <Object?>[];
    for (final (i, m) in messages.indexed) {
      if (m is! Map<String, Object?>) {
        throw _fail('e2ee.request', 'Nachricht unlesbar');
      }
      final (plain, sealed) = _sealMessage(m, i);
      plainMessages.add(plain);
      sealedMessages.add(sealed);
    }
    // The receipt covers what the service decrypted: the body with the
    // structure it restores, in the member order we sent.
    return SealedBody(
      wire: jsonEncode({...body, 'messages': sealedMessages}),
      plain: Uint8List.fromList(
        utf8.encode(jsonEncode({...body, 'messages': plainMessages})),
      ),
    );
  }

  /// The message as the service sees it after decryption and as it goes
  /// over the wire.
  (Map<String, Object?>, Map<String, Object?>) _sealMessage(
    Map<String, Object?> m,
    int i,
  ) {
    final content = m['content'];
    final field = 'messages.$i.content';
    switch (content) {
      case null:
        return (m, m);
      case final String text:
        // The service turns a decrypted content that parses as a JSON array
        // into structured content; such a text is sent as one text part.
        if (_looksLikeJsonArray(text)) {
          return (
            {
              ...m,
              'content': [
                {'type': 'text', 'text': text},
              ],
            },
            {
              ...m,
              'content': [
                {'type': 'text', 'text': _enc('$field.0.text', text)},
              ],
            },
          );
        }
        return (m, {...m, 'content': _enc(field, text)});
      case final List<Object?> parts:
        return (
          m,
          {
            ...m,
            'content': [
              for (final (j, p) in parts.indexed)
                p is Map<String, Object?>
                    ? _sealPart(p, '$field.$j')
                    : throw _fail('e2ee.request', 'Inhaltsteil unlesbar'),
            ],
          },
        );
      default:
        throw _fail('e2ee.request', 'Inhalt der Nachricht unlesbar');
    }
  }

  Map<String, Object?> _sealPart(Map<String, Object?> p, String field) {
    switch (p['type']) {
      case 'text' when p['text'] is String:
        return {...p, 'text': _enc('$field.text', p['text']! as String)};
      case 'image_url' when p['image_url'] is Map<String, Object?>:
        final image = p['image_url']! as Map<String, Object?>;
        if (image['url'] is! String) {
          throw _fail('e2ee.request', 'Bild ohne URL');
        }
        return {
          ...p,
          'image_url': {
            ...image,
            'url': _enc('$field.image_url.url', image['url']! as String),
          },
        };
      case 'input_audio' when p['input_audio'] is Map<String, Object?>:
        final audio = p['input_audio']! as Map<String, Object?>;
        if (audio['data'] is! String) {
          throw _fail('e2ee.request', 'Audio ohne Daten');
        }
        return {
          ...p,
          'input_audio': {
            ...audio,
            'data': _enc('$field.input_audio.data', audio['data']! as String),
          },
        };
      default:
        throw _fail('e2ee.request', 'Inhaltsteil nicht verschlüsselbar');
    }
  }

  static bool _looksLikeJsonArray(String text) {
    if (!text.trimLeft().startsWith('[')) return false;
    try {
      return jsonDecode(text) is List<Object?>;
    } on FormatException {
      return false;
    }
  }

  String _enc(String field, String text) {
    try {
      return crypto.e2eeEncrypt(
        key.publicKey,
        Uint8List.fromList(utf8.encode(text)),
        E2eeProtocolV2.requestAad(
          field: field,
          model: model,
          nonce: nonce,
          ts: timestamp,
        ),
      );
    } on E2eeCryptoException {
      throw _fail('e2ee.request', 'Verschlüsselung fehlgeschlagen');
    }
  }

  // --- Response ---------------------------------------------------------

  @override
  void checkHead(Map<String, String> headers) {
    String? h(String name) => headers[name]?.trim();
    if (h('x-e2ee-applied')?.toLowerCase() != 'true' ||
        h('x-e2ee-version') != E2eeProtocolV2.version ||
        h('x-e2ee-algo') != E2eeProtocolV2.algo) {
      throw _fail(
        'e2ee.response',
        'Antwort des Anbieters ist nicht Ende-zu-Ende-verschlüsselt, '
            'verworfen',
      );
    }
    final digest = h('x-aci-keyset-digest');
    if (digest != null && keysetDigest != null && digest != keysetDigest) {
      throw _fail(
        'e2ee.keyset',
        'Der Anbieter hat seinen Schlüsselsatz gewechselt, neu prüfen',
      );
    }
  }

  @override
  SseEvent open(SseEvent event) {
    if (event.isDone) return event;
    final Object? json;
    try {
      json = jsonDecode(event.data);
    } on FormatException {
      throw _fail('e2ee.response', 'Antwortereignis unlesbar');
    }
    if (json is! Map<String, Object?>) {
      throw _fail('e2ee.response', 'Antwortereignis unlesbar');
    }
    if (json['error'] != null) {
      // Fehlerobjekt im Klartext; nie ungeprüfte choices durchreichen.
      if (!json.containsKey('choices')) return event;
      return SseEvent(
        data: jsonEncode({...json}..remove('choices')),
        event: event.event,
        id: event.id,
      );
    }
    final choices = json['choices'];
    if (choices is! List<Object?>) return event; // e.g. usage chunk
    final id = json['id'] is String ? json['id']! as String : '';
    var changed = false;
    final opened = <Object?>[];
    for (final (position, choice) in choices.indexed) {
      if (choice is! Map<String, Object?> ||
          choice['delta'] is! Map<String, Object?>) {
        opened.add(choice);
        continue;
      }
      final index = choice['index'] is int ? choice['index']! as int : position;
      final delta = {...choice['delta']! as Map<String, Object?>};
      for (final name in E2eeProtocolV2.deltaFields) {
        final value = delta[name];
        if (value == null || value == '') continue;
        if (value is! String) {
          throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt');
        }
        delta[name] = _dec(value, 'choices.$index.delta.$name', id);
        changed = true;
      }
      opened.add({...choice, 'delta': delta});
    }
    if (!changed) return event;
    return SseEvent(
      data: jsonEncode({...json, 'choices': opened}),
      event: event.event,
      id: event.id,
    );
  }

  String _dec(String wire, String field, String id) {
    try {
      final plain = crypto.e2eeDecrypt(
        _client.secret,
        wire,
        E2eeProtocolV2.responseAad(
          field: field,
          id: id,
          model: model,
          nonce: nonce,
          ts: timestamp,
        ),
      );
      return utf8.decode(plain);
    } on E2eeCryptoException {
      throw _fail(
        'e2ee.response',
        'Antwort des Anbieters ließ sich nicht entschlüsseln, verworfen',
      );
    } on FormatException {
      throw _fail(
        'e2ee.response',
        'Antwort des Anbieters ließ sich nicht entschlüsseln, verworfen',
      );
    }
  }
}
