// WP171 Teil 4A: beide Stufe-1-Erkenner auf einer Merkmalskette, ein
// Archivfall je Äußerung. Audio synthetisch, die Erkennung ein Skript.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Int16List counting(int from, [int n = 480]) =>
    Int16List.fromList([for (var i = 0; i < n; i++) (from + i) % 30000]);

typedef W = ({double? model, double? margin});

final class _Archive {
  _Archive({this.on = true});
  final bool on;
  final entries = <DevArchiveEntry>[];
  final clips = <DevClip>[];
  late final hook = DevClips(
    enabled: () => on,
    write: clips.add,
    archive: DevArchive(
      write: entries.add,
      context: (source) => {'src': source},
      takeStt: () => const {},
    ),
  );
}

/// Only the WP155 interface (classifier score), no windows.
final class _ScoreOnly implements WakeWordEngine, ScoringWakeEngine {
  _ScoreOnly(this.scores);
  final Map<int, double> scores;
  @override
  void Function(int endSample, double score)? scoreSink;
  int _frames = 0;
  @override
  Future<void> open(List<KeywordSpec> keywords) async {}
  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final i = _frames++;
    scoreSink?.call((i + 1) * 480, scores[i] ?? 0);
    return const [];
  }

  @override
  void reset() => _frames = 0;
  @override
  Future<void> close() async {}
}

final class _MeanCounter implements WakeFeatureExtractor {
  _MeanCounter(this.embedding);
  final Float32List embedding;
  int meanReads = 0;
  int _end = 0;
  @override
  String get featureVersion => 'fake-1';
  @override
  Float32List? get embeddingMean {
    meanReads++;
    return null;
  }

  @override
  String? get centerId => null;
  @override
  Future<void> open() async {}
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    _end += frame.length;
    return [WakeWindow(endSample: _end, embedding: embedding, modelScore: 0.1)];
  }

  @override
  void reset() => _end = 0;
  @override
  Future<void> close() async {}
}

Float32List v(List<double> x) => Float32List.fromList(x);
final _word = v([1, 0, 0, 0]);
final _other = v([0, 1, 0, 0]);
WakeTemplates _tpl() => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.5,
  embeddings: [_word],
);

