// WP143: Rechenvorschrift von Prüfer B gegen die Lieferung WP137
// (test/fixtures/wake_verifier_b/verifier_b_parity.json, synthetisch, erzeugt
// mit tool/train_wake_word/verifier_export.py; Beschreibung in
// docs/notes/wake-verifier-b.md der Lieferung).
//
// Toleranz 1e-4 (Wert der Lieferung): Python rechnet in float64, die App in
// float32 (Frames) mit double-Summen; gemessen liegen die Abweichungen bei
// etwa 1e-7. Ein Fehler im Zentrieren, im Versatz-Maximum oder im Top-3-Mittel
// ändert die Werte um 1e-2 und mehr.
//
// Der Zuschnitt der Vorlagen weicht mit Absicht vom Python-Trim ab (Probe
// WP137: kein Trim, dafür Auffüllen auf 1,0 s mit echtem Audio): geprüft
// werden nur die Grenzen vor dem Trim (`label_a`, `label_b`); `trim_*`,
// `clip_*` und `m` der Lieferung gelten für den Trim und stehen hier nicht.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const tolerance = 1e-4;

Map<String, dynamic> load(String name) =>
    jsonDecode(File('test/fixtures/wake_verifier_b/$name').readAsStringSync())
        as Map<String, dynamic>;

Float32List flat(List<dynamic> rows) => Float32List.fromList([
  for (final r in rows) ...[
    for (final v in r as List<dynamic>) (v as num).toDouble(),
  ],
]);

VerifierBSequence prep(List<dynamic> rows) =>
    VerifierBSequence.prepare(flat(rows), wakeVerifierBMu);

/// `x[i] = 0.4 * ((i*37 % 2001) - 1000) / 2000` als int16 (Formel der Datei).
Int16List live(int n) => Int16List.fromList([
  for (var i = 0; i < n; i++)
    (0.4 * ((i * 37 % 2001) - 1000) / 2000 * 32768).round(),
]);

void main() {
  final fx = load('verifier_b_parity.json');
  final pcm = fx['pcm'] as Map<String, dynamic>;

  test('mu der App = mu der Lieferung, Feature-Version gleich', () {
    final mu = load('wake_verifier_b_mu.json');
    expect(wakeVerifierBMuIsPlaceholder, isFalse);
    expect(wakeVerifierBFeatureVersion, mu['feature_version']);
    expect(fx['feature_version'], wakeVerifierBFeatureVersion);
    final want = (mu['mu'] as List).cast<num>();
    expect(wakeVerifierBMu.length, want.length);
    for (var i = 0; i < want.length; i++) {
      expect(wakeVerifierBMu[i], closeTo(want[i].toDouble(), 1e-5));
    }
  });

  test('Schwelle HW der App = Schwelle der Lieferung', () {
    final t = fx['thresholds_trainingsseite'] as Map<String, dynamic>;
    expect(
      WakeClassifierRules.verifierBThresholdHw,
      closeTo((t['HW'] as num).toDouble(), 5e-5),
    );
    expect(WakeClassifierRules.verifierBTopK, fx['topk']);
  });

  group('Werte je Kopf (cases)', () {
    for (final c
        in (fx['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final name = c['name'] as String;
      test(name, () {
        final queries = c['queries'] as List<dynamic>;
        final templates = c['templates'] as Map<String, dynamic>;
        final expected = c['expected'] as Map<String, dynamic>;
        for (final head in expected.keys) {
          final tpl = [
            for (final t in templates[head] as List<dynamic>)
              prep(t as List<dynamic>),
          ];
          final want = (expected[head] as List<dynamic>).cast<num>();
          expect(want, hasLength(queries.length));
          for (var q = 0; q < queries.length; q++) {
            expect(
              verifierBScore(prep(queries[q] as List<dynamic>), tpl),
              closeTo(want[q].toDouble(), tolerance),
              reason: '$head Ausschnitt $q',
            );
          }
        }
      });
    }
  });

  group('Ausschnitt live (pcm.live)', () {
    for (final c
        in (pcm['live'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final name = c['name'] as String;
      test(name, () {
        final end = c['decision_end_sample'] as int;
        final sig = live(
          ((c['signal'] as Map<String, dynamic>)['len'] as num).toInt(),
        );
        final b = verifierBLiveBounds(end);
        expect(b.from, c['a']);
        expect(b.to, c['b']);
        expect(verifierBAlign(end), c['e']);
        final clip = verifierBLiveClip(sig, end);
        expect(clip.length, c['seg_len']);
        final front = c['zeros_front'] as int, back = c['zeros_back'] as int;
        expect(clip.sublist(0, front).every((s) => s == 0), isTrue);
        expect(clip.sublist(clip.length - back).every((s) => s == 0), isTrue);
        // Kopierter Teil = Quelle[copy_lo, copy_hi) mal Verstärkung.
        final lo = c['copy_lo'] as int, hi = c['copy_hi'] as int;
        expect(hi - lo, clip.length - front - back);
        final peakIn = sig.sublist(lo, hi).map((s) => s.abs()).reduce(math.max);
        // Wie Python: trunc(x * peak / max * 32767).
        final gain = (c['peak_out'] as num) * 32767 / peakIn;
        for (var i = 0; i < hi - lo; i += 101) {
          expect(clip[front + i], closeTo(sig[lo + i] * gain, 1));
        }
        expect(
          clip.map((s) => s.abs()).reduce(math.max),
          closeTo((c['peak_out'] as num) * 32768, 1),
        );
      });
    }
  });

  group('Grenzen Vorlage (pcm.template, ohne Trim)', () {
    for (final c
        in (pcm['template'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final len = ((c['signal'] as Map<String, dynamic>)['len'] as num)
            .toInt();
        final b = verifierBTemplateBounds(
          len,
          (c['start_s'] as num).toDouble(),
          (c['end_s'] as num).toDouble(),
        );
        expect(b.from, c['label_a']);
        expect(b.to, c['label_b']);
        // Mindestlänge der Lieferung (m >= 2, ab 13920 Samples) ist hier
        // nicht Regel der App (sie füllt auf 1,0 s auf); der Fall
        // `usable_as_template: false` ist ein zu kurzer Zuschnitt, den die
        // App auffüllt statt verwirft. Die Höchstlänge gilt wie dort.
        final cutLen = b.to - b.from;
        expect(
          verifierBTemplateWindow(
                len,
                ((c['start_s'] as num) * 16000).toInt(),
                ((c['end_s'] as num) * 16000).toInt(),
              ) !=
              null,
          cutLen <= WakeClassifierRules.verifierBMaxTemplateSamples,
        );
      });
    }
  });
}
