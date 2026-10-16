import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
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

void main() {
  group('LazyWakeBargeInDetector', () {
    late FakeAudioInput audio;

    LazyWakeBargeInDetector make(
      List<WakeTemplates> sets,
      Float32List e, {
      List<WakeTemplates> stops = const [],
      Future<double?> Function()? margin,
    }) {
      audio = FakeAudioInput(
        // WP80: „Stopp“ needs speech-level sound after a quiet start.
        frames: [
          Int16List(480),
          for (var i = 0; i < 3; i++)
            Int16List.fromList([
              for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
            ]),
        ],
        frameInterval: const Duration(milliseconds: 5),
      );
      return LazyWakeBargeInDetector(
        audio: audio,
        templates: () async => sets,
        stopTemplates: () async => stops,
        marginOverride: margin,
        stopTail: null, // two-value fake embeddings have no time axis
        diagInterval: const Duration(milliseconds: 20),
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: e),
        ),
      );
    }

    test('„Wendelin“ während der Sprachausgabe: Signal wake', () async {
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

    test(
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

    WakeTemplates stopTpl(double threshold) => WakeTemplates(
      speakerId: 'a',
      featureVersion: 'fake-1',
      threshold: threshold,
      embeddings: [
        Float32List.fromList([0, 1]),
      ],
    );

    group('„Stopp“ am Fensterende (WP80)', () {
      // 16 values: the first 7 equal the template, the last 9 (the word's
      // tail) differ completely. Whole window: similarity ~0.99, tail: 0.
      Float32List vec(List<double> head, List<double> tail) =>
          Float32List.fromList([...head, ...tail]);
      final head = List<double>.filled(7, 10);
      final stopTemplate = WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.7,
        embeddings: [
          vec(head, [1, 0, 1, 0, 1, 0, 1, 0, 1]),
        ],
      );
      final mainTemplate = WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.9,
        embeddings: [Float32List(16)..[15] = 1],
      );

      Future<List<BargeInSignal>> run({
        double? tail,
        bool defaultTail = false,
      }) async {
        final a = FakeAudioInput(
          frames: [
            Int16List(480),
            for (var i = 0; i < 6; i++)
              Int16List.fromList([
                for (var j = 0; j < 480; j++) j.isEven ? 2000 : -2000,
              ]),
          ],
          frameInterval: const Duration(milliseconds: 5),
        );
        FakeWakeFeatureExtractor features() => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: vec(head, [0, 1, 0, 1, 0, 1, 0, 1, 0]),
          ),
        );
        final d = defaultTail
            ? LazyWakeBargeInDetector(
                audio: a,
                templates: () async => [mainTemplate],
                stopTemplates: () async => [stopTemplate],
                features: features,
              )
            : LazyWakeBargeInDetector(
                audio: a,
                templates: () async => [mainTemplate],
                stopTemplates: () async => [stopTemplate],
                stopTail: tail,
                features: features,
              );
        final signals = <BargeInSignal>[];
        d.signals.listen(signals.add);
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await d.dispose();
        return signals;
      }

      test(
        'Kontrolle: ohne Fensterende löst die Ganzfenster-Ähnlichkeit aus',
        () async {
          final signals = await run(tail: null);
          expect(signals.map((s) => s.keyword), contains(BargeInKeyword.stop));
        },
      );

      test(
        'Standard: die App schließt das Fensterende an, Echo löst nicht aus',
        () async {
          final signals = await run(defaultTail: true);
          expect(signals, isEmpty);
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

      test('barge-config, barge-diag je Intervall und barge-end', () async {
        final d = make(
          [tpl(0.8)],
          Float32List.fromList([1, 0]),
          stops: [stopTpl(0.7)],
        );
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
                l.contains('sthr=0.75'),
          ),
          isTrue,
          reason: lines.join('\n'),
        );
        final diag = lines.where((l) => l.contains('barge-diag')).toList();
        expect(diag, isNotEmpty);
        expect(diag.first, contains('t=1'));
        // WP80: background of „Stopp“ and level.
        expect(diag.first, contains('sfloor='));
        expect(diag.first, contains('quiet='));
        expect(diag.any((l) => l.contains('sim=1.00')), isTrue);
        final end = lines.singleWhere((l) => l.contains('barge-end'));
        expect(end, contains('frames=4'));
        expect(end, contains('sim=1.00'));
      });

      test('Treffer erzeugt barge-hit mit Maxima; barge-end meldet das Maximum '
          'der ganzen Ausgabe', () async {
        // The first window hits (sim 1.00); later windows score low.
        audio = FakeAudioInput(
          frames: [Int16List(480), Int16List(480), Int16List(480)],
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
      });

      test('barge-diag ohne „Stopp“-Vorlagen: sthr=-1', () async {
        final d = make([tpl(0.8)], Float32List.fromList([1, 0]));
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await d.dispose();
        final diag = lines.where((l) => l.contains('barge-diag'));
        expect(diag, isNotEmpty);
        expect(diag.every((l) => l.contains('sthr=-1')), isTrue);
      });

      test('Ende ohne stop(): barge-end steht trotzdem im Log', () async {
        final d = make([tpl(0.8)], Float32List.fromList([1, 0]));
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await d.dispose();
        expect(lines.where((l) => l.contains('barge-end')), hasLength(1));
      });

      test('Mikrofon liefert nichts: frames=0 wird geloggt', () async {
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

      test('Entwickler-Schwelle ersetzt +0,05', () async {
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

    test('Neubau im Leerlauf beendet den Detektor sofort', () async {
      final d = make([tpl(0.9)], Float32List.fromList([1, 0]));
      await d.disposeWhenIdle();
      expect(d.isRunning, isFalse);
    });

    test('„Stopp“ allein: Signal stop, ohne Vorlage still', () async {
      final spoken = Float32List.fromList([0, 1]);
      final d = make([tpl(0.9)], spoken, stops: [stopTpl(0.9)]);
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals.first.keyword, BargeInKeyword.stop);
      await d.dispose();

      final without = make([tpl(0.9)], spoken);
      final none = <BargeInSignal>[];
      without.signals.listen(none.add);
      await without.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(none, isEmpty);
      await without.dispose();
    });

    test(
      'Echo der eigenen Ausgabe (fremde Merkmale) löst nichts aus',
      () async {
        final echo = Float32List.fromList([-0.7, -0.7]);
        final d = make([tpl(0.9)], echo, stops: [stopTpl(0.9)]);
        final signals = <BargeInSignal>[];
        d.signals.listen(signals.add);
        await d.start();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(signals, isEmpty);
        await d.dispose();
      },
    );

    test('„Stopp“-Schwelle ebenfalls + 0,05', () async {
      final d = make(
        [tpl(0.9)],
        Float32List.fromList([0.3676, 0.93]),
        stops: [stopTpl(0.9)],
      );
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals, isEmpty);
      await d.dispose();
    });

    test('strenger als im Leerlauf: Schwelle + 0,05', () async {
      // Similarity 0.93 passes 0.9 but not 0.9 + 0.05.
      final d = make([tpl(0.9)], Float32List.fromList([0.93, 0.3676]));
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals, isEmpty);
      await d.dispose();
    });

    test('nichts eingelernt: still, mit Logzeile', () async {
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
    test('null ohne Gesprächsmodus, sonst ein Detektor', () async {
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

    test(
      'neu eingelerntes oder gelöschtes „Stopp“ baut den Detektor neu',
      () async {
        final env = TestEnv();
        await env.storage.settings.set(
          voiceSettingsKey,
          const VoiceSettings(conversationMode: true),
        );
        final c = env.container();
        addTearDown(c.dispose);
        await c.read(voiceSettingsProvider.future);
        await c.read(stopLearnedProvider.future);
        final first = c.read(wakeBargeInDetectorProvider);
        expect(c.read(wakeBargeInDetectorProvider), same(first));
        // Learning „Stopp“ alone does not rebuild in the middle of a session.
        c.invalidate(stopLearnedProvider);
        await c.read(stopLearnedProvider.future);
        expect(c.read(wakeBargeInDetectorProvider), same(first));
        // Enrolling and deleting invalidate the detector provider.
        c.invalidate(wakeBargeInDetectorProvider);
        final second = c.read(wakeBargeInDetectorProvider);
        expect(second, isNotNull);
        expect(second, isNot(same(first)));
        await c.read(wakeSpeakersProvider.notifier).remove('x');
        expect(c.read(wakeBargeInDetectorProvider), isNot(same(second)));
      },
    );
  });
}
