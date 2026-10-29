import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Int16List counting(int start, int n) =>
    Int16List.fromList([for (var i = 0; i < n; i++) (start + i).toSigned(16)]);

void main() {
  group('WakeWordListener mit rollendem Ringpuffer (WP178)', () {
    late FakeAudioInput audio;
    late FakeWakeWordEngine engine;
    late FakeWakeVerifier verifier;
    late WakeWordListener listener;
    late List<WakeWordDetection> found;

    void setUpListener({
      Set<int> hits = const {},
      Duration tail = Duration.zero,
      Duration verifyTimeout = const Duration(seconds: 8),
      Duration? preRoll,
    }) {
      audio = FakeAudioInput();
      engine = FakeWakeWordEngine(hitAtFrame: hits);
      verifier = FakeWakeVerifier();
      listener = WakeWordListener(
        audio: audio,
        engine: engine,
        verifier: verifier,
        verifyTail: tail,
        verifyTimeout: verifyTimeout,
        preRoll: preRoll ?? AudioRingBuffer.defaultCapacity,
      );
      found = [];
      listener.detections.listen(found.add);
    }

    test(
      'Hält durchgehend rollend mindestens 5 Sekunden Audio im Speicher',
      () async {
        setUpListener();
        await listener.start();

        // 6 Sekunden Audio einspeisen (100 Frames à 960 Samples = 60 ms je Frame = 96000 Samples)
        const frameLen = 960;
        for (var i = 0; i < 100; i++) {
          audio.push(counting(i * frameLen, frameLen));
          await Future<void>.delayed(Duration.zero);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Mindestens 5 Sekunden gepuffert (80000 Samples)
        expect(listener.bufferedSamples, greaterThanOrEqualTo(5 * 16000));
        await listener.dispose();
      },
    );

    test('Bei Kandidat wird der Puffer während der Verifikation gehalten und wächst mit', () async {
      // Treffer bei Frame 50 (3 Sekunden im Stream, 48000 Samples)
      setUpListener(hits: {50});
      final gate = verifier.gate = Completer<void>();
      await listener.start();

      const frameLen = 960;
      // 51 Frames einspeisen (bis Treffer)
      for (var i = 0; i <= 50; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(verifier.calls, hasLength(1)); // Verifikation läuft

      final bufferedBefore = listener.bufferedSamples;

      // Während Stufe 2 prüft (z.B. Modell laden / Whisper), kommen 2 weitere Sekunden Audio
      for (var i = 51; i < 85; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Puffer ist gewachsen und hat nichts verworfen!
      expect(listener.bufferedSamples, bufferedBefore + (85 - 51) * frameLen);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(found, hasLength(1));

      // Der übergebene Puffer enthält die Vorlauf-Daten, das Weckwort und ALLES danach
      final pre = found.single.preRoll;
      expect(pre.last, ((85 * frameLen) - 1).toSigned(16));
      await listener.dispose();
    });

    test('Bei Verwurf (falscher Alarm) rollt der Puffer weiter und älteres > 5 s wird verworfen', () async {
      setUpListener(hits: {50});
      verifier.answer = (_) => false; // Verwurf!
      final gate = verifier.gate = Completer<void>();
      await listener.start();

      const frameLen = 960;
      for (var i = 0; i <= 50; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(verifier.calls, hasLength(1));

      // Weitere Frames einspeisen während der Prüfung
      for (var i = 51; i < 90; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Jetzt Verifikation beenden (wird verworfen)
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(found, isEmpty);

      // Puffer rollt wieder auf normale Kapazität (z.B. 5-6 s = max ~96000 Samples)
      expect(
        listener.bufferedSamples,
        inInclusiveRange(5 * 16000, 6 * 16000 + frameLen),
      );
      await listener.dispose();
    });

    test('Schnelles Sprechen: „Wendelin <Kommando>“ ohne Pause enthält das vollständige Kommando', () async {
      // 1 s Raum, 600 ms Weckwort (Ende bei 1600 ms = 25600 Samples = Frame 53 bei 480er Frames),
      // 1200 ms Kommando („schalte die Taschenlampe an“ = 19200 Samples = 40 Frames)
      setUpListener(hits: {53});
      final gate = verifier.gate = Completer<void>();
      await listener.start();

      const frameLen = 480; // 30 ms
      // Bis zum Weckwort-Ende einspeisen (54 Frames = 25920 Samples)
      for (var i = 0; i <= 53; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(verifier.calls, hasLength(1));

      // Sprecher spricht sofort ohne Pause weiter: das gesamte 1200 ms Kommando
      for (var i = 54; i < 94; i++) {
        audio.push(counting(i * frameLen, frameLen));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verifikation bestätigt den Treffer
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(found, hasLength(1));
      final detection = found.single;
      final preRoll = detection.preRoll;

      // Das Weckwort-Ende liegt genau an wakeEnd
      final wakeEndSample = detection.wakeEnd!;
      expect(wakeEndSample, greaterThan(0));

      // Nach dem Weckwort müssen lückenlos ALLE 40 Frames des Kommandos (19200 Samples) folgen!
      final commandSamples = preRoll.sublist(wakeEndSample);
      expect(commandSamples.length, 40 * frameLen);
      expect(commandSamples.first, (54 * frameLen).toSigned(16));
      expect(commandSamples.last, ((94 * frameLen) - 1).toSigned(16));

      // Keine einzige Sekunde fehlt!
      for (var i = 1; i < commandSamples.length; i++) {
        expect(
          commandSamples[i],
          (commandSamples[i - 1] + 1).toSigned(16),
          reason: 'Lücke bei Sample $i',
        );
      }

      await listener.dispose();
    });
  });
}
