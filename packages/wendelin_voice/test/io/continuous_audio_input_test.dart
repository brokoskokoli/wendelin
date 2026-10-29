import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  audioInputContract(
    () => ContinuousAudioInput(
      FakeAudioInput(frames: AudioFrames.pattern('S.S.S.S.')),
    ),
    name: 'ContinuousAudioInput',
  );

  group('ContinuousAudioInput (WP178)', () {
    late FakeAudioInput source;
    late ContinuousAudioInput continuous;

    setUp(() {
      source = FakeAudioInput();
      continuous = ContinuousAudioInput(source);
    });

    tearDown(() async {
      await continuous.close();
    });

    test('Startet die unterliegende Quelle beim ersten Aufruf', () async {
      expect(source.isRunning, isFalse);
      expect(source.startCount, 0);

      final stream = continuous.start();
      expect(source.isRunning, isTrue);
      expect(source.startCount, 1);
      expect(continuous.isRunning, isTrue);

      final frames = <Int16List>[];
      final sub = stream.listen(frames.add);

      source.push(Int16List(480));
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(1));

      await sub.cancel();
    });

    test(
      'stop() beendet die Phase, aber die Aufnahme läuft kontinuierlich weiter',
      () async {
        final stream1 = continuous.start();
        final frames1 = <Int16List>[];
        final sub1 = stream1.listen(frames1.add);

        source.push(Int16List(480));
        await Future<void>.delayed(Duration.zero);
        expect(frames1, hasLength(1));

        // Phase 1 endet (z.B. Spracheingabe fertig, Wechsel zu Sprachausgabe)
        await continuous.stop();
        await sub1.cancel();

        // Unterliegende Quelle läuft weiter! Nicht ständig neu starten/stoppen.
        expect(source.isRunning, isTrue);
        expect(source.startCount, 1);

        // Während der Sprachausgabe (Wendelin redet) rollt das Audio in den Ringpuffer
        final speechFrame = Int16List(480)..fillRange(0, 480, 777);
        source.push(speechFrame);
        await Future<void>.delayed(Duration.zero);

        expect(continuous.ring.length, 960);
        expect(continuous.ring.snapshot().last, 777);

        // Phase 2 (Folgefrage): Kein Neustart des Mikrofons nötig
        final stream2 = continuous.start();
        expect(source.startCount, 1); // Weiterhin nur 1 Start!

        final frames2 = <Int16List>[];
        final sub2 = stream2.listen(frames2.add);

        source.push(Int16List(480)..fillRange(0, 480, 888));
        await Future<void>.delayed(Duration.zero);
        expect(frames2, hasLength(1));
        expect(frames2.single.first, 888);

        await sub2.cancel();
        await continuous.stop();
      },
    );

    test(
      'Nicht benötigte Abschnitte können verworfen werden (discard)',
      () async {
        continuous.start();
        source.push(Int16List(480));
        await continuous.stop();

        expect(continuous.ring.length, 480);
        continuous.discard();
        expect(continuous.ring.length, 0);
      },
    );

    test('close() beendet die unterliegende Aufnahme endgültig', () async {
      continuous.start();
      expect(source.isRunning, isTrue);

      await continuous.close();
      expect(source.isRunning, isFalse);
      expect(continuous.isRunning, isFalse);
    });

    test(
      'Fehler in der Quelle wird an aktiven Stream weitergeleitet',
      () async {
        final stream = continuous.start();
        final errors = <Object>[];
        final sub = stream.listen((_) {}, onError: errors.add);

        source.fail(
          const VoiceException(VoiceErrorKind.unavailable, 'Hardware error'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        await sub.cancel();
      },
    );
  });
}
