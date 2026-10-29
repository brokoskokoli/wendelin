// WP151: Prüfer B beim Unterbrechen (Vorlagen statt Transkript).
import 'dart:async';
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
    _Fallback? fallback,
    bool templates = true,
    Object? error,
    double threshold = 0.6815,
    String Function()? spoken,
  }) {
    final row = _vec([cos, math.sqrt(1 - cos * cos)]);
    final live = Float32List(96)..[0] = 1;
    return VerifierBBargeVerifier(
      scorer: VerifierBScorer(
        mu: Float32List(96),
        threshold: threshold,
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
      spokenText: spoken ?? () => '',
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

  test('Score unter der Schwelle ohne Fallback: verworfen', () async {
    final v = await make(
      cos: 0.3,
      fallback: null,
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.keyword, isNull);
    expect(v.result, 'no');
    expect(v.verifier, 'b');
    expect(v.score, closeTo(0.3, 1e-3));
  });

  test('Score unter der Schwelle mit Fallback (ODER-Logik): Transkript entscheidet', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.3,
      fallback: fb,
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.result, 'echo');
    expect(fb.calls, 1);
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

  test('Stille im Ausschnitt: B kann nicht entscheiden, Transkript', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.9,
      fallback: fb,
    ).verify(Int16List(16000), candidate: BargeInKeyword.wake);
    expect(v.keyword, isNull);
    expect(v.verifier, 'transcript');
    expect(fb.calls, 1);
  });

  test('Score genau auf der Schwelle: wake (>=)', () async {
    final probe = await make(
      cos: 0.9,
      fallback: _Fallback(),
    ).verify(clip, candidate: BargeInKeyword.wake);
    final v = await make(
      cos: 0.9,
      fallback: _Fallback(),
      threshold: probe.score!,
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(v.keyword, BargeInKeyword.wake);
    expect(v.verifier, 'b');
  });

  test(
    'Antwort enthält das Weckwort: Transkript mit Echo-Filter, B schweigt',
    () async {
      final fb = _Fallback();
      final v = await make(
        cos: 0.9,
        fallback: fb,
        spoken: () => 'Ich heiße Wendelin.',
      ).verify(clip, candidate: BargeInKeyword.wake);
      expect(fb.calls, 1);
      expect(v.verifier, 'transcript');
      expect(v.score, isNull);
    },
  );

  test('Antwort ohne Weckwort: B entscheidet', () async {
    final fb = _Fallback();
    final v = await make(
      cos: 0.9,
      fallback: fb,
      spoken: () => 'Das Wetter ist schön.',
    ).verify(clip, candidate: BargeInKeyword.wake);
    expect(fb.calls, 0);
    expect(v.verifier, 'b');
  });

  test('Prüfer B nach close(): kein neuer Extraktor, kein Score', () async {
    final gate = Completer<List<WakeTemplates>>();
    var made = 0;
    var loaded = 0;
    final scorer = VerifierBScorer(
      mu: Float32List(96),
      threshold: 0.6815,
      templates: () {
        loaded++;
        return gate.future;
      },
      features: () {
        made++;
        return FakeWakeFeatureExtractor(
          featureVersion: wakeVerifierBFeatureVersion,
          sequenceFor: (_) => Float32List(96 * 25),
        );
      },
    );
    final pending = scorer.score(clip, clip.length);
    await scorer.close();
    final row = _vec([1]);
    gate.complete([
      WakeTemplates(
        speakerId: 's',
        featureVersion: wakeVerifierBFeatureVersion,
        threshold: 0.5,
        embeddings: [Float32List(4)],
        sequences: [
          WakeTemplateSequence(word: 'hw', values: _flat([row, row])),
        ],
      ),
    ]);
    expect(await pending, isNull);
    expect(loaded, 1);
    expect(await scorer.score(clip, clip.length), isNull);
    expect(loaded, 1, reason: 'nach close() wird nichts mehr geladen');
    expect(made, 0);
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
