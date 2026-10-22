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

  group('Listener', () {
    late FakeAudioInput audio;
    late FakeWakeVerifier verifier;
    late WakeWordListener listener;
    late List<WakeWordDetection> found;

    Future<void> run(int amp, {bool? normalize}) async {
      audio = FakeAudioInput();
      verifier = FakeWakeVerifier();
      listener = WakeWordListener(
        audio: audio,
        engine: FakeWakeWordEngine(hitAtFrame: {19}),
        verifier: verifier,
        verifyTail: Duration.zero,
        verifyNormalize: normalize ?? WakeClassifierRules.verifyNormalize,
      );
      found = [];
      listener.detections.listen(found.add);
      await listener.start();
      for (var i = 0; i < 25; i++) {
        audio.push(_tone(480, amp));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test(
      'Standard an: Whisper bekommt Spitze 0,5, der Pre-Roll bleibt',
      () async {
        expect(WakeClassifierRules.verifyNormalize, isTrue);
        await run(900);
        expect(_peak(verifier.calls.single), inInclusiveRange(16383, 16385));
        expect(found, hasLength(1));
        expect(_peak(found.single.preRoll), lessThanOrEqualTo(900));
        await listener.dispose();
      },
    );

    test('Schalter aus: Ausschnitt unverändert', () async {
      await run(900, normalize: false);
      expect(_peak(verifier.calls.single), lessThanOrEqualTo(900));
      await listener.dispose();
    });

    test('Stille wird nicht verstärkt (Spitze 0 bleibt 0)', () async {
      await run(0);
      expect(_peak(verifier.calls.single), 0);
      await listener.dispose();
    });
  });
}
