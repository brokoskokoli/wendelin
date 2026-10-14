import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/attestation_types.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/src/tee/e2ee_v2.dart';
import 'package:wendelin_providers/src/tee/gateway_documents.dart';
import 'package:wendelin_providers/testing.dart' show e2eeFrozenAad;

import 'e2ee_support.dart';
import 'tee_support.dart';

const _nonce =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _ts = 1750000000;

/// Exact AAD strings of `spec/e2ee-v2-test-vectors.md` (Dstack-TEE/private-ai-gateway).
const _requestAad =
    '{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"messages.0.content",'
    '"model":"demo-model","nonce":"$_nonce","purpose":"aci.e2ee.request.v2",'
    '"ts":1750000000}';
const _responseAad =
    '{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"choices.0.message.content",'
    '"id":"chatcmpl-123","model":"demo-model","nonce":"$_nonce",'
    '"purpose":"aci.e2ee.response.v2","ts":1750000000}';

String _text(Uint8List b) => utf8.decode(b);

final _hello = <String, Object?>{
  'model': 'm',
  'messages': [
    {'role': 'user', 'content': 'x'},
  ],
};

void main() {
  final crypto = FakeAttestationCrypto();
  late FakeE2eeService service;
  setUp(() => service = FakeE2eeService(now: () => probeNow));

  E2eeV2Wire wire({
    String model = 'm',
    String? digest,
    int? ts,
    String nonce = _nonce,
  }) => E2eeV2Wire(
    crypto: crypto,
    key: keyOf(service),
    model: model,
    timestamp: ts ?? probeNow.millisecondsSinceEpoch ~/ 1000,
    nonce: nonce,
    keysetDigest: digest,
  );

  Map<String, String> wireH() => wire().headers;

  String wireFor(Map<String, Object?> b) => wire().seal(b).wire;

  group('Protokollbaustein v2: AAD und Schlüsselwahl', () {
    test('AAD entspricht byte-genau den veröffentlichten Vektoren', () {
      expect(
        _text(
          E2eeProtocolV2.requestAad(
            field: 'messages.0.content',
            model: 'demo-model',
            nonce: _nonce,
            ts: _ts,
          ),
        ),
        _requestAad,
      );
      expect(
        _text(
          E2eeProtocolV2.responseAad(
            field: 'choices.0.message.content',
            id: 'chatcmpl-123',
            model: 'demo-model',
            nonce: _nonce,
            ts: _ts,
          ),
        ),
        _responseAad,
      );
      expect(_requestAad, e2eeFrozenAad);
    });

    test(
      'Schlüsselwahl nach algo, nicht nach key_id; Müll wird übergangen',
      () {
        const good =
            '408e82d159832cfae15007781bcade0badee7d50e9f76d50eaa1777464006537';
        KeysetKey k(String id, String algo, String pub) =>
            KeysetKey(id, algo, pub);
        final key = E2eeProtocolV2.selectKey([
          k('dstack-kms-e2ee-v1', 'secp256k1-aes-256-gcm-hkdf-sha256', '04aa'),
          k('x', E2eeProtocolV2.algo, 'zz'),
          k('y', E2eeProtocolV2.algo, 'abcd'),
          k('irgendein-label', E2eeProtocolV2.algo, '0x$good'),
        ]);
        expect(key?.keyId, 'irgendein-label');
        expect(AttestCodec.hex(key!.publicKey), good);
        expect(
          E2eeProtocolV2.selectKey([
            k('a', 'secp256k1-aes-256-gcm-hkdf-sha256', good),
          ]),
          isNull,
        );
        expect(E2eeProtocolV2.selectKey(const []), isNull);
      },
    );
  });

  group('Request verschlüsseln', () {
    test('Header: fünf Pflichtfelder, Nonce klein, kein X-Signing-Algo', () {
      final h = wire(ts: _ts).headers;
      expect(h.keys.map((e) => e.toLowerCase()).toSet(), {
        'x-e2ee-version',
        'x-client-pub-key',
        'x-model-pub-key',
        'x-e2ee-nonce',
        'x-e2ee-timestamp',
      });
      expect(h['X-E2EE-Version'], '2');
      expect(h['X-E2EE-Nonce'], _nonce);
      expect(h['X-E2EE-Timestamp'], '$_ts');
      expect(h['X-Model-Pub-Key'], service.publicKeyHex);
      expect(h['X-Client-Pub-Key'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('jeder String-Content ist verschlüsselt, Rest bleibt, Klartext für die Quittung kompakt', () {
      final body = {
        'model': 'm',
        'messages': [
          {'role': 'system', 'content': 'Geheimer Systemprompt'},
          {'role': 'user', 'content': ''},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Geheimer Text'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,GEHEIMBILD'},
              },
            ],
          },
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'c1',
                'type': 'function',
                'function': {'name': 'f', 'arguments': '{"x":1}'},
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'c1',
            'content': 'Geheimes Ergebnis',
          },
        ],
        'tools': [
          {'type': 'function'},
        ],
        'stream': true,
        'max_tokens': 5,
      };
      final w = wire();
      final sealed = w.seal(body);
      final wireText = sealed.wire;
      for (final secret in [
        'Geheimer Systemprompt',
        'Geheimer Text',
        'GEHEIMBILD',
        'Geheimes Ergebnis',
      ]) {
        expect(wireText, isNot(contains(secret)));
      }
      final json = jsonDecode(wireText) as Map<String, Object?>;
      expect(json['tools'], body['tools']);
      expect(json['stream'], true);
      expect(json['model'], 'm');
      // The service decrypts it to exactly the original and hashes this.
      final exchange = service.open(w.headers, utf8.encode(wireText));
      expect(exchange.plainBody, body);
      expect(sealed.plain, exchange.plainBytes);
      expect(utf8.decode(sealed.plain), jsonEncode(body));
      final messages = json['messages']! as List<Object?>;
      expect((messages[3]! as Map)['content'], isNull);
      expect((messages[3]! as Map)['tool_calls'], isNotNull);
    });

    test('Text, der wie ein JSON-Array aussieht, geht als Teil-Array (kein Umbau durch den Dienst)', () {
      final body = {
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': '[1,2,3]'},
        ],
      };
      final w = wire();
      final sealed = w.seal(body);
      expect(sealed.wire, isNot(contains('[1,2,3]')));
      final exchange = service.open(w.headers, utf8.encode(sealed.wire));
      expect(sealed.plain, exchange.plainBytes);
      final content =
          ((exchange.plainBody['messages']! as List).single as Map)['content'];
      expect(content, [
        {'type': 'text', 'text': '[1,2,3]'},
      ]);
    });

    test(
      'Fehlerfälle: keine Nachrichten, unlesbarer Inhalt, unbekannter Teil',
      () {
        void fails(Map<String, Object?> body) => expect(
          () => wire().seal(body),
          throwsA(
            isA<AttestationFailedException>().having(
              (e) => e.stage,
              'stage',
              'e2ee.request',
            ),
          ),
        );
        fails({'model': 'm'});
        fails({'model': 'm', 'messages': <Object?>[]});
        fails({
          'model': 'm',
          'messages': ['x'],
        });
        fails({
          'model': 'm',
          'messages': [
            {'role': 'user', 'content': 5},
          ],
        });
        fails({
          'model': 'm',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'video', 'url': 'KLARTEXT'},
              ],
            },
          ],
        });
        fails({
          'model': 'm',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'image_url', 'image_url': <String, Object?>{}},
              ],
            },
          ],
        });
        fails({
          'model': 'm',
          'messages': [
            {
              'role': 'user',
              'content': ['x'],
            },
          ],
        });
      },
    );

    test(
      'AAD bindet Modell, Nonce, Zeit und Feld: Dienst lehnt Abweichungen ab',
      () {
        final body = {
          'model': 'm',
          'messages': [
            {'role': 'user', 'content': 'a'},
          ],
        };
        final sealed = wire().seal(body).wire;
        final w = wire();
        final h = w.headers;
        // Other nonce in the header than in the AAD.
        expect(
          () => service.open({
            ...h,
            'X-E2EE-Nonce': 'a' * 64,
          }, utf8.encode(sealed)),
          throwsA(
            isA<E2eeRejection>().having(
              (e) => e.type,
              'type',
              'e2ee_decryption_failed',
            ),
          ),
        );
        // Another model name.
        final other = jsonDecode(sealed) as Map<String, Object?>
          ..['model'] = 'x';
        expect(
          () => service.open(h, utf8.encode(jsonEncode(other))),
          throwsA(isA<E2eeRejection>()),
        );
      },
    );
  });

  group('Antwort entschlüsseln', () {
    FakeE2eeExchange open(E2eeV2Wire w) => service.open(
      w.headers,
      utf8.encode(
        w.seal({
          'model': w.model,
          'messages': [
            {'role': 'user', 'content': 'x'},
          ],
        }).wire,
      ),
    );

    String chunk(
      FakeE2eeExchange e, {
      String id = 'c1',
      String name = 'content',
      String text = 'Hallo',
      int index = 0,
    }) => jsonEncode({
      'id': 'c1',
      'choices': [
        {
          'index': index,
          'delta': {
            name: e.encryptField('choices.$index.delta.$name', id, text),
          },
        },
      ],
    });

    test(
      'Deltas content, reasoning und reasoning_content werden entschlüsselt',
      () {
        final w = wire();
        final e = open(w);
        for (final name in ['content', 'reasoning', 'reasoning_content']) {
          final out = w.open(
            SseEvent(
              data: chunk(e, name: name, text: 'Grüße ✓'),
            ),
          );
          final delta =
              (((jsonDecode(out.data) as Map)['choices']! as List).single
                      as Map)['delta']!
                  as Map;
          expect(delta[name], 'Grüße ✓');
        }
      },
    );

    test('Klartext, falscher Feldpfad, falsche id, fremder Schlüssel, Nicht-String: Fehler', () {
      final w = wire();
      final e = open(w);
      void fails(String data) => expect(
        () => w.open(SseEvent(data: data)),
        throwsA(
          isA<AttestationFailedException>().having(
            (x) => x.stage,
            'stage',
            'e2ee.response',
          ),
        ),
      );
      fails(
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'delta': {'content': 'Klartext statt Chiffre'},
            },
          ],
        }),
      );
      // Cipher of another chunk id / another field.
      fails(
        jsonEncode({
          'id': 'c2',
          'choices': [
            {
              'index': 0,
              'delta': {
                'content': e.encryptField('choices.0.delta.content', 'c1', 'x'),
              },
            },
          ],
        }),
      );
      fails(
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'content': e.encryptField(
                  'choices.0.delta.reasoning',
                  'c1',
                  'x',
                ),
              },
            },
          ],
        }),
      );
      fails(
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'delta': {'content': 5},
            },
          ],
        }),
      );
      // Encrypted to the key of another request.
      final strangerExchange = FakeE2eeService(now: () => probeNow).open(
        wire(nonce: 'b' * 64).headers,
        utf8.encode(wire(nonce: 'b' * 64).seal(_hello).wire),
      );
      fails(chunk(strangerExchange));
      fails('kein json');
      fails('[1]');
    });

    test('Index kommt aus dem index-Member; ohne Member gilt die Position', () {
      final w = wire();
      final e = open(w);
      final out = w.open(
        SseEvent(
          data: jsonEncode({
            'id': 'c1',
            'choices': [
              {
                'delta': {
                  'content': e.encryptField(
                    'choices.0.delta.content',
                    'c1',
                    'p',
                  ),
                },
              },
              {
                'index': 7,
                'delta': {
                  'content': e.encryptField(
                    'choices.7.delta.content',
                    'c1',
                    'q',
                  ),
                },
              },
            ],
          }),
        ),
      );
      final choices = (jsonDecode(out.data) as Map)['choices']! as List;
      expect(choices.map((c) => ((c as Map)['delta'] as Map)['content']), [
        'p',
        'q',
      ]);
    });

    test('durchgelassen: [DONE], leere/fehlende Felder, tool_calls, usage, Fehlerobjekt', () {
      final w = wire();
      open(w);
      const done = SseEvent(data: '[DONE]');
      expect(w.open(done), same(done));
      for (final data in [
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'delta': {'role': 'assistant', 'content': ''},
            },
          ],
        }),
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'delta': {'content': null},
              'finish_reason': 'stop',
            },
          ],
        }),
        jsonEncode({
          'id': 'c1',
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'name': 'f', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        }),
        jsonEncode({
          'choices': <Object?>[],
          'usage': {'total_tokens': 3},
        }),
        jsonEncode({
          'error': {'message': 'kaputt'},
        }),
      ]) {
        final event = SseEvent(data: data);
        expect(w.open(event), same(event));
      }
    });

    test('Kopfzeilen: nur verschlüsselte Antworten mit Version, Suite und passendem Keyset', () {
      final ok = {
        'x-e2ee-applied': 'true',
        'x-e2ee-version': '2',
        'x-e2ee-algo': E2eeProtocolV2.algo,
      };
      final w = wire(digest: 'sha256:abc');
      w.checkHead({...ok, 'x-aci-keyset-digest': 'sha256:abc'});
      w.checkHead({...ok, 'x-e2ee-applied': 'TRUE'});
      void fails(Map<String, String> h, String stage) => expect(
        () => w.checkHead(h),
        throwsA(
          isA<AttestationFailedException>().having(
            (e) => e.stage,
            'stage',
            stage,
          ),
        ),
      );
      fails(const {}, 'e2ee.response');
      fails({...ok, 'x-e2ee-applied': 'false'}, 'e2ee.response');
      fails({...ok}..remove('x-e2ee-applied'), 'e2ee.response');
      fails({...ok, 'x-e2ee-version': '3'}, 'e2ee.response');
      fails({
        ...ok,
        'x-e2ee-algo': 'secp256k1-aes-256-gcm-hkdf-sha256',
      }, 'e2ee.response');
      fails({...ok, 'x-aci-keyset-digest': 'sha256:andere'}, 'e2ee.keyset');
    });
  });

  group('PhalaE2eeChannel', () {
    AttestedSession session({E2eeKey? key, DateTime? notAfter}) =>
        AttestedSession(
          keysetDigest: 'sha256:x',
          notAfter: notAfter ?? probeNow.add(const Duration(days: 1)),
          receiptKeys: const {},
          repoCommit: null,
          composeHash: 'c',
          attestedAt: probeNow,
          e2eeKey: key,
        );

    Future<void> failsWith(PhalaE2eeChannel c) => expectLater(
      c.begin(model: 'm'),
      throwsA(
        isA<AttestationFailedException>().having(
          (e) => e.stage,
          'stage',
          'e2ee.key',
        ),
      ),
    );

    test('ohne Sitzung, ohne Schlüssel oder mit abgelaufenem Keyset wird nichts gesendet', () async {
      AttestedSession? current;
      final c = PhalaE2eeChannel(crypto: crypto);
      await failsWith(c); // not bound
      c.bind(() => current, FixedClock(probeNow));
      await failsWith(c);
      current = session();
      await failsWith(c);
      current = session(key: keyOf(service), notAfter: probeNow);
      await failsWith(c); // exactly at not_after
      current = session(key: keyOf(service));
      expect(await c.begin(model: 'm'), isA<E2eeV2Wire>());
      expect(() => c.bind(() => null, FixedClock(probeNow)), throwsStateError);
    });

    test('jede Anfrage: frische Nonce (64 Hex klein), frischer Client-Schlüssel, Zeit der Uhr', () async {
      final c = PhalaE2eeChannel(crypto: crypto)
        ..bind(() => session(key: keyOf(service)), FixedClock(probeNow));
      final a = (await c.begin(model: 'm')).headers;
      final b = (await c.begin(model: 'm')).headers;
      expect(a['X-E2EE-Nonce'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a['X-E2EE-Nonce'], isNot(b['X-E2EE-Nonce']));
      expect(a['X-Client-Pub-Key'], isNot(b['X-Client-Pub-Key']));
      expect(
        a['X-E2EE-Timestamp'],
        '${probeNow.millisecondsSinceEpoch ~/ 1000}',
      );
    });
  });

  group('FakeE2eeService lehnt wie der echte Dienst ab', () {
    final body = utf8.encode(jsonEncode(_hello));

    Map<String, String> headers() => wireH();

    test('Header, Nonce, Zeit, Schlüssel, Replay, Body', () {
      final sealed = utf8.encode(wireFor(_hello));
      void rejects(String type, Map<String, String> h, [List<int>? b]) =>
          expect(
            () => service.open(h, Uint8List.fromList(b ?? sealed)),
            throwsA(isA<E2eeRejection>().having((e) => e.type, 'type', type)),
          );

      final h = headers();
      service.open(h, Uint8List.fromList(sealed));
      rejects('e2ee_replay_detected', h);
      rejects('e2ee_header_missing', {...h}..remove('X-E2EE-Nonce'));
      rejects('e2ee_invalid_version', {...h, 'X-E2EE-Version': '1'});
      rejects('e2ee_invalid_version', {...h, 'X-Signing-Algo': 'ecdsa'});
      rejects('e2ee_invalid_nonce', {...h, 'X-E2EE-Nonce': 'A' * 64});
      rejects('e2ee_invalid_timestamp', {...h, 'X-E2EE-Timestamp': '1'});
      rejects('e2ee_invalid_timestamp', {...h, 'X-E2EE-Timestamp': 'x'});
      rejects('e2ee_invalid_public_key', {...h, 'X-Client-Pub-Key': 'zz'});
      rejects('e2ee_invalid_public_key', {...h, 'X-Client-Pub-Key': 'ab'});
      rejects('e2ee_model_key_mismatch', {...h, 'X-Model-Pub-Key': 'ab' * 32});
      final fresh = {...headers(), 'X-E2EE-Nonce': 'c' * 64};
      rejects('e2ee_decryption_failed', fresh, utf8.encode('kein json'));
      rejects('e2ee_invalid_payload_model', {
        ...headers(),
        'X-E2EE-Nonce': 'd' * 64,
      }, utf8.encode('{"messages":[]}'));
      rejects(
        'e2ee_decryption_failed',
        {...headers(), 'X-E2EE-Nonce': 'e' * 64},
        body, // plaintext content
      );
      rejects('e2ee_decryption_failed', {
        ...headers(),
        'X-E2EE-Nonce': 'f' * 64,
      }, utf8.encode('{"model":"m","messages":5}'));
      expect(const E2eeRejection('t', 'm').body, contains('"type":"t"'));
    });
  });
}
