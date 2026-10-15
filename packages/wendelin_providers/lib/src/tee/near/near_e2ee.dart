import 'dart:convert';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../../common/chat_wire.dart';
import '../attestation_crypto.dart';
import '../attestation_types.dart';
import '../codec.dart';
import '../session_channel.dart';
import 'near_crypto.dart';

/// NEAR AI Cloud end-to-end encryption (protocol version 2, header
/// `X-Encrypt-All-Fields: true`, ADR 0019). Everything that depends on the
/// protocol lives here: header names, the list of encrypted fields and the
/// response check. The cipher is the [NearCrypto] port.
///
/// Source: `nearai/cloud-api` + `inference-proxy` (`src/encryption.rs`) and
/// the guide `e2ee-chat-completions`; confirmed against the live service on
/// 2026-10-15 (non-streaming and streaming, with tools).
///
/// Encrypted in the request: every non-empty `messages[].content` (arrays and
/// look-alike JSON arrays as one JSON string), `messages[].name`,
/// `messages[].tool_calls[].function.{name,arguments}`,
/// `tools[].function.{name,description,parameters}` and
/// `tool_choice.function.name`. Plaintext stays: roles, ids (`tool_call_id`,
/// `tool_calls[].id`), `model`, parameters. Any other top-level key makes
/// the request fail instead of leaving the device in plaintext.
///
/// In the response `content`, `reasoning`, `reasoning_content`, `refusal`
/// and `tool_calls[].function.{name,arguments}` of every choice must decrypt;
/// a non-empty value that does not is a failure, never passed on. The
/// protocol has no AAD: a chunk cannot be tied to its field or position.
/// The wire therefore adds its own checks (same `id` for the whole answer,
/// no repeated chunk); chunk order stays unprotected (ADR 0019).
abstract final class NearE2eeProtocol {
  /// `X-Encryption-Version`.
  static const version = '2';

  /// `X-Signing-Algo`.
  static const algo = 'ed25519';

  /// Top-level request keys the wire knows how to protect.
  static const knownBodyKeys = {
    'model',
    'messages',
    'tools',
    'tool_choice',
    'max_tokens',
    'max_completion_tokens',
    'temperature',
    'stream',
    'stream_options',
    'reasoning_effort',
    'reasoning',
  };

  /// The E2EE key of an attestation entry: the Ed25519 signing key (hex).
  static E2eeKey? keyOf(String hexKey) {
    try {
      final bytes = AttestCodec.unhex(hexKey);
      if (bytes.length != 32) return null;
      return E2eeKey(keyId: 'model', algo: algo, publicKey: bytes);
    } on FormatException {
      return null;
    }
  }
}

/// Hands out [NearE2eeWire]s for the attested session of an
/// `AttestedProvider`: every request gets a fresh client identity and fresh
/// ephemeral keys per field. Without a valid session, for a model other than
/// the attested one or with an expired session nothing is sent.
final class NearE2eeChannel implements SessionBoundChannel {
  /// Creates the channel.
  NearE2eeChannel({required this.crypto});

  /// Cipher primitives.
  final NearCrypto crypto;

  AttestedSession? Function()? _session;
  Clock? _clock;

  @override
  bool get bound => _session != null;

  @override
  bool get encryptsTools => true;

  @override
  void bind(AttestedSession? Function() session, Clock clock) {
    if (_session != null) {
      throw StateError('NearE2eeChannel ist schon an einen Anbieter gebunden');
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
        'Prüfung des Anbieters abgelaufen, Anfrage nicht gesendet',
        stage: 'e2ee.key',
      );
    }
    if (session.workloadId != model) {
      throw AttestationFailedException(
        'Modell "$model" ist nicht geprüft (geprüft: ${session.workloadId}), '
        'Anfrage nicht gesendet',
        stage: 'e2ee.key',
      );
    }
    return NearE2eeWire(crypto: crypto, key: key);
  }
}

/// One encrypted exchange (one HTTP attempt).
final class NearE2eeWire implements ChatWire {
  /// Starts an exchange; generates the client identity for the answer.
  NearE2eeWire({required this.crypto, required this.key})
    : _client = crypto.nearGenerateIdentity();

  /// Cipher primitives.
  final NearCrypto crypto;

  /// The attested model key (Ed25519).
  final E2eeKey key;

  final NearIdentity _client;
  String? _id;
  final Set<String> _seen = {};

  @override
  Map<String, String> get headers => {
    'X-Signing-Algo': NearE2eeProtocol.algo,
    'X-Client-Pub-Key': AttestCodec.hex(_client.public),
    'X-Model-Pub-Key': AttestCodec.hex(key.publicKey),
    'X-Encryption-Version': NearE2eeProtocol.version,
    'X-Encrypt-All-Fields': 'true',
    'x-no-aliasing': 'true',
  };

  AttestationFailedException _fail(String stage, String message) =>
      AttestationFailedException(message, stage: stage);

