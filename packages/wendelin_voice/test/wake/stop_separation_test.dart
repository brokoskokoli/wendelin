// WP80: „Stopp“ muss sich von Stille und Echo trennen. Die Merkmale sind
// synthetisch: jedes Fenster hat 16 Embeddings à 6 Werte, der Hintergrund ist
// in jeder Aufnahme gleich (grosser gemeinsamer Anteil), das Wort belegt 5
// der 16 Zeitschritte.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _dim = 6, _frames = 16;
final _bg = [3.0, 3, 3, 3, 3, 3];
// Embedding-Muster des Worts (mittelwertfrei, je Zeitschritt etwas anders).
List<double> _word(int k) => [
  for (var i = 0; i < _dim; i++) 3.5 * math.sin(k * 1.3 + i * 2.1) + 0.5,
];

/// Fenster: Hintergrund, in den Schritten 7..11 das Wort (+ [noise]).
Float32List _window({required bool word, double noise = 0}) {
  final w = Float32List(_dim * _frames);
  for (var f = 0; f < _frames; f++) {
    final isWord = word && f >= 7 && f <= 11;
    for (var i = 0; i < _dim; i++) {
      w[f * _dim + i] =
          (isWord ? _bg[i] + _word(f)[i] : _bg[i]) +
          noise * math.sin(f * 7.0 + i * 3.0);
    }
  }
  return w;
}

WakeTemplates _stopTemplates() => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.9,
  embeddings: [_window(word: true), _window(word: true, noise: 0.15)],
);

WakeTemplates _wake() => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.9,
  embeddings: [Float32List.fromList(List.filled(_dim * _frames, -1))],
);

Int16List _pcm(int amp, [int n = 400]) =>
    Int16List.fromList([for (var i = 0; i < n; i++) i.isEven ? amp : -amp]);

Future<List<String>> _run(
  List<Float32List> windows,
  List<Int16List> frames, {
  double? tail,
  SpeechGate? gate,
  double gap = 0,
  double threshold = 0.9,
}) async {
  var i = 0;
  final e = CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: 100,
      windowFor: (end, _) =>
          WakeWindow(endSample: end, embedding: windows[i++ % windows.length]),
    ),
    templates: _wake(),
    stopTemplates: [_stopTemplates().withThreshold(threshold)],
    modelThreshold: null,
    refractory: Duration.zero,
    stopTailShare: tail,
    stopGate: gate,
    stopFloorGap: gap,
  );
  await e.open([KeywordSpec.wendelin]);
  final ids = <String>[];
  for (final f in frames) {
    ids.addAll([for (final h in await e.accept(f)) h.keywordId]);
  }
  return ids;
}

