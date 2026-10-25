// WP146: Ablösen und Vorlauf gehen durch die Hüllen des Barge-in-Detektors.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin/voice/wake/barge_meter.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/fake_microphone.dart';
import '../../ui/helpers.dart';

void main() {
  test('MeteredAudioInput reicht detach an die Eingabe durch', () async {
    final input = RecordAudioInput(
      FakePcmRecorder(),
      null,
      null,
      FakePcmRecorder.new,
    );
    final metered = MeteredAudioInput(input, BargeMeter(threshold: 0.7));
    final frames = <Int16List>[];
    final sub = metered.start().listen(frames.add);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final end = metered.detach();
    expect(end, isNotNull);
    expect(input.isRunning, isFalse, reason: 'die Eingabe ist frei');
    final n = frames.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(frames.length, greaterThan(n), reason: 'Frames kommen weiter');
    await end!();
    await sub.cancel();
  });

  test('Eingabe ohne Ablösen: null (der Aufrufer stoppt wie bisher)', () {
    final metered = MeteredAudioInput(
      FakeAudioInput(),
      BargeMeter(threshold: 0.7),
    );
    expect(metered.detach(), isNull);
  });

  test('Lazy-Detektor ohne Engine: kein Vorlauf', () {
    final lazy = LazyWakeBargeInDetector(
      audio: FakeAudioInput(),
      templates: () async => [],
      features: FakeWakeFeatureExtractor.new,
    );
    expect(lazy.beginTail(), isFalse);
    expect(lazy.endTail(), isNull);
  });

  test(
    'Lazy: Vorlauf geht durch, danach startet das nächste Mal wieder',
    () async {
      final events = <bool>[];
      final recorder = FakePcmRecorder();
      final lazy = LazyWakeBargeInDetector(
        audio: RecordAudioInput(recorder, null, null, FakePcmRecorder.new),
        templates: () async => [
          WakeTemplates(
            speakerId: 'a',
            featureVersion: 'fake-1',
            threshold: 0.9,
            embeddings: [
              Float32List.fromList([1, 0]),
            ],
          ),
        ],
        onListening: ({required on}) => events.add(on),
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: Float32List.fromList([0, 1]),
          ),
        ),
      );
      await lazy.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(lazy.beginTail(), isTrue);
      expect(events, [true, false], reason: 'hört nicht mehr mit');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final tail = lazy.endTail();
      expect(tail, isNotNull);
      expect(tail!.pcm, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(recorder.running, isFalse, reason: 'keine zweite Aufnahme bleibt');
      expect(lazy.isRunning, isFalse);
      await lazy.start();
      expect(lazy.isRunning, isTrue, reason: 'nächste Antwort: wieder aktiv');
      expect(recorder.running, isFalse, reason: 'die Eingabe wurde getauscht');
      await lazy.stop();
      await lazy.dispose();
    },
  );

  // Not fakeAsync: `StreamSubscription.cancel()` hands back a future of the
  // root zone, so the stop that follows the guard would not run on the fake
  // clock; `pumpUntil` alternates between fake time and the real event loop.
  testWidgets(
    'Lazy: nach Zeitüberschreitung des Vorlaufs startet start() neu',
    (tester) async {
      final recorder = FakePcmRecorder();
      final input = RecordAudioInput(recorder, null, null, FakePcmRecorder.new);
      final lazy = LazyWakeBargeInDetector(
        audio: input,
        tailMax: const Duration(milliseconds: 40),
        templates: () async => [
          WakeTemplates(
            speakerId: 'a',
            featureVersion: 'fake-1',
            threshold: 0.9,
            embeddings: [
              Float32List.fromList([1, 0]),
            ],
          ),
        ],
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: Float32List.fromList([0, 1]),
          ),
        ),
      );
      await tester.runAsync(lazy.start);
      await pumpUntil(tester, () => recorder.starts > 0);
      expect(lazy.beginTail(), isTrue);
      expect(input.isRunning, isFalse);
      // Nobody calls endTail: the detector ends the detached recording itself.
      await pumpUntil(
        tester,
        () => !recorder.running,
        reason: 'die Aufnahme endete von selbst',
      );
      await tester.runAsync(lazy.start);
      expect(input.isRunning, isTrue, reason: 'hört wieder mit');
      await tester.runAsync(lazy.stop);
      await tester.runAsync(lazy.dispose);
    },
  );
}
