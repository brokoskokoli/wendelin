import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// Streams [bodies] as the answer; records what the adapter sent.
final class _Router {
  _Router(this.service);
  final FakeEhbpService service;
  Uint8List? lastBody;
  Map<String, String>? lastHeaders;
  FakeEhbpExchange? exchange;
  int calls = 0;

  /// HTTP status per call (0-based); default 200.
  int Function(int call) status = (_) => 200;

  /// Builds the answer from the decrypted exchange; `null` = plain answer.
  ({Map<String, String> headers, List<Uint8List> chunks}) Function(
    FakeEhbpExchange ex,
  )?
  answer;

  late final client = MockClient.streaming((request, bodyStream) async {
    calls++;
    final body = await bodyStream.toBytes();
    lastBody = body;
    lastHeaders = request.headers;
    final ex = exchange = service.open(request.headers, body);
    final a = answer!(ex);
    return http.StreamedResponse(
      Stream.fromIterable(a.chunks),
      status(calls - 1),
      headers: {'content-type': 'text/event-stream', ...a.headers},
    );
  });
}

/// Delegates to the reference cipher and records disposals.
final class _SpyCrypto implements EhbpCrypto {
  final _inner = EhbpReferenceCrypto();
  final sessions = <EhbpSession>[];
  final decoders = <EhbpReferenceDecoder>[];
  int sessionDisposed = 0;

  @override
  EhbpBinding bindKeyConfig(Uint8List k, Uint8List r) =>
      _inner.bindKeyConfig(k, r);

  @override
  EhbpSealed beginRequest(Uint8List k, Uint8List r, Uint8List p) {
    final s = _inner.beginRequest(k, r, p);
    final spy = _SpySession(this, s.session);
    return EhbpSealed(
      encapsulatedKey: s.encapsulatedKey,
      body: s.body,
      session: spy,
    );
  }
}

final class _SpySession implements EhbpSession {
  _SpySession(this._spy, this._inner);
  final _SpyCrypto _spy;
  final EhbpSession _inner;

  @override
  EhbpDecoder responseDecoder(Uint8List n) {
    final d = _inner.responseDecoder(n) as EhbpReferenceDecoder;
    _spy.decoders.add(d);
    return d;
  }

  @override
  void dispose() {
    _spy.sessionDisposed++;
    _inner.dispose();
  }
}

String _sse(String fixture) =>
    File('test/fixtures/openai/$fixture').readAsStringSync();

ChatRequest _request() => ChatRequest(
  systemPrompt: 'Systemtext',
  messages: [Message.user('Geheimer Nutzertext')],
  model: 'gpt-oss-120b',
  maxTokens: 50,
);