void main() {
  group('Listener: ein Fall je Äußerung aus beiden Erkennern', () {
    late _Archive arch;
    late FakeAudioInput audio;
    late WakeWordListener listener;
    late FakeWakeVerifier verifier;
    final detections = <WakeWordDetection>[];

    Future<void> setUp0(WakeWordEngine engine, {bool on = true}) async {
      arch = _Archive(on: on);
      detections.clear();
      verifier = FakeWakeVerifier();
      listener = WakeWordListener(
        audio: audio = FakeAudioInput(),
        engine: engine,
        verifier: verifier,
        verifyTail: Duration.zero,
        devClips: arch.hook,
      );
      listener.detections.listen(detections.add);
      await listener.start();
    }

    Future<void> feed(int frames) async {
      for (var i = 0; i < frames; i++) {
        audio.push(counting(i * 480));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    tearDown(() => listener.dispose());

    FakeWakeWordEngine fake(
      Map<int, W> windows, {
      Set<int> hits = const {},
      bool primaryModel = false,
    }) => FakeWakeWordEngine(
      hitAtFrame: hits,
      windowAtFrame: windows,
      primaryModel: primaryModel,
    );

    test('Schatten feuert, Primär nicht: ein Fall shadow-would', () async {
      await setUp0(
        fake({
          80: (model: 0.6, margin: -0.3),
          81: (model: 0.99, margin: -0.3),
          82: (model: 0.7, margin: -0.3),
        }),
      );
      await feed(160);
      expect(arch.entries, hasLength(1));
      final m = arch.entries.single.meta;
      expect(arch.entries.single.outcome, 'near-miss');
      expect(m['path'], 'shadow-would');
      expect(m['would'], 'model');
      expect(m['fired'], isFalse);
      expect(m['primary'], 'templates');
      expect(m['sh_model_peak'], '0.9900');
      expect(listener.stats.candidates, 0);
      expect(detections, isEmpty);
    });

    test('beide feuern: ein Fall, Werte beider Erkenner', () async {
      await setUp0(
        fake(
          {
            80: (model: 0.6, margin: -0.1),
            81: (model: 0.99, margin: -0.02),
            82: (model: 0.7, margin: 0.1),
          },
          hits: {82},
        ),
      );
      await feed(175);
      expect(arch.entries, hasLength(1));
      final e = arch.entries.single;
      expect(e.outcome, 'accepted');
      expect(e.meta['fired'], isTrue);
      expect(e.meta['would'], 'both');
      expect(e.meta['sh_model_peak'], '0.9900'); // Fenster vor dem Treffer
      expect(e.meta['sh_tmpl_margin'], '0.1000');
      expect(e.meta['thr_tmpl'], '0.6000');
      expect(e.meta['verdict'], 'ok'); // Prüfer-Ergebnis im selben Fall
    });

    test('Treffer nach Halten, kein Fenster über der Grenze: weiter ein Fall '
        '(markCandidate)', () async {
      await setUp0(
        fake(
          {for (var f = 80; f < 85; f++) f: (model: 0.6, margin: -0.01)},
          hits: {85},
        ),
      );
      await feed(180);
      expect(arch.entries.map((e) => e.outcome), ['accepted']);
    });

    test('nur Primär feuert: ein Fall mit dem Schattenwert', () async {
      await setUp0(
        fake(
          {81: (model: 0.7, margin: 0.1), 82: (model: 0.2, margin: 0.2)},
          hits: {82},
        ),
      );
      await feed(175);
      final e = arch.entries.single;
      expect(arch.entries, hasLength(1));
      expect(e.meta['sh_model_peak'], '0.7000');
      expect(e.meta['would'], 'templates');
      expect(e.meta['fired'], isTrue);
    });

    test('Near-miss beider Kanäle derselben Äußerung: ein Fall', () async {
      await setUp0(
        fake({
          80: (model: 0.6, margin: null),
          81: (model: 0.2, margin: -0.03),
          82: (model: 0.55, margin: -0.2),
        }),
      );
      await feed(160);
      expect(arch.entries, hasLength(1));
      final m = arch.entries.single.meta;
      expect(m['path'], 'near-miss');
      expect(m['would'], 'none');
      expect(m['sh_model_peak'], '0.6000');
      expect(m['sh_tmpl_margin'], '-0.0300');
      expect(m['sh_tmpl_peak'], '0.5700');
    });

    test(
      'Primär über der Grenze, aber ohne Treffer (Sperre): kein Fall',
      () async {
        await setUp0(
          fake({81: (model: 0.99, margin: -0.3)}, primaryModel: true),
        );
        await feed(160);
        expect(arch.entries, isEmpty);
      },
    );

    test('Vorlagen-Near-miss allein (Marge knapp unter 0) wird gesammelt, '
        'Marge -0,06 nicht', () async {
      await setUp0(fake({20: (model: 0.0, margin: -0.06)}));
      await feed(100);
      expect(arch.entries, isEmpty);
      await listener.dispose();
      await setUp0(fake({20: (model: 0.0, margin: -0.05)}));
      await feed(100);
      expect(arch.entries.single.meta['path'], 'near-miss');
    });

    test('5 s Mindestabstand gilt für beide Erkenner zusammen', () async {
      await setUp0(
        fake({
          20: (model: 0.6, margin: null), // Modell-Lauf
          60: (model: 0.0, margin: -0.02), // Vorlagen-Lauf 1,2 s später
          260: (model: 0.0, margin: -0.02), // 5 s später: zählt wieder
        }),
      );
      await feed(330);
      expect(arch.entries, hasLength(2));
    });

    test(
      'Entwicklermodus aus: kein Fall, keine Datei, Erkennung läuft',
      () async {
        await setUp0(
          fake(
            {80: (model: 0.99, margin: 0.2), 82: (model: 0.9, margin: 0.1)},
            hits: {82},
          ),
          on: false,
        );
        await feed(175);
        expect(arch.entries, isEmpty);
        expect(arch.clips, isEmpty);
        expect(detections, hasLength(1));
      },
    );

    test('Engine nur mit scoreSink (WP155): Near-miss wie bisher', () async {
      await setUp0(_ScoreOnly({80: 0.55, 81: 0.9, 82: 0.7}));
      await feed(160);
      expect(arch.entries.single.meta['path'], 'near-miss');
      expect(arch.entries.single.meta['score'], '0.9000');
    });
  });

  group('CandidateWakeEngine: Schatten', () {
    Future<(CandidateWakeEngine, List<WakeWindowScores>)> make({
      required Float32List embedding,
      double? score,
      WakeTemplates? templates,
      List<WakeTemplates> shadow = const [],
      double? modelThreshold,
      bool sink = true,
    }) async {
      final seen = <WakeWindowScores>[];
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          windowFor: (end, _) => WakeWindow(
            endSample: end,
            embedding: embedding,
            modelScore: score,
          ),
        ),
        templates: templates,
        shadowTemplates: shadow,
        modelThreshold: modelThreshold,
      );
      if (sink) e.windowSink = seen.add;
      await e.open([KeywordSpec.wendelin]);
      return (e, seen);
    }

    test('Vorlagen entscheiden: Modell über der Grenze löst nie aus', () async {
      final (e, seen) = await make(
        embedding: _other,
        score: 0.99,
        templates: _tpl(),
      );
      expect(await e.accept(Int16List(100)), isEmpty);
      expect(seen.single.model, 0.99);
      expect(seen.single.margin, closeTo(-0.5, 1e-6));
      expect(seen.single.primaryModel, isFalse);
    });

    test('Vorlagen-Treffer: hit.score bleibt null', () async {
      final (e, _) = await make(
        embedding: _word,
        score: 0.99,
        templates: _tpl(),
      );
      final hit = (await e.accept(Int16List(100))).single;
      expect(hit.reason, 'template');
      expect(hit.score, isNull);
    });

    test(
      'Modell entscheidet: Vorlagen-Schatten löst nie aus, Marge gemeldet',
      () async {
        final (e, seen) = await make(
          embedding: _word,
          score: 0.1,
          shadow: [_tpl()],
          modelThreshold: 0.5,
        );
        expect(await e.accept(Int16List(100)), isEmpty);
        expect(seen.single.margin, closeTo(0.5, 1e-6));
        expect(seen.single.similarity, closeTo(1, 1e-6));
        expect(seen.single.threshold, 0.5);
        expect(seen.single.primaryModel, isTrue);
      },
    );

    test('Modell-Treffer behält den Score', () async {
      final (e, _) = await make(
        embedding: _other,
        score: 0.9,
        shadow: [_tpl()],
        modelThreshold: 0.5,
      );
      expect((await e.accept(Int16List(100))).single.score, 0.9);
    });

    test('ohne Vorlagen nur Modell, ohne Klassifikator nur Vorlagen, NaN ist '
        'kein Wert', () async {
      var (e, seen) = await make(
        embedding: _word,
        score: 0.7,
        modelThreshold: 0.5,
      );
      await e.accept(Int16List(100));
      expect(seen.single.margin, isNull);
      expect(seen.single.model, 0.7);
      (e, seen) = await make(embedding: _word, templates: _tpl());
      await e.accept(Int16List(100));
      expect(seen.single.model, isNull);
      expect(seen.single.margin, closeTo(0.5, 1e-6));
      (e, seen) = await make(
        embedding: _word,
        score: double.nan,
        templates: _tpl(),
      );
      await e.accept(Int16List(100));
      expect(seen.single.model, isNull);
    });

    test('ohne Senke wird der Schatten nicht gerechnet', () async {
      final f = _MeanCounter(_word);
      final e = CandidateWakeEngine(
        features: f,
        shadowTemplates: [_tpl()],
        modelThreshold: 0.5,
      );
      await e.open([KeywordSpec.wendelin]);
      await e.accept(Int16List(100));
      expect(f.meanReads, 0);
      e.windowSink = (_) {};
      await e.accept(Int16List(100));
      expect(f.meanReads, greaterThan(0));
    });

    test('shadowCost: je Fenster eine Zeit, nur mit Schatten-Vorlagen und '
        'Senke', () async {
      Future<int> windows({
        List<WakeTemplates> shadow = const [],
        bool sink = true,
      }) async {
        final times = <Duration>[];
        final e = CandidateWakeEngine(
          features: FakeWakeFeatureExtractor(
            windowEvery: 100,
            windowFor: (end, _) =>
                WakeWindow(endSample: end, embedding: _word, modelScore: 0.1),
          ),
          shadowTemplates: shadow,
          shadowCost: times.add,
          modelThreshold: 0.5,
        );
        if (sink) e.windowSink = (_) {};
        await e.open([KeywordSpec.wendelin]);
        await e.accept(Int16List(300));
        return times.length;
      }

      expect(await windows(shadow: [_tpl()]), 3);
      expect(await windows(), 0, reason: 'ohne Schatten-Vorlagen nichts');
      expect(await windows(shadow: [_tpl()], sink: false), 0);
    });

    test('werfende Senke ändert die Entscheidung nicht', () async {
      final (e, _) = await make(embedding: _word, templates: _tpl());
      e.windowSink = (_) => throw StateError('sink');
      expect(await e.accept(Int16List(100)), hasLength(1));
    });
  });
}