  // --- Request ----------------------------------------------------------

  /// Encrypts [body]. The receipt covers the bytes on the wire, so `plain`
  /// equals `wire`.
  @override
  SealedBody seal(Map<String, Object?> body) {
    for (final k in body.keys) {
      if (!NearE2eeProtocol.knownBodyKeys.contains(k)) {
        throw _fail('e2ee.request', 'Anfragefeld "$k" nicht verschlüsselbar');
      }
    }
    final messages = body['messages'];
    if (messages is! List<Object?> || messages.isEmpty) {
      throw _fail('e2ee.request', 'Anfrage ohne Nachrichten, nicht gesendet');
    }
    final sealed = <String, Object?>{
      ...body,
      'messages': [for (final m in messages) _sealMessage(m)],
      if (body['tools'] case final List<Object?> tools)
        'tools': [for (final t in tools) _sealTool(t)],
      if (body['tool_choice'] case final Map<String, Object?> choice)
        'tool_choice': _sealChoice(choice),
    };
    final text = jsonEncode(sealed);
    return SealedBody(wire: text, plain: Uint8List.fromList(utf8.encode(text)));
  }

  Object? _sealMessage(Object? m) {
    if (m is! Map<String, Object?>) {
      throw _fail('e2ee.request', 'Nachricht unlesbar');
    }
    for (final k in m.keys) {
      if (!_knownMessageKeys.contains(k)) {
        throw _fail(
          'e2ee.request',
          'Nachrichtenfeld "$k" nicht verschlüsselbar',
        );
      }
    }
    final out = <String, Object?>{...m};
    final content = m['content'];
    switch (content) {
      case null:
        break;
      case final String text when text.isEmpty:
        break;
      case final String text:
        // The service turns a decrypted content that parses as a JSON array
        // into structured content; such a text goes as a one-part array.
        out['content'] = _enc(
          _looksLikeJsonArray(text)
              ? jsonEncode([
                  {'type': 'text', 'text': text},
                ])
              : text,
        );
      case final List<Object?> parts:
        out['content'] = _enc(jsonEncode(parts));
      default:
        throw _fail('e2ee.request', 'Inhalt der Nachricht unlesbar');
    }
    for (final name in ['name', 'refusal', 'reasoning_content', 'reasoning']) {
      if (m[name] case final String s when s.isNotEmpty) out[name] = _enc(s);
    }
    final calls = m['tool_calls'];
    if (calls is List<Object?>) {
      out['tool_calls'] = [
        for (final c in calls)
          if (c is Map<String, Object?> &&
              c['function'] is Map<String, Object?>)
            {
              ...c,
              'function': _sealFunction(c['function']! as Map<String, Object?>),
            }
          else
            throw _fail('e2ee.request', 'Werkzeugaufruf unlesbar'),
      ];
    } else if (calls != null) {
      throw _fail('e2ee.request', 'Werkzeugaufrufe unlesbar');
    }
    return out;
  }

  /// Message fields the request sealing knows (anything else would go out in
  /// plaintext, so it aborts the request): `function_call` and `audio` are
  /// deliberately missing.
  static const _knownMessageKeys = {
    'role',
    'content',
    'name',
    'refusal',
    'reasoning',
    'reasoning_content',
    'tool_calls',
    'tool_call_id',
  };

  /// Answer message fields that may stay plain (no text); everything else
  /// with a value must have been opened.
  static const _plainAnswerKeys = {
    'role',
    'content',
    'reasoning',
    'reasoning_content',
    'refusal',
    'tool_calls',
  };

  Map<String, Object?> _sealFunction(Map<String, Object?> f) => {
    ...f,
    for (final k in ['name', 'arguments', 'description'])
      if (f[k] case final String s when s.isNotEmpty) k: _enc(s),
  };

  Object? _sealTool(Object? t) {
    if (t is! Map<String, Object?> ||
        t['type'] != 'function' ||
        t['function'] is! Map<String, Object?>) {
      throw _fail('e2ee.request', 'Werkzeugdefinition nicht verschlüsselbar');
    }
    final f = t['function']! as Map<String, Object?>;
    return {
      ...t,
      'function': {
        ..._sealFunction(f),
        if (f.containsKey('parameters'))
          'parameters': _enc(jsonEncode(f['parameters'])),
      },
    };
  }

  Object? _sealChoice(Map<String, Object?> choice) {
    final f = choice['function'];
    if (f is! Map<String, Object?> || f['name'] is! String) {
      throw _fail('e2ee.request', 'tool_choice nicht verschlüsselbar');
    }
    return {
      ...choice,
      'function': {...f, 'name': _enc(f['name']! as String)},
    };
  }

  static bool _looksLikeJsonArray(String text) {
    if (!text.trimLeft().startsWith('[')) return false;
    try {
      return jsonDecode(text) is List<Object?>;
    } on FormatException {
      return false;
    }
  }

