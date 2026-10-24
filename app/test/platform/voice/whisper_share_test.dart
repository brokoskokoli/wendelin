import 'dart:isolate';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/whisper_registry.dart';
import 'package:wendelin/platform/voice/whisper_share.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// A stand-in for the Whisper isolate: answers shared requests with the
/// number of samples (or fails for the language `xx`).
void _worker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((message) {
    if (isSharedWhisperRequest(message)) {
      answerSharedWhisper(message! as List<Object?>, (samples, language) {
        if (language == 'xx') throw StateError('kaputt');
        return WhisperResult(
          text: '${samples.length} Samples',
          language: language ?? 'de',
          meanLogProb: samples.length == 1600 ? -0.25 : null,
        );
      });
    } else if (message == 'exit') {
      inbox.close();
    }
  });
}

void main() {
  late Isolate isolate;
  late SendPort worker;

  setUp(() async {
    final ready = ReceivePort();
    isolate = await Isolate.spawn(_worker, ready.sendPort);
    worker = await ready.first as SendPort;
  });

  tearDown(() => isolate.kill(priority: Isolate.immediate));

  test('Anfragen erkennen', () {
    expect(isSharedWhisperRequest(['ping', worker]), isTrue);
    expect(isSharedWhisperRequest(['transcribe']), isTrue);
    expect(isSharedWhisperRequest(const <Object>[]), isFalse);
    expect(isSharedWhisperRequest(['other']), isFalse);
    expect(isSharedWhisperRequest(null), isFalse);
  });

  test('ping, transkribieren, Fehler', () async {
    expect(await RemoteWhisperBackend.alive(worker), isTrue);
    final remote = RemoteWhisperBackend(worker);
    final r = await remote.transcribe(Float32List(1600), language: 'fr');
    expect(r.text, '1600 Samples');
    expect(r.language, 'fr');
    expect(r.meanLogProb, -0.25);
    expect((await remote.transcribe(Float32List(16))).meanLogProb, isNull);
    expect((await remote.transcribe(Float32List(16))).language, 'de');
    await expectLater(
      remote.transcribe(Float32List(16), language: 'xx'),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.failed,
        ),
      ),
    );
    await remote.dispose(); // does not own the model
    expect(await RemoteWhisperBackend.alive(worker), isTrue);
  });

  test('kaputte Anfragen werden ignoriert', () async {
    final reply = ReceivePort();
    answerSharedWhisper(['transcribe', 'kein Audio', null, reply.sendPort], (
      _,
      _,
    ) {
      fail('nicht aufrufen');
    });
    answerSharedWhisper(['ping', 'kein Port'], (_, _) => fail('nein'));
    reply.close();
  });

  test('Besitzer weg: nach der Ping-Frist unavailable statt 60 s', () {
    // Virtuelle Zeit: der Aufruf muss nach der Ping-Frist (50 ms) enden, nicht
    // erst nach der Antwortfrist von 60 s.
    fakeAsync((async) {
      final dead = ReceivePort()..close();
      bool? alive;
      RemoteWhisperBackend.alive(
        dead.sendPort,
        within: const Duration(milliseconds: 50),
      ).then((v) => alive = v);
      Object? error;
      RemoteWhisperBackend(
            dead.sendPort,
            pingTimeout: const Duration(milliseconds: 50),
          )
          .transcribe(Float32List(16))
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      async.elapse(const Duration(milliseconds: 49));
      expect(alive, isNull);
      expect(error, isNull);
      async.elapse(const Duration(milliseconds: 11));
      expect(alive, isFalse);
      expect(error, isA<VoiceException>());
      expect((error! as VoiceException).kind, VoiceErrorKind.unavailable);
    });
  });

  /// A port that answers pings and then [onTranscribe].
  ReceivePort fakeOwner(void Function(SendPort reply) onTranscribe) {
    final port = ReceivePort();
    port.listen((m) {
      final list = m as List<Object?>;
      final reply = list.last! as SendPort;
      list.first == 'ping' ? reply.send(const ['pong']) : onTranscribe(reply);
    });
    addTearDown(port.close);
    return port;
  }

  test(
    'Besitzer lebt, antwortet aber nicht rechtzeitig: unavailable',
    () async {
      final slow = fakeOwner((_) {});
      await expectLater(
        RemoteWhisperBackend(
          slow.sendPort,
          timeout: const Duration(milliseconds: 50),
        ).transcribe(Float32List(16)),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.unavailable,
          ),
        ),
      );
    },
  );

  test('Frist: 20 s plus Länge der Aufnahme (WP19)', () {
    final port = ReceivePort();
    addTearDown(port.close);
    final backend = RemoteWhisperBackend(port.sendPort);
    expect(backend.timeout, const Duration(seconds: 20));
    expect(
      backend.waitFor(Float32List(16000 * 4)),
      const Duration(seconds: 24),
    );
    expect(backend.waitFor(Float32List(0)), const Duration(seconds: 20));
  });

  test('unerwartete Antwort', () async {
    final odd = fakeOwner((reply) => reply.send(const ['weird']));
    await expectLater(
      RemoteWhisperBackend(odd.sendPort).transcribe(Float32List(4)),
      throwsStateError,
    );
    final noPong = ReceivePort();
    noPong.listen((m) => ((m as List<Object?>).last! as SendPort).send('x'));
    expect(await RemoteWhisperBackend.alive(noPong.sendPort), isFalse);
    noPong.close();
  });

  group('Registry (zwischen Engines)', () {
    test('veröffentlichen, finden, zurückziehen', () async {
      expect(await lookupSharedWhisper('whisper-base'), isNull);
      publishSharedWhisper('whisper-base', worker);
      final found = await lookupSharedWhisper('whisper-base');
      expect(found, isNotNull);
      expect(found!.port, worker);
      expect(await lookupSharedWhisper('whisper-small'), isNull);
      // Someone else's port is not withdrawn.
      withdrawSharedWhisper('whisper-base', ReceivePort().sendPort);
      expect(await lookupSharedWhisper('whisper-base'), isNotNull);
      withdrawSharedWhisper('whisper-base', worker);
      expect(await lookupSharedWhisper('whisper-base'), isNull);
    });

    test('Besitzer antwortet nicht: nicht verwenden', () async {
      final dead = ReceivePort()..close();
      publishSharedWhisper('whisper-small', dead.sendPort);
      expect(
        await lookupSharedWhisper(
          'whisper-small',
          within: const Duration(milliseconds: 50),
        ),
        isNull,
      );
      withdrawSharedWhisper('whisper-small', dead.sendPort);
    });
  });
}
