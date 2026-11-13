import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Loud noise with a quiet hole of [hole] samples at [at].
Int16List _audio(int length, {List<(int at, int hole)> holes = const []}) {
  final pcm = Int16List(length);
  for (var i = 0; i < length; i++) {
    pcm[i] = i.isEven ? 8000 : -8000;
  }
  for (final (at, hole) in holes) {
    pcm.fillRange(at, at + hole, 0);
  }
  return pcm;
}

List<int> _join(List<Int16List> parts) => [for (final p in parts) ...p];

void main() {
  const limit = sttSegmentLimitSamples;

  group('splitAtQuietPoints (WP192)', () {
    test('bis zur Grenze: ein Stück, dieselbe Liste', () {
      final pcm = _audio(limit);
      final parts = splitAtQuietPoints(pcm);
      expect(parts, hasLength(1));
      expect(identical(parts.single, pcm), isTrue);
      expect(splitAtQuietPoints(Int16List(0)).single, isEmpty);
    });

    test('eine Sample über der Grenze: geteilt, jedes Stück <= Grenze', () {
      final parts = splitAtQuietPoints(_audio(limit + 1));
      expect(parts.length, 2);
      expect(parts.every((p) => p.length <= limit), isTrue);
    });

    test('schneidet in der Stille im Suchbereich (20-25 s)', () {
      final hole = [(22 * 16000, 8000)]; // 22.0-22.5 s quiet
      final pcm = _audio(40 * 16000, holes: hole);
      final parts = splitAtQuietPoints(pcm);
      expect(parts, hasLength(2));
      final cut = parts.first.length;
      expect(cut, inInclusiveRange(22 * 16000, 22 * 16000 + 8000));
    });

    test('Stille außerhalb des Suchbereichs (vor 20 s) wird ignoriert', () {
      final pcm = _audio(40 * 16000, holes: [(10 * 16000, 8000)]);
      final cut = splitAtQuietPoints(pcm).first.length;
      expect(cut, greaterThanOrEqualTo(20 * 16000));
      expect(cut, lessThanOrEqualTo(limit));
    });

    test('mehrere Schnitte; keine Samples verloren oder doppelt', () {
      final pcm = Int16List.fromList([
        for (var i = 0; i < 70 * 16000; i++) (i * 7919) % 20000 - 10000,
      ]);
      final parts = splitAtQuietPoints(pcm);
      expect(parts.length, greaterThanOrEqualTo(3));
      expect(parts.every((p) => p.length <= limit), isTrue);
      expect(_join(parts), pcm.toList());
    });

    test('eigene Grenze (Parameter)', () {
      final pcm = _audio(100000);
      final parts = splitAtQuietPoints(pcm, limit: 30000);
      expect(parts.every((p) => p.length <= 30000), isTrue);
      expect(_join(parts), pcm.toList());
    });
  });

  group('mergeTranscripts (WP192)', () {
    test('Text mit Leerzeichen, leere übersprungen, Konfidenz Minimum', () {
      final t = mergeTranscripts(const [
        Transcript(text: 'Eins.', language: 'de', confidence: 0.9),
        Transcript(text: '', language: 'de', confidence: 0.1),
        Transcript(text: ' Zwei. ', confidence: 0.7),
      ]);
      expect(t.text, 'Eins. Zwei.');
      expect(t.language, 'de');
      expect(t.confidence, 0.1);
    });

    test('ohne Konfidenz/Sprache: null', () {
      final t = mergeTranscripts(const [
        Transcript(text: 'a'),
        Transcript(text: 'b'),
      ]);
      expect(t.text, 'a b');
      expect(t.confidence, isNull);
      expect(t.language, isNull);
    });
  });
}