  String _enc(String text) {
    try {
      return crypto.nearEncrypt(
        key.publicKey,
        Uint8List.fromList(utf8.encode(text)),
      );
    } on E2eeCryptoException {
      throw _fail('e2ee.request', 'Verschlüsselung fehlgeschlagen');
    }
  }

  // --- Response ---------------------------------------------------------

  /// The service sends no E2EE marker header; the proof is in the fields
  /// (anything that does not decrypt is rejected in [open]).
  @override
  void checkHead(Map<String, String> headers) {}

  @override
  SseEvent open(SseEvent event) {
    if (event.isDone) return event;
    final String data = event.data;
    final opened = openJson(data, streaming: true);
    return identical(opened, data)
        ? event
        : SseEvent(data: opened, event: event.event, id: event.id);
  }

  /// Opens one response JSON (a non-streaming answer or one stream chunk).
  /// Returns [json] itself if nothing in it needed opening.
  String openJson(String json, {bool streaming = false}) {
    final Object? parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      throw _fail('e2ee.response', 'Antwort unlesbar');
    }
    if (parsed is! Map<String, Object?>) {
      throw _fail('e2ee.response', 'Antwort unlesbar');
    }
    if (parsed['error'] != null) {
      // Error object in plaintext; never pass unchecked choices.
      return parsed.containsKey('choices')
          ? jsonEncode({...parsed}..remove('choices'))
          : json;
    }
    final id = parsed['id'];
    if (id is String) {
      if (_id != null && _id != id) {
        throw _fail(
          'e2ee.response',
          'Antwort mit wechselnder Kennung, verworfen',
        );
      }
      _id = id;
    }
    final choices = parsed['choices'];
    if (choices is! List<Object?>) return json; // usage chunk
    final key = streaming ? 'delta' : 'message';
    var changed = false;
    final out = <Object?>[];
    for (final choice in choices) {
      if (choice is! Map<String, Object?>) {
        throw _fail('e2ee.response', 'Antwort unlesbar');
      }
      // A carrier under the other key would bypass opening.
      final other = streaming ? 'message' : 'delta';
      if (choice[other] != null) {
        throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt');
      }
      final msg = choice[key];
      if (msg == null) {
        out.add(choice);
        continue;
      }
      if (msg is! Map<String, Object?>) {
        throw _fail('e2ee.response', 'Antwort unlesbar');
      }
      for (final e in msg.entries) {
        if (!_plainAnswerKeys.contains(e.key) && !_isEmpty(e.value)) {
          throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt');
        }
      }
      final opened = <String, Object?>{...msg};
      for (final name in [
        'content',
        'reasoning',
        'reasoning_content',
        'refusal',
      ]) {
        changed |= _openField(opened, name, parts: name == 'content');
      }
      final calls = msg['tool_calls'];
      if (calls != null) {
        if (calls is! List<Object?>) {
          throw _fail('e2ee.response', 'Werkzeugaufrufe unlesbar');
        }
        opened['tool_calls'] = [
          for (final c in calls)
            if (c is Map<String, Object?>)
              _openCall(c)
            else
              throw _fail('e2ee.response', 'Werkzeugaufruf unlesbar'),
        ];
        changed = true;
      }
      if (msg['function_call'] != null || msg['audio'] != null) {
        throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt');
      }
      out.add({...choice, key: opened});
    }
    return changed ? jsonEncode({...parsed, 'choices': out}) : json;
  }

  static bool _isEmpty(Object? v) =>
      v == null ||
      v == '' ||
      (v is List && v.isEmpty) ||
      (v is Map && v.isEmpty);

  Map<String, Object?> _openCall(Map<String, Object?> c) {
    final f = c['function'];
    if (f == null) return c;
    if (f is! Map<String, Object?>) {
      throw _fail('e2ee.response', 'Werkzeugaufruf unlesbar');
    }
    final opened = <String, Object?>{...f};
    _openField(opened, 'name');
    _openField(opened, 'arguments');
    return {...c, 'function': opened};
  }

  /// Decrypts `obj[name]` in place; returns whether it changed.
  bool _openField(Map<String, Object?> obj, String name, {bool parts = false}) {
    final value = obj[name];
    if (value == null || value == '') return false;
    if (value is List<Object?> && parts) {
      obj[name] = [
        for (final p in value)
          if (p is Map<String, Object?> && p['text'] is String)
            {...p, 'text': _dec(p['text']! as String)}
          else
            throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt'),
      ];
      return true;
    }
    if (value is! String) {
      throw _fail('e2ee.response', 'Antwortfeld nicht verschlüsselt');
    }
    obj[name] = _dec(value);
    return true;
  }

  String _dec(String wire) {
    if (wire.isEmpty) return wire;
    if (!_seen.add(wire)) {
      throw _fail('e2ee.response', 'Wiederholtes Antwortstück, verworfen');
    }
    try {
      return utf8.decode(crypto.nearDecrypt(_client.secret, wire));
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
