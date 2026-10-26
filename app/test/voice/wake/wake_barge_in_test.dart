import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/test_env.dart';

WakeTemplates tpl(double threshold) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: threshold,
  embeddings: [
    Float32List.fromList([1, 0]),
  ],
);

/// Runs [body] on a fake clock: the detector's frame timers and the test's
/// waits advance in 5 ms steps of virtual time, without real delays. Between
/// the steps the real event loop turns once, because futures that are
/// already completed in the root zone (a cancelled subscription) resume
/// there.
Future<void> runFake(Future<void> Function() body) async {
  final fake = FakeAsync();
  var done = false;
  Object? error;
  StackTrace? trace;
  fake.run((_) {
    body().then<void>(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        error = e;
        trace = s;
        done = true;
      },
    );
  });
  for (var i = 0; i < 20000 && !done; i++) {
    fake.elapse(const Duration(milliseconds: 5));
    await Future<void>.delayed(Duration.zero);
  }
  if (!done) throw TestFailure('Test hängt auch in virtueller Zeit');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

void ftest(String name, Future<void> Function() body) =>
    test(name, () => runFake(body));

class _SpyVerifier implements BargeVerifier {
  _SpyVerifier(this.onVerify);
  final void Function() onVerify;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    onVerify();
    return BargeVerdict.no;
  }
}

