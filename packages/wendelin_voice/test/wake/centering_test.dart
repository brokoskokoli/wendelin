// WP134: zentrierter Kosinus. Eingebettete Fenster teilen einen festen
// Anteil; roh liegen Stille, Rauschen und Sprache nahe beieinander.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Float32List v(List<double> x) => Float32List.fromList(x);

/// Gemeinsamer Anteil wie bei den echten Embeddings (hier 4 statt 1536).
final _mean = v([10, 10, 10, 10]);
final _word = v([12, 10, 10, 10]); // Mittel + Wort-Richtung
final _noise = v([10, 10.3, 9.8, 10.1]); // nahe am Mittel, ohne Wort-Anteil
final _silence = v([10, 10, 10, 10]); // genau das Mittel

WakeTemplates _tpl({String? center}) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.5,
  embeddings: [_word],
  center: center,
);

CandidateWakeEngine _engine(List<Float32List> windows, {Float32List? mean}) {
  var i = 0;
  return CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: 100,
      embeddingMean: mean,
      centerId: mean == null ? null : 'm-1',
      windowFor: (end, _) =>
          WakeWindow(endSample: end, embedding: windows[i++]),
    ),
    templates: _tpl(center: mean == null ? null : 'm-1'),
    modelThreshold: null,
  );
}

Future<int> _hits(CandidateWakeEngine e, int n) async {
  await e.open([KeywordSpec.wendelin]);
  e.reset();
  var hits = 0;
  for (var k = 0; k < n; k++) {
    hits += (await e.accept(Int16List(100))).length;
  }
  return hits;
}

