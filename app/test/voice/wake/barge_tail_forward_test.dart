// WP146, WP184: Ablösen und Vorlauf gehen durch die Hüllen des Barge-in-Detektors.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/central_audio_input.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin/voice/wake/barge_meter.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../platform/voice/central_audio_input_test.dart';
import '../../support/fake_microphone.dart';
import '../../ui/helpers.dart';

void main() {
  testWidgets('MeteredAudioInput reicht detach an die Eingabe durch', (
    tester,
  ) async {
    final input = RecordAudioInput(
      FakePcmRecorder(),
      null,
      FakePcmRecorder.new,
    );
    final metered = MeteredAudioInput(input, BargeMeter(threshold: 0.7));
    final frames = <Int16List>[];
    final sub = metered.start().listen(frames.add);
    await pumpUntil(tester, () => frames.length >= 2);
    final end = metered.detach();
    expect(end, isNotNull);
    expect(input.isRunning, isFalse, reason: 'die Eingabe ist frei');
    final n = frames.length;
    await pumpUntil(
      tester,
      () => frames.length > n,
      reason: 'Frames kommen weiter',
    );
    await tester.runAsync(end!);
    await tester.runAsync(sub.cancel);
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

  testWidgets(
    'Lazy: Vorlauf geht durch, danach startet das nächste Mal wieder',
    (tester) async {
      final events = <bool>[];
      final recorder = FakePcmRecorder();
      final lazy = LazyWakeBargeInDetector(
        audio: RecordAudioInput(recorder, null, FakePcmRecorder.new),
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
      await tester.runAsync(lazy.start);
      await pumpUntil(tester, () => recorder.sent >= 2);
      expect(lazy.beginTail(), isTrue);
      expect(events, [true, false], reason: 'hört nicht mehr mit');
      final seen = recorder.sent;
      await pumpUntil(tester, () => recorder.sent >= seen + 2);
      final tail = lazy.endTail();
      expect(tail, isNotNull);
      expect(tail!.pcm, isNotEmpty);
      await pumpUntil(
        tester,
        () => !recorder.running,
        reason: 'keine zweite Aufnahme bleibt',
      );
      expect(lazy.isRunning, isFalse);
      await tester.runAsync(lazy.start);
      expect(lazy.isRunning, isTrue, reason: 'nächste Antwort: wieder aktiv');
      expect(recorder.running, isFalse, reason: 'die Eingabe wurde getauscht');
      await tester.runAsync(lazy.stop);
      await tester.runAsync(lazy.dispose);
    },
  );

  // Not fakeAsync: `StreamSubscription.cancel()` hands back a future of the
  // root zone, so the stop that follows the guard would not run on the fake
  // clock; `pumpUntil` alternates between fake time and the real event loop.
  testWidgets(
    'Lazy: nach Zeitüberschreitung des Vorlaufs startet start() neu',
    (tester) async {
      final recorder = FakePcmRecorder();
      final input = RecordAudioInput(recorder, null, FakePcmRecorder.new);
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

  testWidgets(
    'CentralAudioInput: MeteredAudioInput detach ermöglicht sofortigen Follow-Up ohne busy',
    (tester) async {
      final bridge = FakeCentralAudioBridge(available: true);
      final centralInput = CentralAudioInput(
        bridge: bridge,
        kind: 'session',
        isAndroid: true,
      );
      final metered = MeteredAudioInput(
        centralInput,
        BargeMeter(threshold: 0.7),
      );

      // Barge-in starts while speaking
      final bargeFrames = <Int16List>[];
      final bargeSub = metered.start().listen(bargeFrames.add);
      await pumpUntil(tester, () => centralInput.isRunning);
      await pumpUntil(tester, () => bridge.controllers.isNotEmpty);

      // Speaking ends, barge-in calls detach
      final closer = metered.detach();
      expect(closer, isNotNull);
      expect(centralInput.isRunning, isFalse, reason: 'sofort frei');

      // VoicePipeline starts follow-up on centralInput without busy error
      final followUpFrames = <Int16List>[];
      final followUpStream = centralInput.start();
      expect(centralInput.isRunning, isTrue);
      final followUpSub = followUpStream.listen(followUpFrames.add);
      await pumpUntil(tester, () => bridge.startedSubIds.length >= 2);

      // Feed frame to detached barge stream
      final subId1 = bridge.startedSubIds[0]!;
      bridge.controllers[subId1]?.add(Int16List.fromList([100]));
      await pumpUntil(tester, () => bargeFrames.isNotEmpty);
      expect(bargeFrames.single, [100]);

      // Feed frame to active follow-up stream
      final subId2 = bridge.startedSubIds[1]!;
      bridge.controllers[subId2]?.add(Int16List.fromList([200]));
      await pumpUntil(tester, () => followUpFrames.isNotEmpty);
      expect(followUpFrames.single, [200]);

      // Closer ends the detached stream
      await tester.runAsync(closer!);
      // Active follow-up is still running
      expect(centralInput.isRunning, isTrue);

      await tester.runAsync(centralInput.stop);
      expect(centralInput.isRunning, isFalse);

      await tester.runAsync(bargeSub.cancel);
      await tester.runAsync(followUpSub.cancel);
    },
  );
}
