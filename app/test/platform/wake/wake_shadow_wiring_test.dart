// WP171 Teil 4B: Schatten-Erkenner im Entwicklermodus, Verdrahtung in
// DeviceWakeParts und WakeHost (Kette, Dev-Flanke, Kostenlog).
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
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'wake_host_fixtures.dart';

WakeTemplates _tpl(String id, double threshold) => WakeTemplates(
  speakerId: id,
  featureVersion: 'fake-1',
  threshold: threshold,
  embeddings: [
    Float32List.fromList([1, 0]),
  ],
);

WakeWindow _window(int end, {double? model}) => WakeWindow(
  endSample: end,
  embedding: Float32List.fromList([1, 0]),
  modelScore: model,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> logs;

  setUp(() {
    logs = [];
    final saved = voiceLogSink;
    final savedEngine = voiceLogEngine;
    final savedDev = devLogEnabled;
    voiceLogSink = logs.add;
    voiceLogEngine = 'wake';
    addTearDown(() {
      voiceLogSink = saved;
      voiceLogEngine = savedEngine;
      devLogEnabled = savedDev;
    });
  });

  group('DeviceWakeParts.engine', () {
    // Which factory built the chain, and what it was given.
    late int plainChains, shadowChains;
    var note = 'not-installed';

    Future<DeviceWakeParts> parts(List<WakeTemplates> sets) async {
      final store = SecretWakeTemplateStore(InMemorySecretStore());
      await store.saveSpeakers([
        for (final t in sets) WakeSpeaker(id: t.speakerId, name: t.speakerId),
      ]);
      for (final t in sets) {
        await store.save(t);
      }
      plainChains = shadowChains = 0;
      final c = ProviderContainer(
        overrides: [
          wakeStoreProvider.overrideWithValue(store),
          wakeFeaturesFactoryProvider.overrideWithValue(() {
            plainChains++;
            return FakeWakeFeatureExtractor(
              windowEvery: 100,
              windowFor: (end, _) => _window(end),
            );
          }),
          wakeClassifierFeaturesFactoryProvider.overrideWithValue(
            () => FakeWakeFeatureExtractor(
              windowEvery: 100,
              windowFor: (end, _) => _window(end, model: 0.2),
            ),
          ),
          wakeShadowFeaturesFactoryProvider.overrideWithValue(({
            classifyCost,
            onNote,
          }) {
            shadowChains++;
            onNote?.call(note);
            return FakeWakeFeatureExtractor(
              windowEvery: 100,
              // The classifier is missing: no score on the windows.
              windowFor: (end, _) =>
                  _window(end, model: note == 'ok' ? 0.2 : null),
            );
          }),
        ],
      );
      addTearDown(c.dispose);
      return DeviceWakeParts(c);
    }

    Int16List loud() => Int16List(100)..fillRange(0, 100, 6000);

    setUp(() => note = 'not-installed');

    test('Dev an, Vorlagen entscheiden: Klassifikator-Kette, Fenster mit '
        'beiden Werten', () async {
      note = 'ok';
      final p = await parts([_tpl('a', 0.9)]);
      final e = (await p.engine(shadow: true))! as CandidateWakeEngine;
      expect(shadowChains, 1);
      expect(plainChains, 0);
      expect(e.modelThreshold, isNull, reason: 'Vorlagen entscheiden');
      final seen = <WakeWindowScores>[];
      e.windowSink = seen.add;
      await e.open([KeywordSpec.wendelin]);
      await e.accept(loud());
      expect(seen.single.model, 0.2);
      expect(seen.single.margin, closeTo(0.1, 1e-6));
      expect(seen.single.primaryModel, isFalse);
    });

    test('Dev aus: einfache Kette, kein Klassifikator, keine Schatten-Werte '
        'und keine Kosten', () async {
      final p = await parts([_tpl('a', 0.9), _tpl('b', 0.8)]);
      for (final d in [WakeDetector.templates, WakeDetector.model]) {
        final e = (await p.engine(detector: d))! as CandidateWakeEngine;
        expect(e.shadowTemplates, isEmpty);
        expect(e.shadowCost, isNull);
      }
      expect(shadowChains, 0, reason: 'kein Klassifikator-Aufbau');
      expect(plainChains, 1);
    });

    test('Dev an, Modell entscheidet: Klassifikator-Kette, alle Stimmen als '
        'Schatten-Vorlagen, Kosten gemessen', () async {
      final p = await parts([_tpl('a', 0.9), _tpl('b', 0.8)]);
      final e =
          (await p.engine(detector: WakeDetector.model, shadow: true))!
              as CandidateWakeEngine;
      expect(e.shadowTemplates.map((t) => t.speakerId), ['a', 'b']);
      expect(e.templates, isNull, reason: 'sie entscheiden nicht');
      expect(e.modelThreshold, isNotNull);
      expect(shadowChains, 0, reason: 'Modell-Weg: Klassifikator Pflicht');
      final seen = <WakeWindowScores>[];
      e.windowSink = seen.add;
      await e.open([KeywordSpec.wendelin]);
      await e.accept(loud());
      expect(seen.single.primaryModel, isTrue);
      expect(seen.single.margin, isNotNull);
      expect(p.fallbackStats.shadow.count, 1);
    });

    test('Dev an, Modell entscheidet, ohne Stimmen: Modell-Dienst läuft '
        '(keine Schatten-Vorlagen)', () async {
      final p = await parts([]);
      final e =
          (await p.engine(detector: WakeDetector.model, shadow: true))!
              as CandidateWakeEngine;
      expect(e.shadowTemplates, isEmpty);
    });

    test('Klassifikator fehlt: Vorlagen-Dienst läuft weiter, eine Zeile '
        'wake-shadow', () async {
      final p = await parts([_tpl('a', 0.9)]);
      final e = (await p.engine(shadow: true))! as CandidateWakeEngine;
      await e.open([KeywordSpec.wendelin]);
      // Silence floor: a few loud frames, then the window decides.
      var hits = <WakeWordHit>[];
      for (var i = 0; i < 12 && hits.isEmpty; i++) {
        hits = await e.accept(loud());
      }
      expect(hits, isNotEmpty, reason: 'Vorlagen entscheiden weiter');
      expect(hits.first.score, isNull);
      expect(logs.where((l) => l.contains('wake-shadow')), hasLength(1));
      expect(
        logs.firstWhere((l) => l.contains('wake-shadow')),
        contains('classifier=not-installed'),
      );
    });

    test('Dev aus: nie eine Zeile wake-shadow', () async {
      final p = await parts([_tpl('a', 0.9)]);
      await p.engine();
      expect(logs.where((l) => l.contains('wake-shadow')), isEmpty);
    });
  });

  group('WakeHost', () {
    late List<(String, Object?)> toKotlin;
    late FakeParts parts;
    late WakeHost host;

    Future<void> fromKotlin(String method, [Object? args]) async {
      final done = Completer<void>();
      unawaited(
        messenger.handlePlatformMessage(
          wakeEngineChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) => done.complete(),
        ),
      );
      await done.future;
    }

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 300 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue, reason: '${parts.shadows} $logs');
    }

    Future<void> start(Map<String, Object?> run, {Duration? alive}) async {
      parts = FakeParts();
      host = WakeHost(
        parts: parts,
        audio: ServiceAudioInput(channel),
        aliveEvery: alive ?? const Duration(minutes: 5),
      );
      await host.attach();
      await fromKotlin('run', {'verify': false, ...run});
      await until(() => toKotlin.any((c) => c.$1 == 'startMic'));
    }

    setUp(() {
      toKotlin = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        toKotlin.add((call.method, call.arguments));
        return null;
      });
    });

    tearDown(() async {
      await fromKotlin('shutdown');
      messenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'run: der Dev-Schalter geht als shadow in den Bau der Engine',
      () async {
        await start({'dev': true});
        expect(parts.shadows, [true]);
        await fromKotlin('run', {'verify': false, 'dev': false});
        await until(() => parts.shadows.length == 2);
        expect(parts.shadows, [true, false]);
      },
    );

    test('Dev-Flanke während des Laufs: genau ein Neustart je Flanke, gleicher '
        'Zustand startet nicht neu', () async {
      await start({'dev': false});
      expect(parts.shadows, [false]);
      await fromKotlin('devMode', {'on': true});
      await fromKotlin('devMode', {'on': true});
      await pumpEventQueue();
      expect(parts.shadows, [false, true], reason: 'ein Neustart, Schatten an');
      await fromKotlin('devMode', {'on': false});
      await fromKotlin('devMode', {'on': false});
      await pumpEventQueue();
      expect(parts.shadows, [false, true, false]);
      expect(parts.lastDetector, isNotNull);
    });

    test('Fenster-Senke des Listeners kommt bis zur Engine (Dekorierer '
        'reicht sie durch)', () async {
      await start({'dev': true});
      expect(parts.built.single.windowSink, isNotNull);
    });

    test('Rückfall auf Vorlagen (Modell fehlt) behält den Schatten', () async {
      parts = FakeParts(
        errorsOnlyModel: true,
        engineError: const VoiceException(VoiceErrorKind.modelMissing, 'x'),
      );
      host = WakeHost(parts: parts, audio: ServiceAudioInput(channel));
      await host.attach();
      await fromKotlin('run', {
        'verify': false,
        'dev': true,
        'detector': 'model',
      });
      await until(() => toKotlin.any((c) => c.$1 == 'startMic'));
      expect(parts.shadows, [true, true], reason: 'Modell, dann Vorlagen');
      expect(parts.lastDetector, WakeDetector.templates);
    });

    test('Dev-Flanke ohne laufenden Dienst: kein Bau', () async {
      parts = FakeParts();
      host = WakeHost(parts: parts, audio: ServiceAudioInput(channel));
      await host.attach();
      await fromKotlin('devMode', {'on': true});
      await pumpEventQueue();
      expect(parts.engines, 0);
    });

    test('Dev-Flanke behält Nachprüfung und Ort des Laufs', () async {
      await start({'dev': false, 'station': true, 'detector': 'model'});
      await fromKotlin('devMode', {'on': true});
      await until(() => parts.engines == 2);
      expect(parts.lastStation, isTrue);
      expect(parts.lastDetector, WakeDetector.model);
    });

    test(
      'wake-alive: Mittel und Höchstwert des Schattens nur im Dev',
      () async {
        await start({'dev': true}, alive: const Duration(milliseconds: 50));
        final feed = Timer.periodic(
          const Duration(milliseconds: 5),
          (_) => parts.fallbackStats.shadow.add(
            const Duration(microseconds: 2000),
          ),
        );
        addTearDown(feed.cancel);
        await until(() => logs.any((l) => l.contains('shMeanUs=2000')));
        final line = logs.firstWhere((l) => l.contains('shMeanUs'));
        expect(line, contains('shMaxUs=2000'));
        expect(line, matches(r'shN=\d+'));
      },
    );

    test('wake-alive ohne Dev: keine Schatten-Kosten', () async {
      await start({'dev': false}, alive: const Duration(milliseconds: 50));
      final feed = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) =>
            parts.fallbackStats.shadow.add(const Duration(microseconds: 2000)),
      );
      addTearDown(feed.cancel);
      await until(() => logs.any((l) => l.contains('wake-alive')));
      await until(
        () => logs.where((l) => l.contains('wake-alive')).length >= 2,
      );
      expect(logs.where((l) => l.contains('shMeanUs')), isEmpty);
    });
  });
}
