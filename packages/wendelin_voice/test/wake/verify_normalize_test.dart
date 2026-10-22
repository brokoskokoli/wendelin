// WP129: Pegelnormalisierung des Stufe-2-Ausschnitts (Spitze 0,5 wie WP133),
// nie für Stille, nie für den Pre-Roll des Verbrauchers.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

int _peak(Int16List x) => x.fold(0, (p, s) => math.max(p, s.abs()));

Int16List _tone(int n, int amp) => Int16List.fromList([
  for (var i = 0; i < n; i++) (amp * math.sin(i * 0.3)).round(),
]);

void main() {
  group('normalizePeak', () {
    test('leiser Ausschnitt wird auf Spitze 0,5 angehoben, Form bleibt', () {
      final x = _tone(4000, 800);
      final y = normalizePeak(x);
      expect(_peak(y), inInclusiveRange(16383, 16385));
      // Verhältnis erhalten (Gewinn 20,48).
      expect(y[10] / x[10], closeTo(20.48, 0.2));
      expect(_peak(x), 800, reason: 'Eingang bleibt unverändert');
    });

    test('lauter Ausschnitt wird auf 0,5 gesenkt, nie übersteuert', () {
      final y = normalizePeak(_tone(4000, 32767));
      expect(_peak(y), inInclusiveRange(16383, 16385));
    });

    test('Stille und Spitze unter der Untergrenze werden nicht verstärkt', () {
      final zeros = Int16List(3000);
      expect(normalizePeak(zeros), same(zeros));
      final hush = _tone(3000, 40); // Rauschen im geschlossenen Raum
      final out = normalizePeak(hush);
      expect(_peak(out), 40);
      expect(out, orderedEquals(hush));
      final edge = _tone(3000, WakeClassifierRules.verifyMinPeak);
      expect(_peak(normalizePeak(edge)), greaterThan(16000));
    });

    test('leerer Ausschnitt', () {
      expect(normalizePeak(Int16List(0)), isEmpty);
    });
  });

  group('Prüfer', () {
    Future<FixedTranscriptStt> run(
      int amp, {
      required bool normalize,
      String kind = 'whisper',
    }) async {
      final stt = FixedTranscriptStt('Wendelin');
      final v = TranscriptWakeVerifier(stt, normalize: normalize, kind: kind);
      expect(await v.confirm(_tone(8000, amp)), isTrue);
      expect(v.kind, kind);
      return stt;
    }

    test('Parakeet-Regel an: Ausschnitt auf Spitze 0,5', () async {
      final stt = await run(
        900,
        normalize: WakeClassifierRules.verifyNormalizeParakeet,
        kind: 'parakeet',
      );
      expect(stt.lastPeak, inInclusiveRange(16383, 16385));
    });

    test('Whisper-Regel aus: Ausschnitt unverändert', () async {
      final stt = await run(
        900,
        normalize: WakeClassifierRules.verifyNormalizeWhisper,
      );
      expect(stt.lastPeak, lessThanOrEqualTo(900));
    });

    test('Standard ist die Whisper-Regel (aus)', () async {
      final stt = FixedTranscriptStt('Wendelin');
      await TranscriptWakeVerifier(stt).confirm(_tone(8000, 900));
      expect(stt.lastPeak, lessThanOrEqualTo(900));
    });

    test('Stille wird nicht verstärkt (Spitze 0 bleibt 0)', () async {
      final stt = await run(0, normalize: true, kind: 'parakeet');
      expect(stt.lastPeak, 0);
    });
  });

  group('Listener', () {
    test('Pre-Roll und Ausschnitt kommen unverändert beim Prüfer an', () async {
      final audio = FakeAudioInput();
      final verifier = FakeWakeVerifier();
      final listener = WakeWordListener(
        audio: audio,
        engine: FakeWakeWordEngine(hitAtFrame: {19}),
        verifier: verifier,
        verifyTail: Duration.zero,
      );
      final found = <WakeWordDetection>[];
      listener.detections.listen(found.add);
      await listener.start();
      for (var i = 0; i < 25; i++) {
        audio.push(_tone(480, 900));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_peak(verifier.calls.single), lessThanOrEqualTo(900));
      expect(found, hasLength(1));
      await listener.dispose();
    });
  });
}
