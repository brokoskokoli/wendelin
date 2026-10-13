import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/recognizer/recognizer_host.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const frame = Duration(milliseconds: 30);

/// [RecognizerEngines] with fakes; [missing] makes [checkInstalled] fail.
final class FakeEngines implements RecognizerEngines {
  FakeEngines({List<Transcript> transcripts = const []})
    : stt = FakeSpeechToText(transcripts);

  final FakeSpeechToText stt;
  final vads = <FakeVoiceActivityDetector>[];
  final released = <VoiceActivityDetector>[];
  final checked = <String>[];
  final sttModels = <String>[];
  bool missing = false;

  /// Model [checkInstalled] answers with (`null` = the requested one).
  String? installedModel;
  int idles = 0;
  int disposed = 0;

  @override
  Future<String> checkInstalled(String modelId) async {
    checked.add(modelId);
    if (missing) {
      throw const VoiceException(VoiceErrorKind.modelMissing, 'fehlt');
    }
    return installedModel ?? modelId;
  }

  @override
  VoiceActivityDetector vad(double threshold) {
    final v = FakeVoiceActivityDetector(threshold: threshold);
    vads.add(v);
    return v;
  }

  @override
  void releaseVad(VoiceActivityDetector vad) => released.add(vad);

  @override
  Future<SpeechToText> speechToText(String modelId) async {
    sttModels.add(modelId);
    return stt;
  }

  @override
  void idle() => idles++;

  @override
  Future<void> dispose() async => disposed++;
}

