import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/wake/device_wake_parts.dart';
import 'package:wendelin/platform/wake/service_audio_input.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/platform/wake/wake_host.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../recognizer/recognizer_host_test.dart' show FakeEngines;

const channel = MethodChannel(wakeEngineChannelName);

final class _Parts implements WakeParts {
  _Parts({
    this.engineless = false,
    this.verdict = true,
    this.direct = false,
    this.holdMs,
    this.engineError,
    this.openError,
    this.errorsOnlyModel = false,
  });

  /// The errors hit only the classifier (the templates work).
  final bool errorsOnlyModel;

  final bool engineless;
  final bool direct;
  final int? holdMs;
  final Object? engineError;
  final Object? openError;
  bool verdict;
  Object? verifyError;
  int disposed = 0;
  int engines = 0;
  WakeDetector? lastDetector;
  bool? lastStation;
  WakeDetector? verifierDetector;

  @override
  Future<WakeWordEngine?> engine({
    WakeDetector detector = WakeDetector.templates,
    bool station = false,
  }) async {
    engines++;
    lastDetector = detector;
    lastStation = station;
    final hit = !errorsOnlyModel || detector == WakeDetector.model;
    final error = engineError;
    if (hit && error != null) throw error;
    if (hit && openError != null) return _OpenFails(openError!);
    return engineless
        ? null
        : FakeWakeWordEngine(direct: direct, holdMs: holdMs);
  }

  @override
  WakeVerifier verifier({WakeDetector detector = WakeDetector.templates}) {
    verifierDetector = detector;
    return _Verifier(
      this,
      detector == WakeDetector.model ? 'parakeet' : 'whisper',
    );
  }

  @override
  Future<void> dispose() async => disposed++;
}

/// An engine whose models cannot be opened (classifier file missing).
final class _OpenFails implements WakeWordEngine {
  _OpenFails(this.error);
  final Object error;

  @override
  Future<void> open(List<KeywordSpec> keywords) async => throw error;

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async => const [];

  @override
  void reset() {}

  @override
  Future<void> close() async {}
}

final class _Verifier implements WakeVerifier {
  _Verifier(this.parts, this.kind);
  final _Parts parts;

  @override
  final String kind;

  @override
  Future<bool> confirm(Int16List pcm) async {
    final e = parts.verifyError;
    if (e != null) throw e;
    return parts.verdict;
  }
}