void main() {
  group('LazyWakeBargeInDetector', () {
    late FakeAudioInput audio;

    LazyWakeBargeInDetector make(
      List<WakeTemplates> sets,
      Float32List e, {
      Future<double?> Function()? margin,
      BargeVerifier Function(String Function())? verifier,
      bool? quietStart,
    }) {
      final quiet = quietStart ?? (verifier == null);
      audio = FakeAudioInput(
        // A quiet start (no level in the first window) tests the level gate.
        // With stage 2 a „Wendelin“ candidate needs level already in its first
        // window (WP126), so the stream is loud from the start there.
        frames: [
          if (quiet) Int16List(480),
          for (var i = 0; i < (quiet ? 3 : 4); i++)
            Int16List.fromList([
              for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
            ]),
        ],
        frameInterval: const Duration(milliseconds: 5),
      );
      return LazyWakeBargeInDetector(
        audio: audio,
        templates: () async => sets,
        marginOverride: margin,
        verifier: verifier,
        // The first (quiet) window is the candidate, the check follows on
        // the next (loud) frame.
        verifySettle: const Duration(milliseconds: 20),
        diagInterval: const Duration(milliseconds: 20),
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: e),
        ),
      );
    }

    ftest('onListening meldet true beim Start, false nach stop() und '
        'dispose', () async {
      final events = <bool>[];
      final d = LazyWakeBargeInDetector(
        audio: FakeAudioInput(
          frames: [Int16List(480)],
          frameInterval: const Duration(milliseconds: 5),
        ),
        templates: () async => [tpl(0.9)],
        onListening: ({required on}) => events.add(on),
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: Float32List.fromList([0, 1]),
          ),
        ),
      );
      await d.start();
      expect(events, [true]);
      await d.stop();
      expect(events, [true, false]);
      await d.start();
      await d.dispose(); // ended without stop()
      expect(events, [true, false, true, false]);
    });

    ftest('WP148: devClips gehen an den Detektor: Kandidat und Prüf-Ausschnitt '
        'als Clips, nur bei eingeschaltetem Modus', () async {
      Future<List<String>> run({required bool on}) async {
        final clips = <DevClip>[];
        final seen = <String>[];
        final d = LazyWakeBargeInDetector(
          audio: FakeAudioInput(
            frames: [
              for (var i = 0; i < 3; i++)
                Int16List.fromList([
                  for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
                ]),
            ],
            frameInterval: const Duration(milliseconds: 5),
          ),
          verifySettle: Duration.zero,
          templates: () async => [tpl(0.9)],
          verifier: (spoken) => _SpyVerifier(() => seen.add(spoken())),
          devClips: DevClips(enabled: () => on, write: clips.add),
          features: () => FakeWakeFeatureExtractor(
            windowEvery: 480,
            windowFor: (end, _) => WakeWindow(
              endSample: end,
              embedding: Float32List.fromList([1, 0]),
            ),
          ),
        );
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await d.dispose();
        expect(seen, isNotEmpty, reason: 'die Prüfung lief');
        return [for (final c in clips) c.event];
      }

      expect(await run(on: true), containsAll(['barge-cand', 'barge-verify']));
      expect(await run(on: false), isEmpty);
    });

    ftest('Echo-Filter: stop() leert, nur die letzten Sätze zählen', () async {
      final seen = <String>[];
      final d = LazyWakeBargeInDetector(
        audio: FakeAudioInput(
          frames: [
            Int16List.fromList([
              for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
            ]),
          ],
          frameInterval: const Duration(milliseconds: 5),
        ),
        verifySettle: Duration.zero,
        templates: () async => [tpl(0.9)],
        verifier: (spoken) => _SpyVerifier(() => seen.add(spoken())),
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: Float32List.fromList([1, 0]),
          ),
        ),
      );
      d
        ..spoke('Eins Stopp.')
        ..spoke('Zwei.')
        ..spoke('Drei.');
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await d.stop();
      final first = seen.first;
      expect(first, 'Zwei. Drei.');
      seen.clear();
      d.spoke('Neu.');
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await d.dispose();
      expect(seen.first, 'Neu.');
    });

    ftest('„Wendelin“ während der Sprachausgabe: Signal wake', () async {
      final d = make([tpl(0.9)], Float32List.fromList([1, 0]));
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      expect(d.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals.first.keyword, BargeInKeyword.wake);
      await d.stop();
      expect(d.isRunning, isFalse);
      expect(audio.isRunning, isFalse);
      await d.dispose();
    });

    ftest(
      'Neubau während der Ausgabe: laufender Detektor bleibt aktiv',
      () async {
        final d = make([tpl(0.9)], Float32List.fromList([1, 0]));
        final signals = <BargeInSignal>[];
        d.signals.listen(signals.add);
        await d.start();
        await d.disposeWhenIdle();
        expect(d.isRunning, isTrue);
        expect(audio.isRunning, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(signals, isNotEmpty);
        await d.stop();
        expect(audio.isRunning, isFalse);
        await d.dispose(); // idempotent
      },
    );

    group('Stufe 2: Gegenprüfung des Kandidaten (WP113, K84)', () {
      late List<String> lines;
      late void Function(String) saved;
      setUp(() {
        saved = voiceLogSink;
        lines = [];
        voiceLogSink = lines.add;
      });
      tearDown(() => voiceLogSink = saved);

      Float32List atSim(double sim, {bool second = false}) {
        final o = math.sqrt(1 - sim * sim);
        return Float32List.fromList(second ? [o, sim] : [sim, o]);
      }

      BargeVerifier Function(String Function()) heard(String text) =>
          (spoken) => TranscriptBargeVerifier(
            FixedTranscriptStt(text),
            spokenText: spoken,
          );

      Future<List<String>> run(
        LazyWakeBargeInDetector d, {
        String? spoken,
      }) async {
        final codes = <String>[];
        d.signals.listen((s) => codes.add(s.code));
        if (spoken != null) d.spoke(spoken);
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await d.dispose();
        return codes;
      }

      ftest(
        'verifySettle der App geht an den Detektor: Prüfung ohne Wartezeit',
        () async {
          var calls = 0;
          final d = make(
            [tpl(0.8)],
            Float32List.fromList([1, 0]),
            verifier: (_) => _SpyVerifier(() => calls++),
          );
          await run(d);
          // Settle 20 ms in make(); the default of 800 ms would not fit into
          // the 20 ms of audio.
          expect(calls, greaterThan(0));
        },
      );

      ftest('Kandidat unter der gelernten Schwelle kommt durch, Erkenner '
          'bestätigt „Wendelin“', () async {
        // Learned threshold 0.88, window 0.85: Stufe 1 alone (+0.05) rejects.
        final plain = make([tpl(0.88)], atSim(0.85));
        expect(await run(plain), isEmpty);
        final d = make(
          [tpl(0.88)],
          atSim(0.85),
          verifier: heard('Wendelin, hör mal'),
        );
        expect(await run(d), ['keyword-wake']);
        expect(
          lines.any(
            (l) => l.contains('barge-config') && l.contains('verify=true'),
          ),
          isTrue,
        );
        final cand = lines.firstWhere((l) => l.contains('barge-cand'));
        expect(cand, contains('kind=wake'));
        expect(cand, contains('sim=0.85'));
        final v = lines.firstWhere((l) => l.contains('barge-verify'));
        expect(v, contains('result=wake'));
        // Kein Inhalt außer dem erkannten Schlüsselwort.
        expect(lines.join('\n'), isNot(contains('hör mal')));
      });

      ftest(
        'Kandidatenschwelle nie unter candidateWakeFloor (WP134)',
        () async {
          // Calibrated threshold 0.40, margin -0.05 would give 0.35: speech
          // at 0.42 would reach stage 2 all the time.
          var asked = 0;
          BargeVerifier Function(String Function()) counting() =>
              (_) => _SpyVerifier(() => asked++);
          final low = make([tpl(0.40)], atSim(0.42), verifier: counting());
          expect(await run(low), isEmpty);
          expect(asked, 0);
          expect(
            lines.any(
              (l) => l.contains('barge-config') && l.contains('thr=0.45'),
            ),
            isTrue,
            reason: lines.join('\n'),
          );
          final ok = make([tpl(0.40)], atSim(0.47), verifier: counting());
          await run(ok);
          expect(asked, greaterThan(0));
        },
      );

      ftest('Rand der Kandidatenmarge -0,05 (WP134)', () async {
        // 0.88 - 0.05 = 0.83: 0.80 stays out, 0.85 gets in.
        var asked = 0;
        BargeVerifier Function(String Function()) spy() =>
            (_) => _SpyVerifier(() => asked++);
        await run(make([tpl(0.88)], atSim(0.80), verifier: spy()));
        expect(asked, 0);
        await run(make([tpl(0.88)], atSim(0.85), verifier: spy()));
        expect(asked, greaterThan(0));
      });

      ftest('Gegenprüfung verwirft: kein Signal, Log result=no', () async {
        final d = make([tpl(0.88)], atSim(0.85), verifier: heard('Guten Tag'));
        expect(await run(d), isEmpty);
        expect(
          lines.where((l) => l.contains('barge-verify')).first,
          contains('result=no'),
        );
      });

      ftest('Eigen-Echo: Wort im vorgelesenen Text zählt nicht', () async {
        final d = make([tpl(0.88)], atSim(0.85), verifier: heard('Wendelin'));
        expect(await run(d, spoken: 'Ich bin Wendelin.'), isEmpty);
        expect(
          lines.where((l) => l.contains('barge-verify')).first,
          contains('result=echo'),
        );
      });

      ftest('Eigen-Echo gilt nur für die letzten Sätze: später „Wendelin“ '
          'unterbricht', () async {
        final d = make([tpl(0.88)], atSim(0.85), verifier: heard('Wendelin'));
        d
          ..spoke('Ich bin Wendelin.')
          ..spoke('Das Wetter ist gut.')
          ..spoke('Morgen regnet es.');
        d.signals.listen((_) {});
        expect(await run(d), ['keyword-wake']);
      });

      ftest(
        'Ohne Prüfer bleibt der Aufschlag +0.05 (Schwellen unverändert)',
        () async {
          final d = make([tpl(0.8)], Float32List.fromList([1, 0]));
          await run(d);
          expect(lines.any((l) => l.contains('thr=0.85')), isTrue);
        },
      );
    });

    group('Diagnose (WP72)', () {
      late List<String> lines;
      late void Function(String) saved;
      setUp(() {
        saved = voiceLogSink;
        lines = [];
        voiceLogSink = lines.add;
      });
      tearDown(() => voiceLogSink = saved);

      ftest('barge-config, barge-diag je Intervall und barge-end', () async {
        final d = make([tpl(0.8)], Float32List.fromList([1, 0]));
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await d.stop();
        await d.dispose();
        expect(
          lines.any(
            (l) =>
                l.contains('barge-config') &&
                l.contains('margin=0.05') &&
                l.contains('thr=0.85') &&
                !l.contains('sthr='),
          ),
          isTrue,
          reason: lines.join('\n'),
        );
        final diag = lines.where((l) => l.contains('barge-diag')).toList();
        expect(diag, isNotEmpty);
        expect(diag.first, contains('t=1'));
        // WP134: no more fields of the removed stop word.
        for (final k in ['sthr=', 'sfloor=', 'sgap=', 'quiet=']) {
          expect(diag.first, isNot(contains(k)));
        }
        expect(diag.any((l) => l.contains('sim=1.00')), isTrue);
        final end = lines.singleWhere((l) => l.contains('barge-end'));
        expect(end, contains('frames=4'));
        expect(end, contains('sim=1.00'));
      });

      ftest(
        'Treffer erzeugt barge-hit mit Maxima; barge-end meldet das Maximum '
        'der ganzen Ausgabe',
        () async {
          // The first window hits (sim 1.00); later windows score low.
          audio = FakeAudioInput(
            frames: [
              // Speech level in the first window (silenceFloor, WP134).
              Int16List.fromList([
                for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
              ]),
              Int16List(480),
              Int16List(480),
            ],
            frameInterval: const Duration(milliseconds: 5),
          );
          final d = LazyWakeBargeInDetector(
            audio: audio,
            templates: () async => [tpl(0.9)],
            features: () => FakeWakeFeatureExtractor(
              windowEvery: 480,
              windowFor: (end, _) => WakeWindow(
                endSample: end,
                embedding: Float32List.fromList(end <= 480 ? [1, 0] : [0, 1]),
              ),
            ),
          );
          await d.start();
          await Future<void>.delayed(const Duration(milliseconds: 90));
          await d.stop();
          await d.dispose();
          final hit = lines.singleWhere((l) => l.contains('barge-hit'));
          expect(hit, contains('kind=keyword-wake'));
          expect(hit, contains('sim=1.00'));
          final end = lines.singleWhere((l) => l.contains('barge-end'));
          expect(
            end,
            contains('sim=1.00'),
            reason: 'nicht nur das letzte Fenster',
          );
        },
      );

      ftest('Ende ohne stop(): barge-end steht trotzdem im Log', () async {
        final d = make([tpl(0.8)], Float32List.fromList([1, 0]));
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await d.dispose();
        expect(lines.where((l) => l.contains('barge-end')), hasLength(1));
      });

      ftest(
        'WP134: digitale Stille löst ohne Prüfer nicht aus (silenceFloor)',
        () async {
          // Window matches the template perfectly, but the stream is silent.
          final d = LazyWakeBargeInDetector(
            audio: FakeAudioInput(
              frames: [for (var i = 0; i < 6; i++) Int16List(480)],
              frameInterval: const Duration(milliseconds: 5),
            ),
            templates: () async => [tpl(0.9)],
            features: () => FakeWakeFeatureExtractor(
              windowEvery: 480,
              windowFor: (end, _) => WakeWindow(
                endSample: end,
                embedding: Float32List.fromList([1, 0]),
              ),
            ),
          );
          final codes = <String>[];
          d.signals.listen((s) => codes.add(s.code));
          await d.start();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await d.dispose();
          expect(codes, isEmpty);
          // Control: the same window with speech-level audio does fire.
          final loud = make([tpl(0.9)], Float32List.fromList([1, 0]));
          final loudCodes = <String>[];
          loud.signals.listen((s) => loudCodes.add(s.code));
          await loud.start();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await loud.dispose();
          expect(loudCodes, contains('keyword-wake'));
        },
      );

      ftest('Mikrofon liefert nichts: frames=0 wird geloggt', () async {
        audio = FakeAudioInput(frames: const []);
        final d = LazyWakeBargeInDetector(
          audio: audio,
          templates: () async => [tpl(0.9)],
          diagInterval: const Duration(milliseconds: 10),
          features: () => FakeWakeFeatureExtractor(
            windowEvery: 480,
            windowFor: (end, _) => WakeWindow(
              endSample: end,
              embedding: Float32List.fromList([1, 0]),
            ),
          ),
        );
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 45));
        await d.dispose();
        expect(
          lines.where(
            (l) => l.contains('barge-diag') && l.contains('frames=0'),
          ),
          isNotEmpty,
        );
      });

      ftest('Entwickler-Schwelle ersetzt +0,05', () async {
        final d = make(
          [tpl(0.8)],
          Float32List.fromList([1, 0]),
          margin: () async => -0.05,
        );
        await d.start();
        await d.dispose();
        expect(
          lines.singleWhere((l) => l.contains('barge-config')),
          allOf(contains('margin=-0.05'), contains('thr=0.75')),
        );
      });
    });

    ftest('Neubau im Leerlauf beendet den Detektor sofort', () async {
      final d = make([tpl(0.9)], Float32List.fromList([1, 0]));
      await d.disposeWhenIdle();
      expect(d.isRunning, isFalse);
    });

    ftest(
      'Echo der eigenen Ausgabe (fremde Merkmale) löst nichts aus',
      () async {
        final echo = Float32List.fromList([-0.7, -0.7]);
        final d = make([tpl(0.9)], echo);
        final signals = <BargeInSignal>[];
        d.signals.listen(signals.add);
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(signals, isEmpty);
        await d.dispose();
      },
    );

    ftest('strenger als im Leerlauf: Schwelle + 0,05', () async {
      // Similarity 0.93 passes 0.9 but not 0.9 + 0.05.
      final d = make([tpl(0.9)], Float32List.fromList([0.93, 0.3676]));
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals, isEmpty);
      await d.dispose();
    });

    ftest('nichts eingelernt: still, mit Logzeile', () async {
      final lines = <String>[];
      final saved = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = saved);
      final d = make([], Float32List.fromList([1, 0]));
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(audio.isRunning, isFalse);
      expect(lines.join(), contains('barge-in-off'));
      await d.stop();
      await d.dispose();
    });
  });

  group('wakeBargeInDetectorProvider', () {
    ftest('null ohne Gesprächsmodus, sonst ein Detektor', () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      expect(c.read(wakeBargeInDetectorProvider), isNull);
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      final c2 = env.container();
      addTearDown(c2.dispose);
      await c2.read(voiceSettingsProvider.future);
      expect(c2.read(wakeBargeInDetectorProvider), isA<BargeInDetector>());
    });

    ftest('Einlernen oder Löschen baut den Detektor neu', () async {
      final env = TestEnv();
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      await c.read(wakeVerifyProvider.future);
      final first = c.read(wakeBargeInDetectorProvider);
      expect(c.read(wakeBargeInDetectorProvider), same(first));
      // Enrolling and deleting invalidate the detector provider.
      c.invalidate(wakeBargeInDetectorProvider);
      final second = c.read(wakeBargeInDetectorProvider);
      expect(second, isNotNull);
      expect(second, isNot(same(first)));
      await c.read(wakeSpeakersProvider.notifier).remove('x');
      expect(c.read(wakeBargeInDetectorProvider), isNot(same(second)));
    });

    ftest(
      'Verifier-Schalter baut den Detektor neu, Ring folgt dem Detektor',
      () async {
        final env = TestEnv();
        await env.storage.settings.set(
          voiceSettingsKey,
          const VoiceSettings(conversationMode: true),
        );
        final audio = FakeAudioInput(
          frames: [Int16List(480)],
          frameInterval: const Duration(milliseconds: 5),
        );
        final c = ProviderContainer(
          overrides: [
            ...env.overrides,
            audioInputProvider.overrideWithValue(audio),
            wakeFeaturesFactoryProvider.overrideWithValue(
              () => FakeWakeFeatureExtractor(
                windowEvery: 480,
                windowFor: (end, _) => WakeWindow(
                  endSample: end,
                  embedding: Float32List.fromList([0, 1]),
                ),
              ),
            ),
          ],
          retry: (_, _) => null,
        );
        addTearDown(c.dispose);
        await c.read(voiceSettingsProvider.future);
        await c.read(wakeVerifyProvider.future);
        final store = c.read(wakeStoreProvider);
        await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'A')]);
        await store.save(tpl(0.9));
        final first = c.read(wakeBargeInDetectorProvider)!;
        expect(c.read(bargeListeningProvider), isFalse);
        await first.start();
        expect(c.read(bargeListeningProvider), isTrue);
        await first.stop();
        expect(c.read(bargeListeningProvider), isFalse);
        await c.read(wakeVerifyProvider.notifier).set(enabled: false);
        expect(c.read(wakeBargeInDetectorProvider), isNot(same(first)));
      },
    );

    ftest('Start ohne vorgeladenes Verify: Neubau beim Laden stoert den Start nicht', () async {
      final env = TestEnv();
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      final audio = FakeAudioInput(
        frames: [Int16List(480)],
        frameInterval: const Duration(milliseconds: 5),
      );
      final c = ProviderContainer(
        overrides: [
          ...env.overrides,
          audioInputProvider.overrideWithValue(audio),
          wakeFeaturesFactoryProvider.overrideWithValue(
            () => FakeWakeFeatureExtractor(
              windowEvery: 480,
              windowFor: (end, _) => WakeWindow(
                endSample: end,
                embedding: Float32List.fromList([0, 1]),
              ),
            ),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      final store = c.read(wakeStoreProvider);
      await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'A')]);
      await store.save(tpl(0.9));
      // wakeVerifyProvider is still loading: it must not rebuild the
      // detector when it delivers its (default) value.
      final first = c.read(wakeBargeInDetectorProvider)!;
      await first.start();
      expect(c.read(bargeListeningProvider), isTrue);
      expect(audio.isRunning, isTrue);
      expect(c.read(wakeBargeInDetectorProvider), same(first));
      await first.stop();
    });

    ftest(
      'Alter Detektor nach Neubau meldet das Ende noch (Listening gehalten)',
      () async {
        final env = TestEnv();
        await env.storage.settings.set(
          voiceSettingsKey,
          const VoiceSettings(conversationMode: true),
        );
        final audio = FakeAudioInput();
        final c = ProviderContainer(
          overrides: [
            ...env.overrides,
            audioInputProvider.overrideWithValue(audio),
            wakeFeaturesFactoryProvider.overrideWithValue(
              () => FakeWakeFeatureExtractor(
                windowEvery: 480,
                windowFor: (end, _) => WakeWindow(
                  endSample: end,
                  embedding: Float32List.fromList([0, 1]),
                ),
              ),
            ),
          ],
          retry: (_, _) => null,
        );
        addTearDown(c.dispose);
        await c.read(voiceSettingsProvider.future);
        await c.read(wakeVerifyProvider.future);
        final store = c.read(wakeStoreProvider);
        await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'A')]);
        await store.save(tpl(0.9));
        final first = c.read(wakeBargeInDetectorProvider)!;
        await first.start();
        expect(c.read(bargeListeningProvider), isTrue);
        // Rebuild while the answer runs: the old ref is disposed.
        await c.read(wakeVerifyProvider.notifier).set(enabled: false);
        expect(c.read(wakeBargeInDetectorProvider), isNot(same(first)));
        await first.stop();
        expect(c.read(bargeListeningProvider), isFalse);
      },
    );
  });
}