void main() {
  final silence = _window(word: false, noise: 0.1);
  final word = _window(word: true, noise: 0.1);
  const tail = 9 / 16;

  test('Ursache: im ganzen Fenster ist Stille dem Wort fast so ähnlich', () {
    final t = _stopTemplates().embeddings;
    double sim(Float32List w, {bool onlyTail = false}) => bestSimilarity(
      onlyTail ? Float32List.sublistView(w, _dim * 7) : w,
      onlyTail ? [for (final e in t) Float32List.sublistView(e, _dim * 7)] : t,
    );
    // Whole window: silence is above the 0.9 threshold, hardly below the word.
    expect(sim(silence), greaterThan(0.9));
    expect(sim(word) - sim(silence), lessThan(0.1));
    // Tail with the word: silence drops under the threshold, the word stays.
    expect(sim(silence, onlyTail: true), lessThan(0.9));
    expect(sim(word, onlyTail: true), greaterThan(0.97));
    expect(
      sim(word, onlyTail: true) - sim(silence, onlyTail: true),
      greaterThan(0.1),
    );
  });

  test(
    'vorher: Stille löst „Stopp“ aus (Nachstellung des Gerätebefunds)',
    () async {
      expect(await _run([silence], [Int16List(400)]), contains('stop'));
    },
  );

  test('Fenster-Ende: Stille löst nicht aus, das Wort schon', () async {
    expect(await _run([silence], [_pcm(2000)], tail: tail), isEmpty);
    expect(await _run([word], [_pcm(2000)], tail: tail), contains('stop'));
  });

  test('Pegel-Gate: Stille im Mikrofon löst nie aus, Sprache schon', () async {
    // The window looks like the word, the microphone delivers silence.
    expect(
      await _run([word], [Int16List(400), Int16List(400)], gate: SpeechGate()),
      isEmpty,
    );
    expect(
      await _run([word], [Int16List(400), _pcm(1500)], gate: SpeechGate()),
      contains('stop'),
    );
  });

  test('Echo-Fall: gleichmässig lautes Echo ist kein Sprachanstieg', () async {
    final gate = SpeechGate();
    final ids = <String>[];
    var i = 0;
    final e = CandidateWakeEngine(
      features: FakeWakeFeatureExtractor(
        windowEvery: 100,
        windowFor: (end, _) => WakeWindow(endSample: end, embedding: word),
      ),
      templates: _wake(),
      stopTemplates: [_stopTemplates()],
      modelThreshold: null,
      refractory: Duration.zero,
      stopGate: gate,
    );
    await e.open([KeywordSpec.wendelin]);
    // Steady echo (rms 300) for 3 s: its own level is the background.
    for (; i < 150; i++) {
      ids.addAll([for (final h in await e.accept(_pcm(300, 320))) h.keywordId]);
    }
    expect(ids, isEmpty);
    expect(gate.active, isFalse);
    // The user speaks: clearly above the echo.
    ids.addAll([for (final h in await e.accept(_pcm(3000, 320))) h.keywordId]);
    expect(ids, contains('stop'));
  });

  test('Hintergrund-Abstand: nur klar über dem gleitenden Niveau', () async {
    Float32List sim(double s) =>
        Float32List.fromList([math.sqrt(1 - s * s), s]);
    WakeTemplates two() => WakeTemplates(
      speakerId: 'a',
      featureVersion: 'fake-1',
      threshold: 0.95,
      embeddings: [
        Float32List.fromList([0, 1]),
      ],
    );
    final seq = <double>[...List.filled(15, 0.93), 0.96, 0.96, 0.96];
    var i = 0;
    final e = CandidateWakeEngine(
      features: FakeWakeFeatureExtractor(
        windowEvery: 100,
        windowFor: (end, _) =>
            WakeWindow(endSample: end, embedding: sim(seq[i++ % seq.length])),
      ),
      templates: WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.95,
        embeddings: [
          Float32List.fromList([1, 0]),
        ],
      ),
      stopTemplates: [two()],
      modelThreshold: null,
      refractory: Duration.zero,
      stopFloorGap: 0.05,
    );
    await e.open([KeywordSpec.wendelin]);
    var hits = await e.accept(Int16List(1800));
    // 0.96 is over the threshold, but not 0.05 over the 0.93 background.
    expect(hits, isEmpty);
    expect(e.stopFloor, closeTo(0.93, 0.01));
    seq
      ..clear()
      ..addAll([0.999, 0.999, 0.999]);
    i = 0;
    hits = await e.accept(Int16List(300));
    expect([for (final h in hits) h.keywordId], contains('stop'));
  });

  test(
    '„Wendelin“ bleibt unberührt von Gate, Fenster-Ende und Abstand',
    () async {
      final wake = Float32List.fromList(List.filled(_dim * _frames, -1));
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: wake),
        ),
        templates: _wake(),
        stopTemplates: [_stopTemplates()],
        modelThreshold: null,
        stopTailShare: tail,
        stopGate: SpeechGate(),
        stopFloorGap: 0.05,
      );
      await e.open([KeywordSpec.wendelin]);
      // Silent microphone: the main word is still found (own rules only).
      final hits = await e.accept(Int16List(400));
      expect(hits.first.keywordId, 'wake');
    },
  );

  group('SpeechGate', () {
    test(
      'Stille nie aktiv, Anstieg über Grundpegel und Mindestpegel aktiv',
      () {
        final g = SpeechGate();
        g.feed(_pcm(2, 1600));
        expect(g.active, isFalse);
        g.feed(_pcm(100, 320)); // 50 x floor but under the absolute minimum
        expect(g.active, isFalse);
        g.feed(_pcm(1000, 320));
        expect(g.active, isTrue);
        // Look-back: after 800 ms of calm it is over.
        g.feed(_pcm(2, 16000));
        expect(g.active, isFalse);
        g.reset();
        expect(g.floor, 0);
      },
    );
  });
}