Uint8List bytes(Int16List frame) =>
    frame.buffer.asUint8List(frame.offsetInBytes, frame.lengthInBytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<(String, Object?)> toKotlin;
  late List<String> logs;
  late ServiceAudioInput audio;
  late _Parts parts;
  late WakeHost host;

  Future<void> fromKotlin(String method, [Object? args]) async {
    final done = Completer<void>();
    unawaited(
      messenger.handlePlatformMessage(
        wakeEngineChannelName,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) => done.complete(),
      ),
    );
    await done.future;
  }

  List<String> calls() => [for (final (m, _) in toKotlin) m];

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: '${calls()} $logs');
  }

  Future<void> start({
    bool verify = false,
    _Parts? p,
    Map<String, Object?> extra = const {},
  }) async {
    parts = p ?? _Parts();
    audio = ServiceAudioInput(channel);
    host = WakeHost(parts: parts, audio: audio);
    await host.attach();
    await fromKotlin('run', {'verify': verify, ...extra});
    await until(() => calls().contains('startMic'));
  }

  // The Kotlin service sends 100 ms chunks.
  Future<void> hear(Int16List frame) =>
      fromKotlin('audio', {'pcm': bytes(frame)});

  setUp(() {
    toKotlin = [];
    logs = [];
    final saved = voiceLogSink;
    final savedEngine = voiceLogEngine;
    voiceLogSink = logs.add;
    voiceLogEngine = 'wake';
    addTearDown(() {
      voiceLogSink = saved;
      voiceLogEngine = savedEngine;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      toKotlin.add((call.method, call.arguments));
      return null;
    });
  });

  tearDown(() async {
    await fromKotlin('shutdown');
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('ready, dann hört der Dienst zu; ein Treffer gibt das Mikrofon '
      'frei und geht mit dem Pre-Roll an Kotlin', () async {
    await start();
    expect(calls().first, 'ready');
    await hear(Int16List(1600));
    await hear(FakeWakeWordEngine.markerFrame(1600));
    await until(() => calls().contains('hit'));
    await until(() => calls().contains('stopMic'));
    // WP68: hit first, the service keeps the microphone (it ignores the
    // later stopMic while it collects) until the overlay takes the audio.
    expect(calls().indexOf('hit'), lessThan(calls().indexOf('stopMic')));
    final hit = toKotlin.firstWhere((c) => c.$1 == 'hit').$2! as Map;
    expect(hit['kw'], 'wake');
    expect(hit['score'], '0.90');
    // Wake word end in the pcm and the stream position at its end: the
    // marker frame ends at sample 3200 of the stream, the pre-roll holds
    // all of it.
    expect(hit['pos'], 3200);
    expect(hit['end'], 3200);
    expect((hit['pcm'] as Uint8List).length, greaterThanOrEqualTo(3200));
    expect(logs.join('\n'), contains('wake-pause engine=wake reason=overlay'));
    // The overlay is gone: listening again.
    final starts = calls().where((c) => c == 'startMic').length;
    await fromKotlin('overlayClosed');
    await until(() => calls().where((c) => c == 'startMic').length > starts);
    expect(logs.join('\n'), contains('wake-resume'));
  });

  test('Konflikt (Telefonat) pausiert, Ende setzt fort; Konflikt und Overlay '
      'zusammen: erst wenn beide vorbei sind', () async {
    await start();
    await fromKotlin('conflict', {'reason': 'call'});
    await until(() => calls().contains('stopMic'));
    expect(logs.join('\n'), contains('wake-pause engine=wake reason=call'));
    var starts = calls().where((c) => c == 'startMic').length;
    await fromKotlin('conflict', {'reason': null});
    await until(() => calls().where((c) => c == 'startMic').length > starts);

    // Overlay und Aufnahme einer anderen App gleichzeitig.
    await hear(FakeWakeWordEngine.markerFrame(1600));
    await until(() => calls().contains('hit'));
    await fromKotlin('conflict', {'reason': 'recording'});
    starts = calls().where((c) => c == 'startMic').length;
    await fromKotlin('overlayClosed');
    await pumpEventQueue();
    expect(calls().where((c) => c == 'startMic').length, starts);
    await fromKotlin('conflict', {'reason': null});
    await until(() => calls().where((c) => c == 'startMic').length > starts);
  });

  test(
    'Konflikt bleibt bei erneutem run bestehen: kein Mikrofon bis zum Ende',
    () async {
      await start();
      await fromKotlin('conflict', {'reason': 'call'});
      await until(() => calls().contains('stopMic'));
      final starts = calls().where((c) => c == 'startMic').length;
      await fromKotlin('run', {'verify': true});
      await pumpEventQueue();
      expect(calls().where((c) => c == 'startMic').length, starts);
      await fromKotlin('conflict', {'reason': null});
      await until(() => calls().where((c) => c == 'startMic').length > starts);
    },
  );

  test(
    'Stufe 2: ohne Bestätigung kein Treffer; Fehler zählt als nein',
    () async {
      await start(verify: true, p: _Parts(verdict: false));
      final tail = [for (var i = 0; i < 12; i++) Int16List(1600)];
      Future<void> say() async {
        await hear(FakeWakeWordEngine.markerFrame(1600));
        for (final f in tail) {
          await hear(f);
        }
      }

      await say();
      await until(() => logs.any((l) => l.contains('wake-verify')));
      expect(logs.last, contains('result=no'));
      expect(calls(), isNot(contains('hit')));

      parts.verifyError = StateError('kaputt');
      // Past the lockout.
      for (var i = 0; i < 20; i++) {
        await hear(Int16List(1600));
      }
      await say();
      await until(() => logs.any((l) => l.contains('result=skip')));
      expect(logs.last, contains('error=statee'));
      expect(calls(), isNot(contains('hit')));

      parts.verifyError = null;
      parts.verdict = true;
      for (var i = 0; i < 20; i++) {
        await hear(Int16List(1600));
      }
      await say();
      await until(() => calls().contains('hit'));
      expect(logs.join('\n'), contains('wake-verify engine=wake result=ok'));
    },
  );

  test('ohne Nachprüfung: Treffer sofort, Log „skip“', () async {
    await start();
    await hear(FakeWakeWordEngine.markerFrame(1600));
    await until(() => calls().contains('hit'));
    expect(logs.join('\n'), contains('wake-verify engine=wake result=skip'));
    expect(
      logs.join('\n'),
      contains('wake-cand engine=wake stage=1 detector=templates score=0.900'),
    );
    expect(
      logs.join('\n'),
      contains(
        'wake-hit-stage engine=wake detector=templates '
        'stage=1-unchecked score=0.900 verifier=none',
      ),
    );
    expect(
      logs.join('\n'),
      contains('wake-decision engine=wake hold_ms=0 peak=0.900 path=unchecked'),
    );
  });

  test('wake-decision: abgelehnter Stufe-2-Kandidat wird geloggt', () async {
    await start(verify: true, p: _Parts(verdict: false, holdMs: 800));
    await hear(FakeWakeWordEngine.markerFrame(1600));
    for (var i = 0; i < 12; i++) {
      await hear(Int16List(1600));
    }
    await until(() => logs.any((l) => l.contains('result=no')));
    expect(
      logs.join('\n'),
      contains('wake-decision engine=wake hold_ms=800 peak=0.900 path=stage2'),
    );
    expect(calls(), isNot(contains('hit')));
  });

  test('wake-decision: Direkttreffer mit hold_ms > 0', () async {
    await start(verify: true, p: _Parts(direct: true, holdMs: 640));
    await hear(FakeWakeWordEngine.markerFrame(1600));
    await until(() => calls().contains('hit'));
    expect(
      logs.join('\n'),
      contains('wake-decision engine=wake hold_ms=640 peak=0.900 path=direct'),
    );
  });

  group('Erkennung (WP129)', () {
    test(
      'auto: Handy Vorlagen, Station Modell; run reicht Ort durch',
      () async {
        await start(extra: {'detector': 'auto'});
        expect(parts.lastDetector, WakeDetector.templates);
        expect(parts.lastStation, isFalse);
        await fromKotlin('run', {
          'verify': false,
          'detector': 'auto',
          'station': true,
        });
        await until(() => parts.engines == 2);
        expect(parts.lastDetector, WakeDetector.model);
        expect(parts.lastStation, isTrue);
        expect(
          logs.join('\n'),
          contains(
            'wake-listening engine=wake verify=false detector=model '
            'station=true',
          ),
        );
      },
    );

    test('fest gewählt gilt auch an der Station; unbekannt: auto', () async {
      await start(extra: {'detector': 'templates', 'station': true});
      expect(parts.lastDetector, WakeDetector.templates);
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await until(() => parts.engines == 2);
      expect(parts.lastDetector, WakeDetector.model);
      await fromKotlin('run', {'verify': false, 'detector': 'quatsch'});
      await until(() => parts.engines == 3);
      expect(parts.lastDetector, WakeDetector.templates);
    });

    test('gleiche Erkennung und gleicher Ort: kein Neustart', () async {
      await start(extra: {'detector': 'model'});
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await pumpEventQueue();
      expect(parts.engines, 1);
    });

    test('Modell fehlt und auch sonst nichts da: failed modelMissing, kein '
        'Mikrofon', () async {
      parts = _Parts(
        engineError: const VoiceException(VoiceErrorKind.modelMissing, 'x'),
      );
      audio = ServiceAudioInput(channel);
      host = WakeHost(parts: parts, audio: audio);
      await host.attach();
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await until(() => calls().contains('failed'));
      final failed = toKotlin.firstWhere((c) => c.$1 == 'failed').$2! as Map;
      expect(failed['reason'], 'modelMissing');
      // Das Log nennt den Grund lesbar (kebab), nicht als `?`.
      expect(
        logs.where((l) => l.contains('wake-failed')),
        contains(endsWith('reason=model-missing')),
      );
      expect(parts.engines, 2, reason: 'Modell, dann Vorlagen versucht');
      expect(calls(), isNot(contains('startMic')));
    });

    for (final viaOpen in [false, true]) {
      test('Modell fehlt (${viaOpen ? 'beim Öffnen' : 'beim Bauen'}), Vorlagen '
          'da: Rückfall auf Vorlagen, Dienst hört zu (WP140)', () async {
        const missing = VoiceException(VoiceErrorKind.modelMissing, 'x');
        parts = _Parts(
          engineError: viaOpen ? null : missing,
          openError: viaOpen ? missing : null,
          errorsOnlyModel: true,
        );
        audio = ServiceAudioInput(channel);
        host = WakeHost(parts: parts, audio: audio);
        await host.attach();
        await fromKotlin('run', {'verify': false, 'detector': 'model'});
        await until(() => calls().contains('startMic'));
        expect(calls(), isNot(contains('failed')));
        expect(parts.lastDetector, WakeDetector.templates);
        expect(
          logs,
          contains(
            allOf(contains('wake-fallback'), contains('reason=model-missing')),
          ),
        );
        // The service listens with the templates (not with the missing model).
        expect(
          logs,
          contains(
            allOf(contains('wake-listening'), contains('detector=templates')),
          ),
        );
      }, timeout: const Timeout(Duration(seconds: 10)));
    }

    test('Modell fehlt, keine Vorlagen: failed modelMissing (Hinweis in den '
        'Einstellungen)', () async {
      parts = _Parts(
        engineError: const VoiceException(VoiceErrorKind.modelMissing, 'x'),
        errorsOnlyModel: true,
        engineless: true,
      );
      audio = ServiceAudioInput(channel);
      host = WakeHost(parts: parts, audio: audio);
      await host.attach();
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await until(() => calls().contains('failed'));
      final failed = toKotlin.firstWhere((c) => c.$1 == 'failed').$2! as Map;
      expect(failed['reason'], 'modelMissing');
    });

    test('Modelldatei fehlt beim Öffnen: failed modelMissing (der Weg der '
        'Merkmalskette), kein Mikrofon', () async {
      parts = _Parts(
        openError: const VoiceException(VoiceErrorKind.modelMissing, 'x'),
      );
      audio = ServiceAudioInput(channel);
      host = WakeHost(parts: parts, audio: audio);
      await host.attach();
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await until(() => calls().contains('failed'));
      final failed = toKotlin.firstWhere((c) => c.$1 == 'failed').$2! as Map;
      expect(failed['reason'], 'modelMissing');
      expect(calls(), isNot(contains('startMic')));
    });

    test('anderer Fehler der Engine: failed engine-failed', () async {
      parts = _Parts(engineError: StateError('kaputt'));
      audio = ServiceAudioInput(channel);
      host = WakeHost(parts: parts, audio: audio);
      await host.attach();
      await fromKotlin('run', {'verify': false, 'detector': 'model'});
      await until(() => calls().contains('failed'));
      final failed = toKotlin.firstWhere((c) => c.$1 == 'failed').$2! as Map;
      expect(failed['reason'], 'engine-failed');
    });

    test(
      'sicherer Treffer: Stufe 1-direct, Whisper wird nicht gefragt',
      () async {
        await start(
          verify: true,
          p: _Parts(direct: true, verdict: false),
          extra: {'detector': 'model'},
        );
        await hear(FakeWakeWordEngine.markerFrame(1600));
        await until(() => calls().contains('hit'));
        final text = logs.join('\n');
        expect(text, contains('stage=1-direct'));
        expect(text, contains('verifier=none'));
        expect(text, contains('direct=true'));
        expect(text, isNot(contains('wake-verify')));
      },
    );

    test('Treffer im Band: Stufe 2-verified', () async {
      await start(verify: true, extra: {'detector': 'model'});
      await hear(FakeWakeWordEngine.markerFrame(1600));
      for (var i = 0; i < 12; i++) {
        await hear(Int16List(1600));
      }
      await until(() => calls().contains('hit'));
      expect(logs.join('\n'), contains('stage=2-verified'));
      // The log names the recognizer that decided (WP129 Parakeet).
      expect(logs.join('\n'), contains('verifier=parakeet'));
      expect(parts.verifierDetector, WakeDetector.model);
    });

    test('Vorlagen-Weg: Prüfer Whisper im Log', () async {
      await start(verify: true, extra: {'detector': 'templates'});
      await hear(FakeWakeWordEngine.markerFrame(1600));
      for (var i = 0; i < 12; i++) {
        await hear(Int16List(1600));
      }
      await until(() => calls().contains('hit'));
      expect(logs.join('\n'), contains('verifier=whisper'));
      expect(parts.verifierDetector, WakeDetector.templates);
    });
  });

  test('nichts eingelernt: der Dienst meldet failed', () async {
    parts = _Parts(engineless: true);
    audio = ServiceAudioInput(channel);
    host = WakeHost(parts: parts, audio: audio);
    await host.attach();
    await fromKotlin('run', {'verify': true});
    await until(() => calls().contains('failed'));
    final failed = toKotlin.firstWhere((c) => c.$1 == 'failed').$2! as Map;
    expect(failed['reason'], 'no-templates');
    expect(calls(), isNot(contains('startMic')));
  });

  test('Fehler des Mikrofons im Dienst: failed', () async {
    await start();
    await fromKotlin('audioError', {'message': 'IllegalStateException'});
    await until(() => calls().contains('failed'));
  });

  test(
    'geänderte Nachprüfung: neu gestartet; gleiche Einstellung: nichts',
    () async {
      await start();
      expect(parts.engines, 1);
      await fromKotlin('run', {'verify': false});
      await pumpEventQueue();
      expect(parts.engines, 1);
      await fromKotlin('run', {'verify': true});
      await until(() => parts.engines == 2);
    },
  );

  test('shutdown gibt Whisper und Mikrofon frei', () async {
    await start();
    await fromKotlin('shutdown');
    expect(parts.disposed, 1);
    expect(audio.isRunning, isFalse);
  });

  test('wake-alive mit Zählern, ohne Inhalt', () async {
    parts = _Parts();
    audio = ServiceAudioInput(channel);
    host = WakeHost(
      parts: parts,
      audio: audio,
      aliveEvery: const Duration(milliseconds: 20),
    );
    await host.attach();
    await fromKotlin('run', {'verify': false});
    await until(() => logs.any((l) => l.contains('wake-alive')));
    expect(
      logs.firstWhere((l) => l.contains('wake-alive')),
      matches(r'wake-alive engine=wake cand=0 ok=0 candPerH=0.0 okPerH=0.0'),
    );
  });

  group('LazyWhisperVerifier', () {
    test('lädt beim ersten Kandidaten und gibt danach frei', () async {
      final engines = FakeEngines(
        transcripts: const [Transcript(text: 'Wendelin, wie spät ist es')],
      );
      final v = LazyWhisperVerifier(engines: () async => engines);
      expect(engines.sttModels, isEmpty);
      expect(
        await v.confirm(Int16List(16000)..fillRange(0, 16000, 500)),
        isTrue,
      );
      expect(engines.checked, ['whisper-base']);
      expect(engines.idles, 1);
    });

    test('Fehler beim Laden: Ausnahme, aber idle() wird nicht doppelt '
        'gezählt', () async {
      final engines = FakeEngines()..missing = true;
      final v = LazyWhisperVerifier(engines: () async => engines);
      await expectLater(
        v.confirm(Int16List(100)),
        throwsA(isA<VoiceException>()),
      );
      expect(engines.idles, 0);
    });
  });

  group('DeviceWakeParts', () {
    WakeTemplates tpl(String id, double threshold) => WakeTemplates(
      speakerId: id,
      featureVersion: 'fake-1',
      threshold: threshold,
      embeddings: [
        Float32List.fromList([1, 0]),
      ],
    );

    Future<(ProviderContainer, SecretWakeTemplateStore)> container(
      List<WakeTemplates> sets,
    ) async {
      final secrets = InMemorySecretStore();
      final store = SecretWakeTemplateStore(secrets);
      await store.saveSpeakers([
        for (final t in sets) WakeSpeaker(id: t.speakerId, name: t.speakerId),
      ]);
      for (final t in sets) {
        await store.save(t);
      }
      final c = ProviderContainer(
        overrides: [
          wakeStoreProvider.overrideWithValue(store),
          wakeFeaturesFactoryProvider.overrideWithValue(
            () => FakeWakeFeatureExtractor(windowEvery: 100),
          ),
        ],
      );
      addTearDown(c.dispose);
      return (c, store);
    }

    test('Vorlagen aller Sprecher gehen in die Stufe 1', () async {
      final (c, _) = await container([tpl('a', 0.9), tpl('b', 0.8)]);
      final engine = await DeviceWakeParts(c).engine();
      expect(engine, isA<CandidateWakeEngine>());
      final e = engine! as CandidateWakeEngine;
      expect(
        [e.templates!.speakerId, ...e.moreTemplates.map((t) => t.speakerId)],
        ['a', 'b'],
      );
      expect(e.modelThreshold, isNull);
      expect(e.holdDuration, Duration.zero);
    });

    test(
      'Modell: Band je Ort aus dem Katalog, keine Vorlagen, '
      'Stille-Sperre (kein Pegel-Gate); Vorlagen-Engine hat die Sperre auch',
      () async {
        final (c, _) = await container([tpl('a', 0.9)]);
        WakeScoreBand band(bool station) =>
            station ? WakeClassifierRules.station : WakeClassifierRules.phone;
        for (final station in [false, true]) {
          final e =
              (await DeviceWakeParts(
                    ProviderContainer(
                      overrides: [
                        wakeClassifierFeaturesFactoryProvider.overrideWithValue(
                          () => FakeWakeFeatureExtractor(windowEvery: 100),
                        ),
                      ],
                    ),
                  ).engine(detector: WakeDetector.model, station: station))!
                  as CandidateWakeEngine;
          expect(e.templates, isNull);
          expect(e.modelThreshold, band(station).verifyFrom);
          expect(e.directThreshold, band(station).acceptFrom);
          expect(e.holdDuration, WakeClassifierRules.holdWindow);
          expect(e.silenceFloor, isNotNull);
          expect(e.silenceFloor!.minRms, WakeClassifierRules.silenceFloorRms);
          expect(e.silenceFloor!.ratio, 0, reason: 'kein Rauschboden-Faktor');
        }
        final t = (await DeviceWakeParts(c).engine())! as CandidateWakeEngine;
        expect(t.silenceFloor!.minRms, WakeClassifierRules.silenceFloorRms);
        expect(t.directThreshold, isNull);
      },
    );

    group('Stufe 2 mit Prüfer B (WP143)', () {
      WakeTemplates withSeq(Float32List frame) => WakeTemplates(
        speakerId: 'a',
        featureVersion: wakeVerifierBFeatureVersion,
        threshold: 0.5,
        embeddings: [
          Float32List.fromList([1, 0]),
        ],
        sequences: [
          for (var i = 0; i < 3; i++)
            WakeTemplateSequence(
              word: WakeTemplates.wordHw,
              values: Float32List(192)
                ..setAll(0, frame)
                ..setAll(96, frame),
            ),
        ],
      );

      Future<(DeviceWakeParts, List<String>)> parts(
        List<WakeTemplates> sets,
      ) async {
        final (c, _) = await container(sets);
        final live = Float32List(25 * 96);
        for (var f = 0; f < 25; f++) {
          live[f * 96] = 1;
        }
        final inner = ProviderContainer(
          parent: c,
          overrides: [
            wakeFeaturesFactoryProvider.overrideWithValue(
              () => FakeWakeFeatureExtractor(sequenceFor: (_) => live),
            ),
          ],
        );
        addTearDown(inner.dispose);
        final logs = <String>[];
        final saved = voiceLogSink;
        voiceLogSink = logs.add;
        addTearDown(() => voiceLogSink = saved);
        return (DeviceWakeParts(inner, useVerifierB: true), logs);
      }

      test('mit Folgen entscheidet B, kein Rückfall, Log verifier=b', () async {
        final f = Float32List(96)..[0] = 1;
        final (p, logs) = await parts([withSeq(f)]);
        final v = p.verifier(detector: WakeDetector.model);
        expect(
          await v.confirm(Int16List(48000)..fillRange(0, 48000, 900)),
          isTrue,
        );
        expect(v.kind, 'b');
        expect(
          logs.single,
          contains(
            'wake-decision engine=wake verifier=b score=1.0000 thr=0.6815',
          ),
        );
      });

      test('B lehnt ab: false, trotzdem kein Rückfall', () async {
        final f = Float32List(96)..[1] = 1; // orthogonal zum Live-Strom
        final (p, logs) = await parts([withSeq(f)]);
        final v = p.verifier(detector: WakeDetector.model);
        expect(
          await v.confirm(Int16List(48000)..fillRange(0, 48000, 900)),
          isFalse,
        );
        expect(logs.single, contains('verifier=b'));
      });

      test(
        'Vorlagen-Weg und ausgeschaltetes B bleiben bei Whisper/Parakeet',
        () async {
          final (c, _) = await container([]);
          expect(
            DeviceWakeParts(c).verifier(detector: WakeDetector.model),
            isA<PreferredWakeVerifier>(),
            reason: 'Platzhalter-mu: B ist aus',
          );
          expect(
            DeviceWakeParts(c, useVerifierB: true).verifier(),
            isA<LazyWhisperVerifier>(),
          );
        },
      );
    });

    test('niemand eingelernt: keine Engine', () async {
      final (c, _) = await container([]);
      expect(await DeviceWakeParts(c).engine(), isNull);
    });
  });
}
