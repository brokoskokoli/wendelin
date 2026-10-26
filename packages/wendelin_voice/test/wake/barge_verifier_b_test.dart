// WP151: Prüfer B beim Unterbrechen (Vorlagen statt Transkript).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Float32List _vec(List<double> head) {
  final v = Float32List(96);
  for (var i = 0; i < head.length; i++) {
    v[i] = head[i];
  }
  return v;
}

Float32List _flat(List<Float32List> rows) {
  final out = Float32List(rows.length * 96);
  for (var i = 0; i < rows.length; i++) {
    out.setAll(i * 96, rows[i]);
  }
  return out;
}

final class _Fallback implements BargeVerifier {
  int calls = 0;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    calls++;
    return const BargeVerdict('echo', null, null, 'transcript');
  }
}

void main() {
  // Live: 25 gleiche Frames in Richtung 0; Vorlagen mit Kosinus [cos].
  VerifierBBargeVerifier make({
    required double cos,
    required _Fallback fallback,
    bool templates = true,
    Object? error,
  }) {
    final row = _vec([cos, math.sqrt(1 - cos * cos)]);
    final live = Float32List(96)..[0] = 1;
    return VerifierBBargeVerifier(
      scorer: VerifierBScorer(
        mu: Float32List(96),
        threshold: 0.6815,
        templates: () async => [
          if (templates)
            WakeTemplates(
              speakerId: 's',
              featureVersion: wakeVerifierBFeatureVersion,
              threshold: 0.5,
              embeddings: [Float32List(4)],
              sequences: [
                for (var i = 0; i < 3; i++)
                  WakeTemplateSequence(word: 'hw', values: _flat([row, row])),
              ],
            ),
        ],
        features: () => FakeWakeFeatureExtractor(
          featureVersion: wakeVerifierBFeatureVersion,
          sequenceFor: (_) {
            if (error != null) throw error;
            return _flat([for (var i = 0; i < 25; i++) live]);
          },
        ),
      ),
      fallback: fallback,
    );
  }

  final clip = Int16List(16000 * 3)..fillRange(0, 16000 * 3, 3000);

  test(
    'Score über der Schwelle: Signal, Prüfer b und Score im Urteil',
    () async {
      final fb = _Fallback();
      final v = await make(
        cos: 0.9,
        fallback: fb,
      ).verify(clip, candidate: BargeInKeyword.wake);
      expect(v.keyword, BargeInKeyword.wake);
      expect(v.verifier, 'b');
      expect(v.score, closeTo(0.9, 1e-3));
      expect(fb.calls, 0);
    },
  );

  test('Score unter der Schwelle: verworfen, kein Transkript', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.3,
      fallback: fb,
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.keyword, isNull);
    expect(v.result, 'no');
    expect(v.verifier, 'b');
    expect(v.score, closeTo(0.3, 1e-3));
    expect(fb.calls, 0);
  });

  test('ohne Vorlagen mit Folgen: Transkript entscheidet', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.9,
      fallback: fb,
      templates: false,
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.result, 'echo');
    expect(fb.calls, 1);
  });

  test('Fehler von B: Transkript entscheidet (nie beide)', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.9,
      fallback: fb,
      error: StateError('x'),
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.verifier, 'transcript');
    expect(fb.calls, 1);
  });

  test('Stille im Ausschnitt: kein Signal von B', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.9,
      fallback: fb,
    ).verify(Int16List(16000), candidate: BargeInKeyword.wake);
    expect(v.keyword, isNull);
  });

  test('Echo-Filter bleibt im Transkript-Pfad', () async {
    final v = await TranscriptBargeVerifier(
      FixedTranscriptStt('Wendelin'),
      spokenText: () => 'Ich bin Wendelin.',
    ).verify(Int16List(16000), candidate: BargeInKeyword.wake);
    expect(v.result, 'echo');
    expect(v.verifier, 'transcript');
  });
}