void main() {
  late FakeEhbpService service;
  late _Router router;
  late TlsPinGate gate;
  EhbpTarget? target;

  var spy = _SpyCrypto();

  OpenAiChatAdapter adapter() => OpenAiChatAdapter(
    baseUrl: Uri.parse('https://inference.test/v1'),
    credentials: Credentials.apiKey('test', style: ApiKeyStyle.bearer),
    defaultModel: 'gpt-oss-120b',
    client: router.client,
    wireCodec: TinfoilEhbpCodec(
      crypto: spy,
      target: () => target,
      tlsPin: gate,
    ),
  );

  ({Map<String, String> headers, List<Uint8List> chunks}) encrypted(
    FakeEhbpExchange ex,
    String sse, {
    int frame = 90,
    int split = 13,
  }) {
    final r = ex.sealText(sse, frameSize: frame);
    return (
      headers: {'Ehbp-Response-Nonce': r.nonceHex},
      chunks: [
        for (var i = 0; i < r.body.length; i += split)
          r.body.sublist(
            i,
            i + split > r.body.length ? r.body.length : i + split,
          ),
      ],
    );
  }

  setUp(() {
    spy = _SpyCrypto();
    service = FakeEhbpService();
    router = _Router(service);
    gate = TlsPinGate(spkiSha256: (_) => Uint8List(32));
    target = EhbpTarget(
      keyConfig: service.keyConfig,
      reportData: service.reportData,
    );
  });

  Future<List<ChatEvent>> run() => adapter().chat(_request()).toList();

  test('streams a decrypted answer; the request is EHBP, not JSON', () async {
    router.answer = (ex) => encrypted(ex, _sse('text.sse'));
    final events = await run();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(events.last, isA<Done>());
    expect(events.whereType<TextDelta>(), isNotEmpty);
    // What went over the wire carries no plaintext, the router can read it.
    final wire = latin1.decode(router.lastBody!);
    expect(wire, isNot(contains('Geheimer Nutzertext')));
    expect(
      router.exchange!.request['messages'].toString(),
      contains('Geheimer Nutzertext'),
    );
    expect(router.lastHeaders!['Ehbp-Encapsulated-Key'], hasLength(64));
    expect(router.lastHeaders!['content-type'], 'application/json');
    // The pin of the attested report goes to the TLS gate.
    expect(gate.expected, AttestCodec.hex(service.tlsSpkiSha256));
  });

  test('decrypts tool calls across frame and chunk borders', () async {
    router.answer = (ex) => encrypted(ex, _sse('tool_call.sse'), frame: 51);
    final events = await run();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(
      events.whereType<ToolCallComplete>().single.call.name,
      'contract__echo',
    );
  });

  group('error answers', () {
    const rejection =
        '{"error":{"message":"unknown parameter: stream_options"}}';

    test('encrypted 400 is decrypted: stream_options retry works', () async {
      router.status = (c) => c == 0 ? 400 : 200;
      router.answer = (ex) => router.calls == 1
          ? encrypted(ex, rejection)
          : encrypted(ex, _sse('text.sse'));
      final events = await run();
      expect(router.calls, 2);
      expect(events.whereType<ErrorEvent>(), isEmpty);
      expect(events.last, isA<Done>());
      expect(router.exchange!.request.containsKey('stream_options'), isFalse);
    });

    test('encrypted 400 is classified from the decrypted body', () async {
      router.status = (_) => 400;
      router.answer = (ex) => encrypted(
        ex,
        '{"error":{"message":"Geheime Ablehnung","type":"invalid_request"}}',
      );
      final error = (await run()).whereType<ErrorEvent>().single.error;
      expect(error, isNot(isA<AttestationFailedException>()));
      expect(error.toString(), contains('Geheime Ablehnung'));
      expect(spy.decoders.single.disposed, isTrue);
    });

    test('400 without nonce: unauthenticated diagnostic, no retry', () async {
      router.status = (_) => 400;
      router.answer = (ex) => (
        headers: <String, String>{},
        chunks: [Uint8List.fromList(utf8.encode(rejection * 20))],
      );
      final error = (await run()).whereType<ErrorEvent>().single.error;
      expect(router.calls, 1, reason: 'unauthenticated body drives no retry');
      expect(error.toString(), contains('unauthentisiert'));
      expect(error.toString().length, lessThan(500));
    });

    test('unauthenticated diagnostic is cut at exactly 200 chars', () async {
      for (final (n, cut) in [(200, false), (201, true)]) {
        router.status = (_) => 400;
        router.answer = (ex) => (
          headers: <String, String>{},
          chunks: [Uint8List.fromList(utf8.encode('a' * n))],
        );
        final text = (await run())
            .whereType<ErrorEvent>()
            .single
            .error
            .toString();
        expect(text, contains('a' * 200), reason: '$n');
        expect(text, isNot(contains('a' * 201)), reason: '$n');
        expect(text.contains('a' * 200 + '…'), cut, reason: '$n');
      }
    });

    test('session is disposed on every error path', () async {
      router.status = (_) => 400;
      router.answer = (ex) => (
        headers: <String, String>{},
        chunks: [Uint8List.fromList(utf8.encode(rejection))],
      );
      await run();
      expect(spy.sessionDisposed, 1, reason: 'error without nonce');
      router.answer = (ex) => (
        headers: {'Ehbp-Response-Nonce': 'zz' * 32},
        chunks: [Uint8List.fromList(utf8.encode(rejection))],
      );
      await run();
      expect(spy.sessionDisposed, 2, reason: 'error with broken nonce');
    });

    test('2xx without nonce disposes the session', () async {
      router.answer = (ex) => (
        headers: <String, String>{},
        chunks: [Uint8List.fromList(utf8.encode(_sse('text.sse')))],
      );
      await run();
      expect(spy.sessionDisposed, 1);
    });

    test('failure before any answer disposes the session', () async {
      final failing = OpenAiChatAdapter(
        baseUrl: Uri.parse('https://inference.test/v1'),
        credentials: Credentials.apiKey('test', style: ApiKeyStyle.bearer),
        defaultModel: 'gpt-oss-120b',
        client: MockClient.streaming(
          (request, bodyStream) async => throw const SocketException('down'),
        ),
        wireCodec: TinfoilEhbpCodec(
          crypto: spy,
          target: () => target,
          tlsPin: gate,
        ),
      );
      final events = await failing.chat(_request()).toList();
      expect(events.whereType<ErrorEvent>(), isNotEmpty);
      expect(spy.sessionDisposed, 1);
    });

    test('400 with a broken ciphertext fails closed', () async {
      router.status = (_) => 400;
      router.answer = (ex) {
        final r = ex.sealText('{"error":{"message":"x"}}', frameSize: 500);
        final body = Uint8List.fromList(r.body)..[r.body.length - 3] ^= 1;
        return (headers: {'Ehbp-Response-Nonce': r.nonceHex}, chunks: [body]);
      };
      final error = (await run()).whereType<ErrorEvent>().single.error;
      expect(error, isA<AttestationFailedException>());
      expect((error as AttestationFailedException).stage, 'e2ee.response');
      expect(error.toString(), isNot(contains('"error"')));
      expect(spy.decoders.single.disposed, isTrue);
    });

    test('400 with an invalid nonce header fails closed', () async {
      router.status = (_) => 400;
      router.answer = (ex) => (
        headers: {'Ehbp-Response-Nonce': '00' * 5},
        chunks: [Uint8List.fromList(utf8.encode(rejection))],
      );
      final error = (await run()).whereType<ErrorEvent>().single.error;
      expect(error, isA<AttestationFailedException>());
    });
  });

  test('session secret and decoder are disposed after the answer', () async {
    router.answer = (ex) => encrypted(ex, _sse('text.sse'));
    await run();
    expect(spy.sessionDisposed, 1);
    expect(spy.decoders.single.disposed, isTrue);
  });

  test('decoder is disposed on a broken answer', () async {
    router.answer = (ex) {
      final r = ex.sealText(_sse('text.sse'), frameSize: 200);
      final body = Uint8List.fromList(r.body)..[r.body.length - 20] ^= 1;
      return (headers: {'Ehbp-Response-Nonce': r.nonceHex}, chunks: [body]);
    };
    await run();
    expect(spy.decoders.single.disposed, isTrue);
  });

  test('no Ehbp-Response-Nonce: error, never plaintext', () async {
    router.answer = (ex) => (
      headers: <String, String>{},
      chunks: [Uint8List.fromList(utf8.encode(_sse('text.sse')))],
    );
    final events = await run();
    expect(events.whereType<TextDelta>(), isEmpty);
    final error = events.whereType<ErrorEvent>().single.error;
    expect(error, isA<AttestationFailedException>());
    expect((error as AttestationFailedException).stage, 'e2ee.response');
  });

  test('invalid nonce headers are refused', () async {
    for (final bad in [
      'zz' * 32,
      '00' * 31,
      '00' * 33,
      '${'00' * 32},${'11' * 32}',
    ]) {
      router.answer = (ex) => (
        headers: {'Ehbp-Response-Nonce': bad},
        chunks: [Uint8List.fromList(utf8.encode(_sse('text.sse')))],
      );
      final events = await run();
      expect(events.whereType<ErrorEvent>(), hasLength(1), reason: bad);
      expect(events.whereType<TextDelta>(), isEmpty, reason: bad);
    }
  });

  test(
    'a flipped bit stops the answer, earlier text may have arrived',
    () async {
      router.answer = (ex) {
        final r = ex.sealText(_sse('text.sse'), frameSize: 200);
        final body = Uint8List.fromList(r.body)..[r.body.length - 20] ^= 1;
        return (headers: {'Ehbp-Response-Nonce': r.nonceHex}, chunks: [body]);
      };
      final events = await run();
      expect(events.last, isA<ErrorEvent>());
      expect(events.whereType<Done>(), isEmpty);
      expect(
        (events.last as ErrorEvent).error,
        isA<AttestationFailedException>(),
      );
    },
  );

  test('truncation inside a frame is an error, not a normal end', () async {
    router.answer = (ex) {
      final r = ex.sealText(_sse('text.sse'), frameSize: 5000);
      return (
        headers: {'Ehbp-Response-Nonce': r.nonceHex},
        chunks: [r.body.sublist(0, r.body.length - 3)],
      );
    };
    final events = await run();
    expect(events.last, isA<ErrorEvent>());
    expect(events.whereType<Done>(), isEmpty);
  });

  test(
    'a stream cut at a frame border before the end of the answer is no success',
    () async {
      router.answer = (ex) {
        final text = _sse('text.sse');
        final cut = text.substring(0, text.indexOf('\n\n') + 2);
        return encrypted(ex, cut, frame: 1 << 20);
      };
      final events = await run();
      expect(events.whereType<Done>(), isEmpty);
    },
  );

  test(
    'openBody: a dangling length prefix after complete frames fails',
    () async {
      final wire = TinfoilEhbpWire(
        crypto: EhbpReferenceCrypto(),
        target: target!,
      );
      final sealed = wire.sealBytes({'model': 'm'});
      final r = service.open(wire.headers, sealed.wire).sealText('data: x\n\n');
      wire.checkHead({'Ehbp-Response-Nonce': r.nonceHex});
      final out = <int>[];
      await expectLater(
        wire.openBody(Stream.value([...r.body, 0, 0])).forEach(out.addAll),
        throwsA(isA<AttestationFailedException>()),
      );
      expect(utf8.decode(out), 'data: x\n\n');
    },
  );

  test('reference session: dispose wipes the secret, later use throws', () {
    final sealed = EhbpReferenceCrypto().beginRequest(
      target!.keyConfig,
      target!.reportData,
      Uint8List.fromList(utf8.encode('x')),
    );
    final nonce = Uint8List(32);
    sealed.session.responseDecoder(nonce).dispose();
    expect((sealed.session as dynamic).secretWiped, isFalse);
    sealed.session.dispose();
    expect((sealed.session as dynamic).secretWiped, isTrue);
    expect(() => sealed.session.responseDecoder(nonce), throwsStateError);
  });

  test('wire disposes the session on a bad nonce, itself', () {
    for (final bad in [null, 'zz' * 32, '00' * 31]) {
      final before = spy.sessionDisposed;
      final wire = TinfoilEhbpWire(crypto: spy, target: target!);
      wire.sealBytes({'model': 'm'});
      expect(
        () => wire.checkHead({'Ehbp-Response-Nonce': ?bad}),
        throwsA(isA<AttestationFailedException>()),
      );
      expect(spy.sessionDisposed, before + 1, reason: '$bad');
      wire.dispose();
      expect(spy.sessionDisposed, before + 1, reason: 'idempotent');
    }
    final wire = TinfoilEhbpWire(crypto: spy, target: target!);
    final before = spy.sessionDisposed;
    wire.sealBytes({'model': 'm'});
    wire.dispose();
    expect(spy.sessionDisposed, before + 1, reason: 'abort without answer');
  });

  test('replayed frame fails', () async {
    router.answer = (ex) {
      final r = ex.seal([Uint8List.fromList(utf8.encode('data: {}\n\n'))]);
      return (
        headers: {'Ehbp-Response-Nonce': r.nonceHex},
        chunks: [
          Uint8List.fromList([...r.body, ...r.body]),
        ],
      );
    };
    final events = await run();
    expect(events.last, isA<ErrorEvent>());
  });

  test('without a verified target nothing is sent', () async {
    target = null;
    router.answer = (ex) => encrypted(ex, _sse('text.sse'));
    final events = await run();
    expect(router.calls, 0);
    final error = events.whereType<ErrorEvent>().single.error;
    expect((error as AttestationFailedException).stage, 'e2ee.key');
  });

  test('a key that is not report_data[32..64] is not used', () async {
    final other = FakeEhbpService(secret: Uint8List(32)..[0] = 9);
    target = EhbpTarget(
      keyConfig: other.keyConfig,
      reportData: service.reportData,
    );
    router.answer = (ex) => encrypted(ex, _sse('text.sse'));
    final events = await run();
    expect(router.calls, 0);
    final error = events.whereType<ErrorEvent>().single.error;
    expect((error as AttestationFailedException).stage, 'bind.hpke');
    expect(gate.expected, isNull);
  });

  test('the errors carry neither plaintext nor key material', () async {
    router.answer = (ex) =>
        (headers: <String, String>{}, chunks: [Uint8List(1)]);
    final events = await run();
    final text = events.whereType<ErrorEvent>().single.error.toString();
    expect(text, isNot(contains('Geheimer Nutzertext')));
    expect(text, isNot(contains(AttestCodec.hex(service.publicKey))));
  });

  test('every attempt uses a fresh ephemeral key', () async {
    router.answer = (ex) => encrypted(ex, _sse('text.sse'));
    await run();
    final first = router.lastHeaders!['Ehbp-Encapsulated-Key'];
    await run();
    expect(router.lastHeaders!['Ehbp-Encapsulated-Key'], isNot(first));
  });

  test('cancel aborts without error after dispose of the listener', () async {
    final hold = Completer<void>();
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      await hold.future;
      return http.StreamedResponse(const Stream.empty(), 200);
    });
    final token = CancelToken();
    final a = OpenAiChatAdapter(
      baseUrl: Uri.parse('https://inference.test/v1'),
      credentials: Credentials.apiKey('test', style: ApiKeyStyle.bearer),
      defaultModel: 'm',
      client: client,
      wireCodec: TinfoilEhbpCodec(
        crypto: EhbpReferenceCrypto(),
        target: () => target,
      ),
    );
    final future = a.chat(_request(), cancel: token).toList();
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    final events = await future;
    expect(events.last, isA<ErrorEvent>());
    hold.complete();
  });

  group('TinfoilEhbpChannel: Ablauf der Sitzung', () {
    final t0 = DateTime.utc(2026, 10, 19, 12);

    AttestedSession session(DateTime notAfter) => AttestedSession(
      keysetDigest: 'sha256:00',
      notAfter: notAfter,
      receiptKeys: const {},
      repoCommit: '',
      composeHash: '',
      attestedAt: t0,
      ehbpKeyConfig: service.keyConfig,
      reportData: service.reportData,
    );

    Future<Object?> beginAt(DateTime now, DateTime notAfter) async {
      final channel = TinfoilEhbpChannel(crypto: spy)
        ..bind(() => session(notAfter), FixedClock(now));
      try {
        await channel.begin(model: 'm');
        return null;
      } on AttestationFailedException catch (e) {
        return e.stage;
      }
    }

    test('vor Ablauf wird verschlüsselt, ab Ablauf nichts gesendet', () async {
      final end = t0.add(const Duration(minutes: 30));
      expect(await beginAt(t0, end), isNull);
      expect(
        await beginAt(end.subtract(const Duration(seconds: 1)), end),
        isNull,
      );
      expect(await beginAt(end, end), 'e2ee.key');
      expect(await beginAt(end.add(const Duration(hours: 1)), end), 'e2ee.key');
    });

    test('ohne Sitzung: kein Schlüssel, nichts gesendet', () async {
      final channel = TinfoilEhbpChannel(crypto: spy)
        ..bind(() => null, FixedClock(t0));
      await expectLater(
        channel.begin(model: 'm'),
        throwsA(isA<AttestationFailedException>()),
      );
    });
  });
}