void main() {
  group('centeredCosine', () {
    test('roh dominiert der gemeinsame Anteil, zentriert nicht', () {
      expect(cosineSimilarity(_noise, _word), greaterThan(0.99));
      expect(centeredCosine(_noise, _word, _mean), lessThan(0.3));
      expect(centeredCosine(_word, _word, _mean), closeTo(1, 1e-6));
    });

    test('Fenster gleich dem Mittel: 0 (Nullvektor), nie NaN', () {
      expect(centeredCosine(_silence, _word, _mean), 0);
      expect(centeredCosine(_word, _silence, _mean), 0);
    });

    test('Längen müssen passen (fail-closed)', () {
      expect(
        () => centeredCosine(v([1, 2]), v([1, 2]), _mean),
        throwsArgumentError,
      );
      expect(
        () => centeredCosine(v([1, 2, 3, 4]), v([1, 2]), _mean),
        throwsArgumentError,
      );
    });

    test('bestSimilarity mit Mittel wählt zentriert, ohne roh', () {
      expect(bestSimilarity(_noise, [_word]), greaterThan(0.99));
      expect(bestSimilarity(_noise, [_word], mean: _mean), lessThan(0.3));
      expect(bestSimilarity(_noise, [], mean: _mean), -1);
    });
  });

  group('festes Mittel', () {
    test('1536 endliche Werte, an die Feature-Version gebunden', () {
      expect(wakeCenterMean.length, 1536);
      expect(wakeCenterMean.every((x) => x.isFinite), isTrue);
      expect(wakeCenterMean.any((x) => x != 0), isTrue);
      expect(wakeCenterFeatureVersion, 'oww-0.5.1-mel-emb-1');
      expect(wakeCenterId, isNotEmpty);
    });
  });

  group('Vorlagen nach Warmstart', () {
    test(
      'Stille und Rauschen lösen nicht aus, das Vorlagen-Wort schon',
      () async {
        expect(
          await _hits(_engine([_silence, _noise, _noise], mean: _mean), 3),
          0,
        );
        expect(await _hits(_engine([_noise, _word], mean: _mean), 2), 1);
      },
    );

    test('Gegenprobe: ohne Mittel (roh) löst dasselbe Rauschen aus', () async {
      // Belegt, dass der Test den Fehler fängt: roh liegt das Rauschen bei 1,0.
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: _noise),
        ),
        templates: WakeTemplates(
          speakerId: 'a',
          featureVersion: 'fake-1',
          threshold: 0.9,
          embeddings: [_word],
        ),
        modelThreshold: null,
      );
      expect(await _hits(e, 1), 1);
    });
  });

  group('mit dem echten Mittel (1536 Werte)', () {
    final rnd = math.Random(7);
    // sigma small: |mean| is about 550, so the raw cosine of two windows stays above 0.9.
    Float32List gauss(double sigma) => Float32List.fromList([
      for (var i = 0; i < 1536; i++)
        sigma *
            math.sqrt(-2 * math.log(1 - rnd.nextDouble())) *
            math.cos(2 * math.pi * rnd.nextDouble()),
    ]);
    Float32List plus(Float32List a, Float32List b) =>
        Float32List.fromList([for (var i = 0; i < a.length; i++) a[i] + b[i]]);
    final word = plus(wakeCenterMean, gauss(4));
    final tpl = WakeTemplates(
      speakerId: 'a',
      featureVersion: 'fake-1',
      center: wakeCenterId,
      threshold: 0.5,
      embeddings: [word],
    );

    Future<int> hits(List<Float32List> windows) async {
      var i = 0;
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          embeddingMean: wakeCenterMean,
          centerId: wakeCenterId,
          windowFor: (end, _) =>
              WakeWindow(endSample: end, embedding: windows[i++]),
        ),
        templates: tpl,
        modelThreshold: null,
      );
      return _hits(e, windows.length);
    }

    test(
      'Stille, Rauschen und fremdes Audio unter 0,5, das Wort darüber',
      () async {
        final silence = Float32List.fromList(wakeCenterMean);
        final noise = [
          for (var i = 0; i < 8; i++) plus(wakeCenterMean, gauss(4)),
        ];
        expect(bestSimilarity(silence, [word], mean: wakeCenterMean), 0);
        for (final n in noise) {
          expect(
            bestSimilarity(n, [word], mean: wakeCenterMean),
            lessThan(0.2),
          );
          // roh sähe das Fenster fast wie die Vorlage aus
          expect(bestSimilarity(n, [word]), greaterThan(0.9));
        }
        expect(await hits([silence, ...noise]), 0);
        final again = plus(word, gauss(1));
        expect(
          bestSimilarity(again, [word], mean: wakeCenterMean),
          greaterThan(0.9),
        );
        expect(await hits([silence, again]), 1);
      },
    );
  });

  group('WakeTemplates.center', () {
    test('Rundlauf mit Mittel-Kennung; Kennung nur wenn gesetzt', () {
      final t = _tpl(center: 'm-1');
      expect(WakeTemplates.fromJson(t.toJson()).center, 'm-1');
      expect(_tpl().toJson().containsKey('center'), isFalse);
      expect(t.withThreshold(0.6).center, 'm-1');
    });

    test(
      'alte Vorlagen (ohne Kennung) sind mit zentrierter Kette unbrauchbar',
      () {
        final old = WakeTemplates.fromJson({
          'speakerId': 's',
          'featureVersion': 'oww-0.5.1-mel-emb-1',
          'threshold': 0.85,
          'embeddings': [
            base64Encode(Uint8List.view(v([1, 2, 3, 4]).buffer)),
          ],
        });
        expect(old.center, isNull);
        expect(
          old.isCompatible('oww-0.5.1-mel-emb-1', center: wakeCenterId),
          isFalse,
        );
        expect(old.isCompatible('oww-0.5.1-mel-emb-1'), isTrue);
      },
    );

    test('andere Kennung oder Version: unbrauchbar', () {
      final t = _tpl(center: 'm-1');
      expect(t.isCompatible('fake-1', center: 'm-1'), isTrue);
      expect(t.isCompatible('fake-1', center: 'm-2'), isFalse);
      expect(t.isCompatible('fake-1'), isFalse);
      expect(t.isCompatible('fake-2', center: 'm-1'), isFalse);
    });

    test('Engine ignoriert alte Vorlagen (kein Treffer)', () async {
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          embeddingMean: _mean,
          centerId: 'm-1',
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: _word),
        ),
        templates: _tpl(), // roh gespeichert
        modelThreshold: null,
      );
      expect(await _hits(e, 2), 0);
    });
  });
}
