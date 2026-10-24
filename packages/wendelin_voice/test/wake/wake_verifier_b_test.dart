import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Float32List vec(List<double> head) {
  final v = Float32List(96);
  for (var i = 0; i < head.length; i++) {
    v[i] = head[i];
  }
  return v;
}

Float32List flat(List<Float32List> rows) {
  final out = Float32List(rows.length * 96);
  for (var i = 0; i < rows.length; i++) {
    out.setAll(i * 96, rows[i]);
  }
  return out;
}

VerifierBSequence prep(List<Float32List> rows, [Float32List? mu]) =>
    VerifierBSequence.prepare(flat(rows), mu ?? Float32List(96));

/// Eine Einheitsrichtung je Index (orthogonal zueinander).
Float32List axis(int i, [double scale = 1]) => Float32List(96)..[i] = scale;

void main() {
  group('Vorbereitung', () {
    test('mu wird je Frame abgezogen, danach Länge 1', () {
      final mu = vec([10, 0]);
      final s = prep([
        vec([13, 4]),
      ], mu); // (3, 4) -> (0.6, 0.8)
      expect(s.values[0], closeTo(0.6, 1e-6));
      expect(s.values[1], closeTo(0.8, 1e-6));
    });

    test(
      'ohne Zentrierung wäre der Vergleich ein anderer (Mutationsanker)',
      () {
        // Zwei Frames, die nur durch mu unterscheidbar sind: roh fast gleich.
        final mu = vec([100, 0, 0]);
        final a = prep([
          vec([101, 1, 0]),
        ], mu);
        final b = prep([
          vec([101, 0, 1]),
        ], mu);
        final raw = prep([
          vec([101, 1, 0]),
        ]);
        final rawB = prep([
          vec([101, 0, 1]),
        ]);
        expect(
          verifierBTemplateScore(a, b),
          closeTo(0.5, 1e-6),
          reason: '(1,1,0)·(1,0,1)/2 = 0.5',
        );
        expect(verifierBTemplateScore(raw, rawB), greaterThan(0.99));
      },
    );

    test('Nullframe bleibt Null (kein NaN)', () {
      final s = prep([Float32List(96)]);
      expect(s.values.every((v) => v == 0), isTrue);
    });

    test('falsche Länge wird abgelehnt', () {
      expect(
        () => VerifierBSequence.prepare(Float32List(97), Float32List(96)),
        throwsArgumentError,
      );
    });
  });

  group('Vorlagen-Score', () {
    test('Maximum über den Versatz und Mittel über die Vorlagenlänge', () {
      final live = prep([axis(0), axis(1), axis(2), axis(3)]);
      // Passt exakt bei Versatz 1 (Frames 1,2).
      final tpl = prep([axis(1), axis(2)]);
      expect(verifierBTemplateScore(live, tpl), closeTo(1, 1e-6));
      // Passt nur zur Hälfte: ein Frame trifft, das andere nicht.
      final half = prep([axis(2), axis(9)]);
      expect(verifierBTemplateScore(live, half), closeTo(0.5, 1e-6));
    });

    test('letzter Versatz zählt mit (Ende des Live-Stücks)', () {
      final live = prep([axis(0), axis(1), axis(2)]);
      expect(
        verifierBTemplateScore(live, prep([axis(1), axis(2)])),
        closeTo(1, 1e-6),
      );
    });

    test('weniger Live-Frames als Vorlagenframes: -1 (abgelehnt)', () {
      final live = prep([axis(0)]);
      expect(verifierBTemplateScore(live, prep([axis(0), axis(1)])), -1);
    });
  });

  group('Top-3', () {
    // Vorlagen mit Scores 1.0, 0.5, 0.0, -0.5 gegen live = [axis(0)].
    VerifierBSequence tpl(double s) => prep([
      vec([s, math.sqrt(1 - s * s)]),
    ]);
    final live = prep([axis(0)]);

    test('Mittel der besten drei, schwächere Vorlagen zählen nicht', () {
      final templates = [tpl(0.2), tpl(1), tpl(0.6), tpl(0.8), tpl(-0.9)];
      expect(
        verifierBScore(live, templates),
        closeTo((1 + 0.8 + 0.6) / 3, 1e-6),
      );
    });

    test('weniger als drei Vorlagen: Mittel aller', () {
      expect(verifierBScore(live, [tpl(1), tpl(0.5)]), closeTo(0.75, 1e-6));
    });

    test('keine Vorlage: -1', () {
      expect(verifierBScore(live, const []), -1);
    });
  });

  group('Ausschnitt live', () {
    Int16List signal(int n) => Int16List.fromList([
      for (var i = 0; i < n; i++)
        (0.4 * ((i * 37 % 2001) - 1000) / 2000 * 32768).round(),
    ]);

    test('Grenzen: Halbe gehen zur geraden Zahl (Python round)', () {
      expect(verifierBLiveBounds(80000), (from: 49600, to: 93600));
      expect(verifierBLiveBounds(20000), (from: -10400, to: 33600));
      expect(verifierBLiveBounds(158000), (from: 127680, to: 171680));
      expect(verifierBLiveBounds(80080), (from: 49600, to: 93600)); // 500.5
      expect(verifierBLiveBounds(80240), (from: 49920, to: 93920)); // 501.5
    });

    test('immer 44000 Samples, Spitze 0,5, Nullen außerhalb', () {
      final pcm = signal(160000);
      final front = verifierBLiveClip(pcm, 20000);
      expect(front.length, 44000);
      expect(front.sublist(0, 10400).every((s) => s == 0), isTrue);
      final back = verifierBLiveClip(pcm, 158000);
      expect(back.length, 44000);
      expect(back.sublist(44000 - 11680).every((s) => s == 0), isTrue);
      final peak = front.map((s) => s.abs()).reduce(math.max);
      expect(peak, closeTo(16384, 1));
    });

    test('Ausschnitt passt zu den Quellsamples (skaliert)', () {
      final pcm = signal(160000);
      final c = verifierBLiveClip(pcm, 80000);
      final gain =
          16384 /
          pcm.sublist(49600, 93600).map((s) => s.abs()).reduce(math.max);
      expect(c[1000], closeTo(pcm[49600 + 1000] * gain, 1));
    });

    test('Stille bleibt Stille', () {
      expect(
        verifierBLiveClip(Int16List(5000), 2500).every((s) => s == 0),
        isTrue,
      );
    });
  });

  group('Ausschnitt Vorlage', () {
    test('Grenzen werden abgeschnitten, nicht gerundet', () {
      expect(verifierBTemplateBounds(48000, 1.0, 1.9), (
        from: 14080,
        to: 33600,
      ));
      expect(verifierBTemplateBounds(48000, 1.13, 2.03), (
        from: 16159,
        to: 35680,
      ));
      expect(verifierBTemplateBounds(48000, 0.23, 1.13), (
        from: 1760,
        to: 21279,
      ));
      expect(verifierBTemplateBounds(48000, 0.05, 0.95), (from: 0, to: 18400));
      expect(verifierBTemplateBounds(10000, 0.5, 0.9), (from: 6080, to: 10000));
    });

    Int16List word(double bg) => Int16List.fromList([
      for (var i = 0; i < 48000; i++)
        (((i * 37 % 2001) - 1000) /
                2000 *
                (i >= 16000 && i < 30400 ? 0.4 : bg) *
                32768)
            .round(),
    ]);

    test('lange Wörter: Zuschnitt unverändert, kein Trim, Spitze 0,5', () {
      // Sprache 16000..30400: Zuschnitt 14080..33600 = 19520 Samples.
      final c = verifierBTemplateClip(word(0.001), 16000, 30400)!;
      expect(c.length, 19520);
      expect(c.map((s) => s.abs()).reduce(math.max), closeTo(16384, 1));
      // Stille am Rand bleibt (der Trim -40 dB ist entfernt).
      expect(c.first.abs(), lessThan(100));
    });

    int zeroRun(Int16List c) {
      var run = 0, best = 0;
      for (final s in c) {
        run = s == 0 ? run + 1 : 0;
        best = math.max(best, run);
      }
      return best;
    }

    test('kurzes Wort: symmetrisch mit echtem Audio auf 1,0 s aufgefüllt', () {
      final pcm = word(0.001);
      // Sprache 20000..24000 (0,25 s): Zuschnitt 0,57 s, 7 420 Samples fehlen.
      final cut = verifierBTemplateBounds(48000, 1.25, 1.5);
      final missing = 16000 - (cut.to - cut.from);
      final w = verifierBTemplateWindow(48000, 20000, 24000)!;
      expect(w.from, cut.from - missing ~/ 2);
      expect(w.to, cut.to + missing - missing ~/ 2);
      expect(w.to - w.from, 16000);
      final c = verifierBTemplateClip(pcm, 20000, 24000)!;
      expect(c.length, 16000);
      // Echtes Audio, keine Nullen: die Samples sind die der Aufnahme.
      final peak = pcm
          .sublist(w.from, w.to)
          .map((s) => s.abs())
          .reduce(math.max);
      final gain = 16384 / peak;
      for (var i = 0; i < c.length; i += 97) {
        expect(c[i], closeTo(pcm[w.from + i] * gain, 1));
      }
      expect(zeroRun(c), lessThan(20));
    });

    test('Aufnahme reicht vorn nicht: Fenster rutscht nach hinten', () {
      expect(verifierBTemplateWindow(48000, 1000, 5000), (from: 0, to: 16000));
    });

    test('Aufnahme reicht hinten nicht: Fenster rutscht nach vorn', () {
      expect(verifierBTemplateWindow(48000, 44000, 47000), (
        from: 32000,
        to: 48000,
      ));
    });

    test('Aufnahme kürzer als 1,0 s oder Sprache außerhalb: null', () {
      expect(verifierBTemplateWindow(15999, 2000, 9000), isNull);
      expect(verifierBTemplateClip(Int16List(15999), 2000, 9000), isNull);
      expect(verifierBTemplateWindow(48000, 50000, 52000), isNull);
    });

    test('Zuschnitt über 2,2 s wird verworfen, darunter bleibt er', () {
      // Zuschnitt = Sprache + 0,32 s (5120 Samples): Grenze bei 30080.
      expect(verifierBTemplateWindow(96000, 16000, 16000 + 30000), isNotNull);
      expect(verifierBTemplateWindow(96000, 16000, 16000 + 30200), isNull);
      expect(
        verifierBTemplateClip(Int16List(96000), 16000, 16000 + 30200),
        isNull,
      );
    });

    test('genau 1,0 s Zuschnitt bleibt unverändert', () {
      // Zuschnitt 16000 Samples: Sprache 14080+1920 .. : start 1.0 s, Ende 1.68.
      final cut = verifierBTemplateBounds(48000, 1.0, 1.68);
      expect(cut.to - cut.from, 16000);
      expect(verifierBTemplateWindow(48000, 16000, 26880), (
        from: cut.from,
        to: cut.to,
      ));
    });

    test(
      'Vorlage ohne Folge (zu kurz für 76 Mel-Frames) wird nicht gespeichert',
      () async {
        final e = FakeWakeFeatureExtractor();
        expect(await verifierBTemplate(e, word(0.001), 16000, 30400), isNull);
        expect(e.sequenceCalls.single.length, 19520);
      },
    );

    test(
      'Vorlage mit nur einem Embedding-Frame wird nicht gespeichert',
      () async {
        final e = FakeWakeFeatureExtractor(sequenceFor: (_) => Float32List(96));
        expect(await verifierBTemplate(e, word(0.001), 16000, 30400), isNull);
      },
    );

    test('Vorlage mit drei Frames bleibt', () async {
      final e = FakeWakeFeatureExtractor(
        sequenceFor: (_) => Float32List(3 * 96),
      );
      expect(
        (await verifierBTemplate(e, word(0.001), 16000, 30400))!.length,
        3 * 96,
      );
    });
  });

  group('VerifierBWakeVerifier', () {
    // Live: 25 gleiche Frames `liveRow`.
    WakeFeatureExtractor liveFeatures(Float32List liveRow) =>
        FakeWakeFeatureExtractor(
          featureVersion: wakeVerifierBFeatureVersion,
          sequenceFor: (_) => flat([for (var i = 0; i < 25; i++) liveRow]),
        );

    WakeTemplates templatesWith(List<Float32List> rows, {String word = 'hw'}) =>
        WakeTemplates(
          speakerId: 's',
          featureVersion: wakeVerifierBFeatureVersion,
          threshold: 0.5,
          embeddings: [Float32List(4)],
          sequences: [
            for (final r in rows)
              WakeTemplateSequence(word: word, values: flat([r, r])),
          ],
        );

    Float32List row(double cosine) =>
        vec([cosine, math.sqrt(1 - cosine * cosine)]);

    final pcm = Int16List(16000 * 3)..fillRange(0, 16000 * 3, 3000);
    final end = 16000 * 2;

    late FakeWakeVerifier fallback;
    late List<(String, double?, double?)> log;
    VerifierBWakeVerifier make(
      WakeFeatureExtractor f,
      List<WakeTemplates> t, {
      Map<String, double>? thresholds,
    }) => VerifierBWakeVerifier(
      templates: () async => t,
      features: () => f,
      fallback: fallback,
      mu: Float32List(96),
      onDecision: (v, s, t) => log.add((v, s, t)),
      thresholds: thresholds ?? const {'w': 0.6038, 'hw': 0.6815},
    );

    setUp(() {
      fallback = FakeWakeVerifier();
      log = [];
    });

    test(
      'Score über der Schwelle: B bestätigt, hw2 wird nicht gefragt',
      () async {
        // Vorlagen mit Kosinus 0.9 zur Live-Zeile (axis 0).
        final v = make(liveFeatures(axis(0)), [
          templatesWith([row(0.9), row(0.9), row(0.9)]),
        ]);
        expect(await v.confirmAt(pcm, end), isTrue);
        expect(fallback.calls, isEmpty);
        expect(v.kind, 'b');
        expect(log.single.$1, 'b');
        expect(log.single.$2, closeTo(0.9, 1e-4));
        expect(log.single.$3, 0.6815);
      },
    );

    test(
      'Score knapp unter der Schwelle: abgelehnt, hw2 nicht gefragt',
      () async {
        final v = make(liveFeatures(axis(0)), [
          templatesWith([row(0.68), row(0.68), row(0.68)]),
        ]);
        expect(await v.confirmAt(pcm, end), isFalse);
        expect(fallback.calls, isEmpty);
      },
    );

    test('Score genau auf der Schwelle zählt (>=)', () async {
      final tpl = [
        templatesWith([row(0.9)]),
      ];
      await make(liveFeatures(axis(0)), tpl).confirmAt(pcm, end);
      final exact = log.single.$2!;
      final on = make(liveFeatures(axis(0)), tpl, thresholds: {'hw': exact});
      expect(await on.confirmAt(pcm, end), isTrue);
      final above = make(
        liveFeatures(axis(0)),
        tpl,
        thresholds: {'hw': exact + 1e-9},
      );
      expect(await above.confirmAt(pcm, end), isFalse);
    });

    test('Wort ohne Schwelle wird ignoriert; sonst Rückfall', () async {
      final v = make(liveFeatures(axis(0)), [
        templatesWith([row(0.9)], word: 'x'),
      ]);
      expect(await v.confirmAt(pcm, end), isTrue); // Fallback bestätigt
      expect(fallback.calls, hasLength(1));
    });

    test('ein Wort reicht: W unter, HW über der Schwelle', () async {
      final v = make(liveFeatures(axis(0)), [
        WakeTemplates(
          speakerId: 's',
          featureVersion: wakeVerifierBFeatureVersion,
          threshold: 0.5,
          embeddings: [Float32List(4)],
          sequences: [
            WakeTemplateSequence(word: 'w', values: flat([row(0.1), row(0.1)])),
            WakeTemplateSequence(
              word: 'hw',
              values: flat([row(0.95), row(0.95)]),
            ),
          ],
        ),
      ]);
      expect(await v.confirmAt(pcm, end), isTrue);
      expect(fallback.calls, isEmpty);
    });

    test('ohne Folgen (Altvorlagen): Rückfall hw2, Log verifier=hw2', () async {
      final old = WakeTemplates(
        speakerId: 's',
        featureVersion: wakeVerifierBFeatureVersion,
        threshold: 0.5,
        embeddings: [Float32List(4)],
      );
      fallback.answer = (_) => false;
      final v = make(liveFeatures(axis(0)), [old]);
      expect(await v.confirmAt(pcm, end), isFalse);
      expect(fallback.calls, hasLength(1));
      expect(v.kind, 'fake');
      expect(log.single, ('hw2', null, null));
    });

    test('Folgen einer anderen Merkmalsversion zählen nicht', () async {
      final other = WakeTemplates(
        speakerId: 's',
        featureVersion: 'andere-1',
        threshold: 0.5,
        embeddings: [Float32List(4)],
        sequences: [
          WakeTemplateSequence(word: 'hw', values: flat([axis(0), axis(0)])),
        ],
      );
      final v = make(liveFeatures(axis(0)), [other]);
      await v.confirmAt(pcm, end);
      expect(fallback.calls, hasLength(1));
    });

    test('Fehler in B: Rückfall auf hw2', () async {
      final f = FakeWakeFeatureExtractor(
        featureVersion: wakeVerifierBFeatureVersion,
        sequenceFor: (_) => throw StateError('kaputt'),
      );
      final v = make(f, [
        templatesWith([row(0.9)]),
      ]);
      expect(await v.confirmAt(pcm, end), isTrue);
      expect(fallback.calls, hasLength(1));
      expect(log.single.$1, 'hw2');
    });

    test(
      'Fehler des Rückfalls selbst wird nicht verschluckt oder doppelt gefragt',
      () async {
        fallback.error = StateError('stt');
        final v = make(liveFeatures(axis(0)), const []);
        await expectLater(v.confirmAt(pcm, end), throwsStateError);
        expect(fallback.calls, hasLength(1));
      },
    );

    test('zu kurzer Clip (null-Folge): Score -1, abgelehnt', () async {
      final v = make(FakeWakeFeatureExtractor(), [
        templatesWith([row(0.9)]),
      ]);
      expect(await v.confirmAt(pcm, end), isFalse);
      expect(log.single.$2, -1);
      expect(fallback.calls, isEmpty);
    });

    test('Vorlage länger als der Ausschnitt wird ignoriert: -1', () async {
      final v = make(
        FakeWakeFeatureExtractor(sequenceFor: (_) => flat([axis(0), axis(0)])),
        [
          WakeTemplates(
            speakerId: 's',
            featureVersion: wakeVerifierBFeatureVersion,
            threshold: 0.5,
            embeddings: [Float32List(4)],
            sequences: [
              WakeTemplateSequence(
                word: 'hw',
                values: flat([axis(0), axis(0), axis(0)]),
              ),
            ],
          ),
        ],
      );
      expect(await v.confirmAt(pcm, end), isFalse);
      expect(log.single.$2, -1);
    });

    test('der Live-Clip hat 44000 Samples um das Ende', () async {
      final f = FakeWakeFeatureExtractor(
        featureVersion: wakeVerifierBFeatureVersion,
        sequenceFor: (_) => flat([for (var i = 0; i < 25; i++) axis(0)]),
      );
      final v = make(f, [
        templatesWith([row(0.9)]),
      ]);
      await v.confirmAt(pcm, end);
      expect(f.sequenceCalls.single.length, 44000);
    });

    test(
      'confirm ohne Endstelle nimmt den Nachlauf des Listeners an',
      () async {
        final f = FakeWakeFeatureExtractor(
          featureVersion: wakeVerifierBFeatureVersion,
          sequenceFor: (_) => flat([for (var i = 0; i < 25; i++) axis(0)]),
        );
        final v = make(f, [
          templatesWith([row(0.9)]),
        ]);
        await v.confirm(Int16List(16 * 2900)..fillRange(0, 16 * 2900, 1000));
        // Ende bei 2000 ms = Sample 32000: Ausschnitt ab 32000 - 30400.
        final clip = f.sequenceCalls.single;
        expect(clip[0], isNot(0)); // beginnt im Signal, nicht in Nullen
        expect(clip.length, 44000);
      },
    );
  });

  group('Vorlagen-JSON', () {
    test('Folgen überleben toJson/fromJson, withThreshold behält sie', () {
      final t = WakeTemplates(
        speakerId: 's',
        featureVersion: 'v',
        threshold: 0.5,
        embeddings: [Float32List(4)],
        sequences: [
          WakeTemplateSequence(word: 'hw', values: flat([axis(3), axis(4)])),
        ],
      );
      final back = WakeTemplates.fromJson(t.toJson());
      expect(back.sequences.single.word, 'hw');
      expect(back.sequences.single.frames, 2);
      expect(back.sequences.single.values[3], 1);
      expect(back.withThreshold(0.7).sequences, hasLength(1));
    });

    test('Altvorlage ohne "sequences" lädt, B inaktiv', () {
      final json = WakeTemplates(
        speakerId: 's',
        featureVersion: 'v',
        threshold: 0.5,
        embeddings: [Float32List(4)],
      ).toJson();
      expect(json.containsKey('sequences'), isFalse);
      expect(WakeTemplates.fromJson(json).hasSequences, isFalse);
    });
  });

  group('Katalog', () {
    test('Modell v8a clean: URL, Prüfsumme, Größe', () {
      final f = WakeClassifierCatalog.model.files.single;
      expect(
        f.url,
        endsWith('/models-wake-v8a-clean/${WakeClassifierCatalog.file}'),
      );
      expect(
        f.sha256,
        '6b41519fa776f5d6c810d0323c64df86433e636d17ddb512d1a630acd9c2e58b',
      );
      expect(f.sizeBytes, 858044);
    });

    test('Schwellen W 0,6038, HW 0,6815', () {
      expect(WakeClassifierRules.verifierBThresholdW, 0.6038);
      expect(WakeClassifierRules.verifierBThresholdHw, 0.6815);
    });
  });
}
