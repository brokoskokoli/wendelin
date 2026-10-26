// WP149: the overlap of the service's tail and the app's first audio is cut
// by content (normalized cross-correlation), not by arrival times.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_align.dart';
import 'package:wendelin/voice/wake/wake_pre_roll.dart';

/// One recording both microphones hear: speech-like noise with an envelope.
Int16List source(int n, {int seed = 7}) {
  var x = seed;
  final out = Int16List(n);
  var lp = 0.0;
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    final white = (x >> 8) / (1 << 22) - 1; // -1..1
    lp = 0.6 * lp + white;
    out[i] = (lp * 3000 * (0.6 + 0.4 * math.sin(i / 700))).round();
  }
  return out;
}

/// A slow chirp is locally periodic (ambiguous, see below), so the test
/// signal is the chirp plus noise.
Int16List chirp(int n) {
  final out = Int16List(n);
  final noise = source(n, seed: 3);
  for (var i = 0; i < n; i++) {
    final t = i / 16000;
    out[i] =
        (6000 * math.sin(2 * math.pi * (300 * t + 1000 * t * t))).round() +
        noise[i];
  }
  return out;
}

void main() {
  final lines = <String>[];
  late void Function(String) saved;
  setUp(() {
    lines.clear();
    saved = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() => voiceLogSink = saved);

  // tail = s[0..b), app = s[b-overlap..); the true overlap is [overlap].
  ({Int16List tail, Int16List app}) cut(Int16List s, int b, int overlap) => (
    tail: Int16List.sublistView(s, 0, b),
    app: Int16List.sublistView(
      s,
      b - overlap,
      math.min(s.length, b - overlap + 6400),
    ),
  );

  for (final (name, s) in [
    ('Rauschen', source(24000)),
    ('Chirp mit Rauschen', chirp(24000)),
  ]) {
    test('$name: Überlappung wird auf das Sample gefunden, auch bei falscher '
        'Zeitschätzung', () {
      for (final (overlap, est) in [
        (1501, 1000), // timestamps too small by 31 ms
        (1103, 1100),
        (2899, 1000), // 119 ms off
        (602, 1300), // too large
      ]) {
        final c = cut(s, 20000, overlap);
        final r = alignWakeTail(c.tail, c.app, estimate: est);
        expect(r.overlap, overlap, reason: '$name overlap=$overlap est=$est');
        expect(r.peak, greaterThanOrEqualTo(wakeAlignMinPeak));
      }
    });
  }

  test('Stille: kein Ergebnis (Rückfall auf die Zeit)', () {
    final r = alignWakeTail(Int16List(20000), Int16List(6400), estimate: 1500);
    expect(r.overlap, isNull);
  });

  test('leises Rauschen unter der Schwelle: kein Ergebnis', () {
    final s = Int16List.fromList([for (final v in source(24000)) v ~/ 1000]);
    final c = cut(s, 20000, 1500);
    expect(alignWakeTail(c.tail, c.app, estimate: 1500).overlap, isNull);
  });

  test('periodisches Signal ist mehrdeutig: kein Ergebnis', () {
    final s = Int16List.fromList([
      for (var i = 0; i < 24000; i++)
        (6000 * math.sin(2 * math.pi * 200 * i / 16000)).round(),
    ]);
    final c = cut(s, 20000, 1500);
    final r = alignWakeTail(c.tail, c.app, estimate: 1500);
    expect(r.overlap, isNull);
    expect(
      r.peak,
      greaterThan(90),
      reason: 'Spitze hoch, aber nicht eindeutig',
    );
  });

  test('zwei verschiedene Aufnahmen: Spitze zu klein', () {
    final a = source(20000, seed: 1);
    final b = source(6400, seed: 2);
    expect(alignWakeTail(a, b, estimate: 1500).overlap, isNull);
  });

  test('stark verrauschte Kopie: Spitze unter der Schwelle, kein Ergebnis', () {
    final s = source(24000);
    final c = cut(s, 20000, 1500);
    final noisy = Int16List.fromList([
      for (final (i, v) in c.app.indexed)
        v + (source(c.app.length, seed: 99)[i] * 1.3).round(),
    ]);
    final r = alignWakeTail(c.tail, noisy, estimate: 1500);
    expect(r.peak, inInclusiveRange(30, wakeAlignMinPeak - 1));
    expect(r.overlap, isNull);
  });

  test('keine Überlappung (Lücke): kein Ergebnis', () {
    final s = source(30000);
    final tail = Int16List.sublistView(s, 0, 20000);
    final app = Int16List.sublistView(s, 21000, 27400); // 1000 samples later
    expect(alignWakeTail(tail, app, estimate: 800).overlap, isNull);
  });

  test('Fenster außerhalb der Grenzen: kein Ergebnis, kein Fehler', () {
    expect(
      alignWakeTail(source(100), source(100), estimate: 50).overlap,
      isNull,
    );
    expect(
      alignWakeTail(source(5000), source(5000), estimate: -5000).overlap,
      isNull,
    );
  });

  group('bridgeWakeTail', () {
    final s = source(40000);
    final pre = WakePreRoll(pcm: Int16List(1600), wakeEnd: 800);

    test('lückenlos und ohne Doppel, obwohl der Zeitstempel 30 ms zu wenig '
        'kürzt', () {
      // tail = s[8000..20000), app = s[18500..): true overlap 1500 samples.
      final tail = Int16List.sublistView(s, 8000, 20000);
      final app = Int16List.sublistView(s, 18500, 18500 + 6400);
      final out = bridgeWakeTail(
        pre,
        (pcm: tail, lastSampleAtMs: 1000),
        // timestamps say 1000 samples overlap (62 ms), truth is 93 ms
        firstFrameAtMs: 1000 - 62 + 100,
        firstFrameSamples: 1600,
        appHead: app,
      );
      // The tail part of the result plus the app audio is the source again.
      final joined = [...out.pcm.sublist(1600), ...app];
      expect(joined, s.sublist(8000, 18500 + 6400));
      final log = lines.singleWhere((l) => l.contains(' wake-gap '));
      expect(log, contains('align=xcorr'));
      expect(log, contains('xcorrMs=${1500 ~/ 16 - 62}'));
      expect(log, contains('trim=${1500 ~/ 16}'));
      expect(log, contains('peak='));
      expect(
        log,
        matches(
          RegExp(
            r'^Wendelin/voice: wake-gap engine=app( \w+=(-?\d+|overlap|xcorr))+$',
          ),
        ),
      );
    });

    test('ohne Signal: Rückfall auf die Zeit, align=time', () {
      final out = bridgeWakeTail(
        pre,
        (pcm: Int16List(12000), lastSampleAtMs: 1000),
        firstFrameAtMs: 1000 - 62 + 100,
        firstFrameSamples: 1600,
        appHead: Int16List(6400),
      );
      expect(out.pcm, hasLength(1600 + 12000 - 62 * 16));
      final log = lines.singleWhere((l) => l.contains(' wake-gap '));
      expect(log, contains('align=time'));
      expect(log, isNot(contains('xcorrMs')));
    });

    test('ohne Anfang des App-Audios: wie bisher (kein align)', () {
      bridgeWakeTail(
        pre,
        (pcm: Int16List.sublistView(s, 8000, 20000), lastSampleAtMs: 1000),
        firstFrameAtMs: 1038,
        firstFrameSamples: 1600,
      );
      expect(lines.single, isNot(contains('align')));
    });

    test('Bestätigungston: der Rest wird nach dem Schnitt stummgeschaltet', () {
      final tail = Int16List.sublistView(s, 8000, 20000);
      final app = Int16List.sublistView(s, 18500, 18500 + 6400);
      final out = bridgeWakeTail(
        WakePreRoll(pcm: Int16List(1600), wakeEnd: 800, muteMicSamples: 800),
        (pcm: tail, lastSampleAtMs: 1000),
        firstFrameAtMs: 1038,
        firstFrameSamples: 1600,
        appHead: app,
      );
      expect(out.pcm.sublist(1600, 2400).every((v) => v == 0), isTrue);
      expect(out.pcm.sublist(2400, 2500), s.sublist(8800, 8900));
      expect(out.muteMicSamples, 0);
    });

    test('Zeit sieht eine Lücke (positiv): Inhalt findet trotzdem die '
        'Überlappung (keine Stille)', () {
      final tail = Int16List.sublistView(s, 8000, 20000);
      final app = Int16List.sublistView(s, 19000, 19000 + 6400);
      final out = bridgeWakeTail(
        pre,
        (pcm: tail, lastSampleAtMs: 1000),
        firstFrameAtMs: 1000 + 20 + 100, // time says a 20 ms hole
        firstFrameSamples: 1600,
        appHead: app,
      );
      expect([...out.pcm.sublist(1600), ...app], s.sublist(8000, 19000 + 6400));
      expect(lines.any((l) => l.contains('wake-gap-fallback')), isFalse);
    });
  });

  test('WakeHandoffTracker: der Anfang des App-Audios kommt von begin '
      '(Verdrahtung)', () async {
    final s = source(40000);
    final tail = Int16List.sublistView(s, 8000, 20000);
    final app = Int16List.sublistView(s, 18500, 18500 + 6400);
    final last = DateTime.now().millisecondsSinceEpoch - 40;
    final taken = WakePreRoll(
      pcm: Int16List(1600),
      wakeEnd: 800,
      lastSampleAtMs: last,
      finish: () async => (pcm: tail, lastSampleAtMs: last),
    );
    int? asked;
    final tracker = WakeHandoffTracker()
      ..begin(taken, (n) {
        asked = n;
        return app;
      });
    tracker.onFirstFrame(1600);
    final out = await tracker.close(taken);
    expect(asked, wakeAlignHead);
    expect(out!.pcm, hasLength(1600 + 12000 - 1500));
    expect(lines.where((l) => l.contains('align=xcorr')), hasLength(1));
  });
}
