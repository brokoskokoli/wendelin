import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/recognizer/device_recognizer_engines.dart';
import 'package:wendelin/platform/voice/engine_whisper.dart';
import 'package:wendelin/platform/voice/whisper_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class FakeBackend implements WhisperBackend {
  FakeBackend(this.name);

  final String name;
  int disposed = 0;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async => WhisperResult(text: name, language: language ?? 'de');

  @override
  Future<void> dispose() async => disposed++;
}

void main() {
  late FakeSpeechModelService models;
  late List<SttSpec> started;
  late List<FakeBackend> own;
  late List<String> lookups;
  FakeBackend? shared;
  Object? startError;
  late List<(String, double)> vads;

  DeviceRecognizerEngines engines({
    Duration idle = const Duration(seconds: 30),
  }) => DeviceRecognizerEngines(
    models: models,
    idleRelease: idle,
    startWhisper: (files) async {
      started.add(files);
      final e = startError;
      if (e != null) throw e;
      final b = FakeBackend('eigen');
      own.add(b);
      return b;
    },
    lookupShared: (id) async {
      lookups.add(id);
      return shared;
    },
    createVad: (path, threshold) {
      vads.add((path, threshold));
      return FakeVoiceActivityDetector(threshold: threshold);
    },
  );

  setUp(() {
    models = FakeSpeechModelService()
      ..installed.addAll({'whisper-base', 'silero-vad'});
    started = [];
    own = [];
    lookups = [];
    shared = null;
    startError = null;
    vads = [];
  });

  Future<String> text(SpeechToText stt) async =>
      (await stt.transcribe(Int16List.fromList(List.filled(1600, 3000)))).text;

  group('checkInstalled', () {
    test('Whisper und Silero da: in Ordnung', () async {
      expect(await engines().checkInstalled('whisper-base'), 'whisper-base');
    });

    for (final (name, installed, id, expected) in [
      // Kein Spiegel (Standard small), nur base da: base (WP33).
      (
        'small fehlt, base da',
        {'whisper-base'},
        'whisper-small',
        'whisper-base',
      ),
      (
        'base fehlt, small da',
        {'whisper-small'},
        'whisper-base',
        'whisper-small',
      ),
      (
        'beide da: small vor base',
        {'whisper-base', 'whisper-small'},
        'whisper-huge',
        'whisper-small',
      ),
      (
        'angefragtes geht vor',
        {'whisper-base', 'whisper-small'},
        'whisper-base',
        'whisper-base',
      ),
    ]) {
      test('Ausweichen: $name', () async {
        models.installed
          ..clear()
          ..addAll({...installed, 'silero-vad'});
        expect(await engines().checkInstalled(id), expected);
      });
    }

    for (final (name, missing, id) in [
      ('kein Whisper', 'whisper-base', 'whisper-small'),
      ('Silero fehlt', 'silero-vad', 'whisper-base'),
      ('unbekanntes Modell, kein Whisper', 'whisper-base', 'whisper-huge'),
    ]) {
      test('$name: modelMissing', () async {
        models.installed.remove(missing);
        await expectLater(
          engines().checkInstalled(id),
          throwsA(
            isA<VoiceException>().having(
              (e) => e.kind,
              'kind',
              VoiceErrorKind.modelMissing,
            ),
          ),
        );
      });
    }
  });

  test('VAD aus dem Silero-Verzeichnis mit der Schwelle', () {
    final e = engines();
    final vad = e.vad(0.6);
    expect(vads.single, ('/fake/silero-vad/silero_vad.onnx', 0.6));
    expect(vad.threshold, 0.6);
    e.releaseVad(vad); // fakes need no freeing
  });

  test('Whisper der App vorhanden: kein zweites Modell', () async {
    shared = FakeBackend('geteilt');
    final e = engines();
    final stt = await e.speechToText('whisper-base');
    expect(await text(stt), 'geteilt');
    expect(stt.info.model, 'whisper-base');
    expect(started, isEmpty);
    expect(e.holdsOwnModel, isFalse);
    expect(lookups, ['whisper-base']);
  });

  test('sonst eigenes Modell, wird wiederverwendet', () async {
    final e = engines();
    expect(await text(await e.speechToText('whisper-base')), 'eigen');
    expect(
      (started.single as WhisperFiles).encoder,
      '/fake/whisper-base/base-encoder.int8.onnx',
    );
    expect(await text(await e.speechToText('whisper-base')), 'eigen');
    expect(started, hasLength(1));
    expect(e.holdsOwnModel, isTrue);
  });

  test('anderes Modell ersetzt das eigene', () async {
    models.installed.add('whisper-small');
    final e = engines();
    await e.speechToText('whisper-base');
    await e.speechToText('whisper-small');
    expect(started, hasLength(2));
    expect(own.first.disposed, 1);
    expect(own.last.disposed, 0);
  });

  test(
    'Modell entpackt, aber beschädigt: modelBroken, Log ohne Pfad',
    () async {
      final lines = <String>[];
      final saved = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = saved);
      models.installed.remove('whisper-base');
      models.damaged.add('whisper-base');
      await expectLater(
        engines().speechToText('whisper-base'),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.modelBroken,
          ),
        ),
      );
      expect(started, isEmpty);
      expect(
        lines.join(),
        allOf(contains('model-broken'), isNot(contains('/fake'))),
      );
    },
  );

  test('Modell nicht installiert: modelMissing', () async {
    models.installed.remove('whisper-base');
    await expectLater(
      engines().speechToText('whisper-base'),
      throwsA(isA<VoiceException>()),
    );
    expect(started, isEmpty);
  });

  test(
    'Laden scheitert: nichts bleibt hängen, nächster Versuch lädt neu',
    () async {
      final e = engines();
      startError = const VoiceException(VoiceErrorKind.failed, 'kaputt');
      await expectLater(
        e.speechToText('whisper-base'),
        throwsA(isA<VoiceException>()),
      );
      expect(e.holdsOwnModel, isFalse);
      startError = null;
      expect(await text(await e.speechToText('whisper-base')), 'eigen');
      expect(started, hasLength(2));
    },
  );

  test('nach der Ruhezeit wird das eigene Modell freigegeben', () {
    fakeAsync((async) {
      final e = engines(idle: const Duration(seconds: 30));
      e.speechToText('whisper-base');
      async.flushMicrotasks();
      e.idle();
      async.elapse(const Duration(seconds: 29));
      expect(own.single.disposed, 0);
      // A new request stops the timer.
      e.speechToText('whisper-base');
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 5));
      expect(own.single.disposed, 0);
      // Two overlapping requests: released only after the last one.
      e.speechToText('whisper-base');
      async.flushMicrotasks();
      e.idle();
      async.elapse(const Duration(seconds: 31));
      expect(own.single.disposed, 0);
      e.idle();
      async.elapse(const Duration(seconds: 31));
      expect(own.single.disposed, 1);
      expect(e.holdsOwnModel, isFalse);
    });
  });

  test('Anfrage endet, bevor das Modell geladen ist: trotzdem freigegeben', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final e = DeviceRecognizerEngines(
        models: models,
        lookupShared: (_) async {
          await gate.future; // e.g. the 3 s ping of a busy app engine
          return null;
        },
        startWhisper: (_) async {
          final b = FakeBackend('eigen');
          own.add(b);
          return b;
        },
      );
      e.speechToText('whisper-base').ignore();
      async.flushMicrotasks();
      e.idle(); // request over (speech timeout, cancel)
      gate.complete();
      async.flushMicrotasks();
      expect(own.single.disposed, 0);
      async.elapse(const Duration(seconds: 31));
      expect(own.single.disposed, 1);
      expect(e.holdsOwnModel, isFalse);
    });
  });

  test(
    'Whisper der App antwortet nicht mehr: eigenes Modell übernimmt',
    () async {
      final e = DeviceRecognizerEngines(
        models: models,
        lookupShared: (_) async => _GoneBackend(
          const VoiceException(VoiceErrorKind.unavailable, 'weg'),
        ),
        startWhisper: (_) async {
          final b = FakeBackend('eigen');
          own.add(b);
          return b;
        },
      );
      final stt = await e.speechToText('whisper-base');
      expect(await text(stt), 'eigen');
      expect(e.holdsOwnModel, isTrue);
      await stt.transcribe(Int16List.fromList(List.filled(1600, 3000)));
      expect(own, hasLength(1));
    },
  );

  test('Modellfehler der App: kein Ausweichen', () async {
    var loads = 0;
    final e = DeviceRecognizerEngines(
      models: models,
      lookupShared: (_) async =>
          _GoneBackend(const VoiceException(VoiceErrorKind.failed, 'kaputt')),
      startWhisper: (_) async {
        loads++;
        return _BrokenBackend();
      },
    );
    final stt = await e.speechToText('whisper-base');
    await expectLater(
      text(stt),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.failed,
        ),
      ),
    );
    // Ein Fehler des Modells selbst lädt kein zweites Modell (N7).
    expect(loads, 0);
    expect(e.holdsOwnModel, isFalse);
  });

  test('eigenes Modell wird den anderen Engines angeboten und beim Freigeben '
      'zurückgezogen (B14)', () {
    fakeAsync((async) {
      final directory = _Directory();
      final e = DeviceRecognizerEngines(
        models: models,
        startWhisper: (files) async => FakeBackend('eigen'),
        lookupShared: (id) async => null,
        directory: directory,
      );
      e.speechToText('whisper-base');
      async.flushMicrotasks();
      expect(directory.published.keys, ['whisper-base']);
      e.idle();
      async.elapse(const Duration(seconds: 31));
      expect(directory.published, isEmpty);
      expect(directory.withdrawn, 1);
    });
  });

  test('idle ohne eigenes Modell tut nichts', () {
    fakeAsync((async) {
      engines().idle();
      async.elapse(const Duration(minutes: 1));
      expect(own, isEmpty);
    });
  });

  test('dispose gibt frei, danach keine Anfragen mehr', () async {
    final e = engines();
    await e.speechToText('whisper-base');
    await e.dispose();
    expect(own.single.disposed, 1);
    await expectLater(e.speechToText('whisper-base'), throwsStateError);
  });

  test('Fehler beim Freigeben werden nur protokolliert', () async {
    final e = DeviceRecognizerEngines(
      models: models,
      startWhisper: (_) async => _BrokenBackend(),
      lookupShared: (_) async => null,
    );
    await e.speechToText('whisper-base');
    await e.dispose();
  });

  test('Standard-Fabriken sind gesetzt', () {
    // Only constructs (sherpa-onnx is not loaded on the test host).
    DeviceRecognizerEngines(models: models);
  });
}

final class _GoneBackend implements WhisperBackend {
  _GoneBackend(this.error);

  final Object error;

  @override
  Future<WhisperResult> transcribe(Float32List samples, {String? language}) =>
      Future.error(error);

  @override
  Future<void> dispose() async {}
}

final class _BrokenBackend implements WhisperBackend {
  @override
  Future<WhisperResult> transcribe(Float32List samples, {String? language}) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async => throw StateError('kaputt');
}

final class _Directory implements WhisperDirectory {
  final published = <String, WhisperBackend>{};
  int withdrawn = 0;

  @override
  Future<WhisperBackend?> lookup(String modelId) async => null;

  @override
  void publish(String modelId, WhisperBackend backend) =>
      published[modelId] = backend;

  @override
  void withdraw(String modelId, WhisperBackend backend) {
    if (identical(published[modelId], backend)) {
      published.remove(modelId);
      withdrawn++;
    }
  }

  @override
  int liveModels() => published.length;
}