/// Little-endian PCM16 bytes of [frames].
Uint8List bytesOf(List<Int16List> frames) {
  final all = Int16List(frames.fold(0, (n, f) => n + f.length));
  var o = 0;
  for (final f in frames) {
    all.setAll(o, f);
    o += f.length;
  }
  final out = ByteData(all.length * 2);
  for (var i = 0; i < all.length; i++) {
    out.setInt16(i * 2, all[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// 150 ms silence, 600 ms speech, 900 ms silence.
List<Int16List> utterance() =>
    AudioFrames.pattern('${'.' * 5}${'S' * 20}${'.' * 30}', frame: frame);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.recognizer');
  late List<MethodCall> toKotlin;
  late FakeEngines engines;
  late RecognizerHost host;

  setUp(() {
    toKotlin = [];
    engines = FakeEngines(
      transcripts: const [
        Transcript(text: ' Milch kaufen ', language: 'de', confidence: 0.8),
      ],
    );
    host = RecognizerHost(engines: engines, channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          toKotlin.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<Map<Object?, Object?>> events() => [
    for (final c in toKotlin)
      if (c.method == 'event') c.arguments as Map<Object?, Object?>,
  ];

  List<String> types() => [for (final e in events()) e['type']! as String];

  Future<void> start(Map<String, Object?> args) =>
      host.handle(MethodCall('start', {'session': 1, ...args}));

  Future<void> audio(List<Int16List> frames, {int session = 1}) async {
    for (final f in frames) {
      await host.handle(
        MethodCall('audio', {
          'session': session,
          'pcm': bytesOf([f]),
        }),
      );
    }
    await pumpEventQueue();
  }

  test(
    'ohne Spiegel, nur base installiert: Erkennung mit base (WP33)',
    () async {
      engines.installedModel = 'whisper-base';
      // Kein „model“ in der Anfrage: Standard whisper-small.
      await start({'language': 'de-DE'});
      await audio(utterance());
      expect(types(), ['began', 'ended', 'result']);
      expect(engines.checked, ['whisper-small']);
      expect(engines.sttModels, ['whisper-base']);
    },
  );

  test('attach meldet „ready“', () async {
    await host.attach();
    expect(toKotlin.single.method, 'ready');
  });

  test('Äußerung: Beginn, Ende, Ergebnis; Mikrofon gestoppt', () async {
    await start({
      'language': 'de-DE',
      'model': 'whisper-small',
      'sttLanguage': 'fr',
      'vadThreshold': 0.6,
      'minSpeechMs': 300,
    });
    await audio(utterance());
    expect(types(), ['began', 'ended', 'result']);
    final result = events().last;
    expect(result['session'], 1);
    expect(result['text'], 'Milch kaufen');
    expect(result['confidence'], 0.8);
    expect(result.containsKey('language'), isFalse);
    // EXTRA_LANGUAGE wins over the setting; model and VAD from the request.
    expect(engines.stt.calls.single.language, 'de');
    expect(engines.checked, ['whisper-small']);
    expect(engines.sttModels, ['whisper-small']);
    expect(engines.vads.single.threshold, 0.6);
    expect(engines.released, engines.vads);
    expect(engines.idles, 1);
    expect(toKotlin.where((c) => c.method == 'stopAudio').single.arguments, {
      'session': 1,
    });
  });

  test('ohne EXTRA_LANGUAGE gilt die Sprache der Einstellungen', () async {
    await start({'sttLanguage': 'fr'});
    await audio(utterance());
    expect(engines.stt.calls.single.language, 'fr');
  });

  test('Einstellung „automatisch“: Whisper erkennt die Sprache', () async {
    await start({'sttLanguage': ''});
    await audio(utterance());
    expect(engines.stt.calls.single.language, isNull);
  });

  test('Audio vor dem Start der Sitzung geht nicht verloren', () async {
    final gate = Completer<void>();
    final slow = _SlowEngines(engines, gate.future);
    host = RecognizerHost(engines: slow, channel: channel);
    final starting = start(const {});
    await audio(utterance());
    gate.complete();
    await starting;
    await pumpEventQueue();
    expect(types(), ['began', 'ended', 'result']);
  });

  test('Modell fehlt: Fehler modelMissing, kein Mikrofon-Ereignis', () async {
    engines.missing = true;
    await start(const {});
    expect(types(), ['error']);
    expect(events().single['error'], 'modelMissing');
    expect(events().single['message'], 'fehlt');
    expect(engines.vads, isEmpty);
    // Later audio of that session is ignored.
    await audio(utterance());
    expect(types(), ['error']);
  });

  test('nicht unterstützte Sprache: Fehler language', () async {
    await start({'language': 'es-ES'});
    expect(events().single['error'], 'language');
    expect(engines.checked, isEmpty);
  });

  test('Prüfung wirft etwas anderes: Fehler client', () async {
    host = RecognizerHost(
      engines: _ThrowingEngines(StateError('x')),
      channel: channel,
    );
    await start(const {});
    expect(events().single['error'], 'client');
    host = RecognizerHost(
      engines: _ThrowingEngines(
        const VoiceException(VoiceErrorKind.failed, 'kaputt'),
      ),
      channel: channel,
    );
    toKotlin.clear();
    await start(const {});
    expect(events().single['error'], 'client');
    expect(events().single['message'], 'kaputt');
  });

  test('Stille: speechTimeout', () async {
    await start(const {});
    await audio(AudioFrames.pattern('.' * 300, frame: frame));
    expect(types(), ['error']);
    expect(events().single['error'], 'speechTimeout');
  });

  test(
    'stop beendet das Zuhören, die bisherige Sprache wird erkannt',
    () async {
      await start(const {});
      await audio(AudioFrames.pattern('..SSSSSSSSSS', frame: frame));
      await host.handle(const MethodCall('stop', {'session': 1}));
      await pumpEventQueue();
      expect(types(), ['began', 'ended', 'result']);
    },
  );

  test('stop während des Kaltstarts: bisherige Sprache wird erkannt', () async {
    // Kotlin buffers start, audio and stop while the engine starts; the
    // stop must not get lost while the models are checked.
    final gate = Completer<void>();
    host = RecognizerHost(
      engines: _SlowEngines(engines, gate.future),
      channel: channel,
    );
    final starting = start(const {});
    await audio(AudioFrames.pattern('..SSSSSSSSSS', frame: frame));
    await host.handle(const MethodCall('stop', {'session': 1}));
    gate.complete();
    await starting;
    await pumpEventQueue();
    expect(types(), ['began', 'ended', 'result']);
    // All frames up to the stop, nothing after it.
    expect(engines.stt.calls.single.samples, 12 * 480);
  });

  test('stop während des Kaltstarts ohne Sprache: noMatch', () async {
    final gate = Completer<void>();
    host = RecognizerHost(
      engines: _SlowEngines(engines, gate.future),
      channel: channel,
    );
    final starting = start(const {});
    await audio(AudioFrames.pattern('.....', frame: frame));
    await host.handle(const MethodCall('stop', {'session': 1}));
    await audio(utterance()); // after the stop: ignored
    gate.complete();
    await starting;
    await pumpEventQueue();
    expect(types(), ['error']);
    expect(events().single['error'], 'noMatch');
    expect(engines.stt.calls, isEmpty);
  });

  test('cancel: keine weiteren Ereignisse', () async {
    await start(const {});
    await audio(AudioFrames.pattern('..SSSS', frame: frame));
    await host.handle(const MethodCall('cancel', {'session': 1}));
    await audio(utterance());
    expect(types(), ['began']);
    expect(engines.stt.calls, isEmpty);
  });

  test('cancel während das Modell geprüft wird: nichts startet', () async {
    final gate = Completer<void>();
    host = RecognizerHost(
      engines: _SlowEngines(engines, gate.future),
      channel: channel,
    );
    final starting = start(const {});
    await host.handle(const MethodCall('cancel', {'session': 1}));
    gate.complete();
    await starting;
    expect(engines.vads, isEmpty);
    expect(types(), isEmpty);
  });

  test('fremde Sitzung: audio, stop, cancel werden ignoriert', () async {
    await start(const {});
    await audio(utterance(), session: 2);
    await host.handle(const MethodCall('stop', {'session': 2}));
    await host.handle(const MethodCall('cancel', {'session': 2}));
    expect(types(), isEmpty);
    await audio(utterance());
    expect(types(), ['began', 'ended', 'result']);
  });

  test('neuer Start bricht die laufende Sitzung ab', () async {
    await start(const {});
    await audio(AudioFrames.pattern('..SSSS', frame: frame));
    await host.handle(const MethodCall('start', {'session': 2}));
    await audio(utterance());
    await audio(utterance(), session: 2);
    final sessions = [for (final e in events()) e['session']];
    expect(sessions, [1, 2, 2, 2]);
  });

  test('Mikrofon-Fehler: permission bzw. audio', () async {
    await start(const {});
    await host.handle(
      const MethodCall('audioError', {'session': 1, 'code': 'permission'}),
    );
    await pumpEventQueue();
    expect(events().single['error'], 'permission');
    toKotlin.clear();
    await host.handle(const MethodCall('start', {'session': 2}));
    await host.handle(
      const MethodCall('audioError', {'session': 2, 'code': 'audio'}),
    );
    await pumpEventQueue();
    expect(events().single['error'], 'audio');
  });

  test('shutdown bricht ab und gibt die Modelle frei', () async {
    await start(const {});
    await audio(AudioFrames.pattern('..SSSS', frame: frame));
    await host.handle(const MethodCall('shutdown'));
    await audio(utterance());
    expect(types(), ['began']);
    expect(engines.disposed, 1);
  });

  test('Dienst weg (kein Kanal): kein Absturz', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await start(const {});
    await audio(utterance());
    expect(engines.stt.calls, hasLength(1));
  });

  test('Kanal-Fehler werden geschluckt', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'gone');
        });
    await start(const {});
    await audio(utterance());
    expect(engines.stt.calls, hasLength(1));
  });

  test('unbekannte Aufrufe und Argumente', () async {
    expect(await host.handle(const MethodCall('unknown')), isNull);
    await host.handle(const MethodCall('audio', 'kaputt'));
    expect(toKotlin, isEmpty);
  });

  group('RecognizerRequest.fromArgs', () {
    test('Standardwerte bei fehlenden oder ungültigen Werten', () {
      for (final args in <Object?>[
        null,
        'x',
        {
          'session': 'x',
          'language': ' ',
          'model': 'llama',
          'sttLanguage': 'es',
          'vadThreshold': 1.5,
          'minSpeechMs': 5000,
        },
      ]) {
        final r = RecognizerRequest.fromArgs(args);
        expect(r.session, 0);
        expect(r.language, isNull);
        expect(r.model, 'whisper-small');
        expect(r.sttLanguage, isNull);
        expect(r.vadThreshold, 0.5);
        expect(r.minSpeechMs, 200);
      }
    });

    test('gültige Werte', () {
      final r = RecognizerRequest.fromArgs({
        'session': 7,
        'language': 'en-GB',
        'model': 'whisper-small',
        'sttLanguage': 'de',
        'vadThreshold': 0.4,
        'minSpeechMs': 300,
      });
      expect(r.session, 7);
      expect(r.language, 'en-GB');
      expect(r.model, 'whisper-small');
      expect(r.sttLanguage, 'de');
      expect(r.vadThreshold, 0.4);
      expect(r.endpoint.minSpeech, const Duration(milliseconds: 300));
      expect(r.endpoint.endSilence, const Duration(milliseconds: 800));
      expect(r.endpoint.maxDuration, const Duration(seconds: 30));
    });
  });

  group('ChannelAudioInput', () {
    test('Frames vor start werden nachgeliefert, stop meldet sich', () async {
      var stops = 0;
      final input = ChannelAudioInput(() async => stops++)
        ..push(
          bytesOf([
            Int16List.fromList(const [1, -2]),
          ]),
        )
        ..push(Uint8List(1)); // too short: ignored
      expect(input.isRunning, isFalse);
      final frames = <Int16List>[];
      final sub = input.start().listen(frames.add);
      input.push(
        bytesOf([
          Int16List.fromList(const [300]),
        ]),
      );
      await pumpEventQueue();
      expect(frames.map((f) => f.toList()), [
        [1, -2],
        [300],
      ]);
      expect(input.isRunning, isTrue);
      expect(input.start, throwsStateError);
      await input.stop();
      await input.stop();
      expect(stops, 1);
      input
        ..push(bytesOf([Int16List(4)]))
        ..fail(StateError('ignored'));
      expect(input.start, throwsStateError);
      await sub.cancel();
    });

    test('end: gepufferte Frames, dann Ende; danach nichts mehr', () async {
      final input = ChannelAudioInput(() async {})
        ..push(
          bytesOf([
            Int16List.fromList(const [5]),
          ]),
        )
        ..end()
        ..end()
        ..push(
          bytesOf([
            Int16List.fromList(const [6]),
          ]),
        )
        ..fail(StateError('ignored'));
      final frames = await input.start().toList();
      expect(frames.map((f) => f.toList()), [
        [5],
      ]);
      await input.stop();
    });

    test('end nach start schließt den Stream', () async {
      final input = ChannelAudioInput(() async {});
      final frames = input.start().toList();
      input
        ..push(
          bytesOf([
            Int16List.fromList(const [7]),
          ]),
        )
        ..end();
      expect((await frames).single.toList(), [7]);
      await input.stop();
      input.end(); // after stop: no-op
    });

    test('Fehler vor start kommt im Stream', () async {
      final input = ChannelAudioInput(() async {})..fail(StateError('mic'));
      await expectLater(input.start(), emitsError(isStateError));
      await input.stop();
    });

    test('Fehler während der Aufnahme', () async {
      final input = ChannelAudioInput(() async {});
      final stream = input.start();
      input.fail(StateError('mic'));
      await expectLater(stream, emitsError(isStateError));
      await input.stop();
    });
  });

  test('eventArgs', () {
    expect(eventArgs(const RecognitionSpeechBegan()), {'type': 'began'});
    expect(eventArgs(const RecognitionSpeechEnded()), {'type': 'ended'});
    expect(
      eventArgs(const RecognitionFailed(RecognitionErrorKind.noMatch, 'x')),
      {'type': 'error', 'error': 'noMatch', 'message': 'x'},
    );
  });
}

final class _SlowEngines implements RecognizerEngines {
  _SlowEngines(this.inner, this.gate);

  final FakeEngines inner;
  final Future<void> gate;

  @override
  Future<String> checkInstalled(String modelId) async {
    await gate;
    return inner.checkInstalled(modelId);
  }

  @override
  VoiceActivityDetector vad(double threshold) => inner.vad(threshold);

  @override
  void releaseVad(VoiceActivityDetector vad) => inner.releaseVad(vad);

  @override
  Future<SpeechToText> speechToText(String modelId) =>
      inner.speechToText(modelId);

  @override
  void idle() => inner.idle();

  @override
  Future<void> dispose() => inner.dispose();
}

final class _ThrowingEngines extends FakeEngines {
  _ThrowingEngines(this.error);

  final Object error;

  @override
  Future<String> checkInstalled(String modelId) async => throw error;
}
