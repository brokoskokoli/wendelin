// WP155: Weckwort-Archiv, Seite des Sprachkerns. Audio ist synthetisch
// (fortlaufende Zähler), die Erkennung ein Skript.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Int16List counting(int from, [int n = 480]) =>
    Int16List.fromList([for (var i = 0; i < n; i++) (from + i) % 30000]);

final class _Archive {
  _Archive({this.on = true});
  bool on;
  bool throwOnWrite = false;
  final entries = <DevArchiveEntry>[];
  final clips = <DevClip>[];
  late final hook = DevClips(
    enabled: () => on,
    write: clips.add,
    archive: DevArchive(
      write: (e) {
        if (throwOnWrite) throw StateError('disk');
        entries.add(e);
      },
      context: (source) => {'app': 'test', 'src': source},
      takeStt: () => {'text': 'wendelin', 'lp': -0.1},
    ),
  );
}

void main() {
  group('NearMissTracker', () {
    NearMissTracker make() => NearMissTracker(above: 0.98);

    NearMiss? run(NearMissTracker t, Map<int, double> scores, int until) {
      NearMiss? out;
      for (var end = 1600; end <= until; end += 1600) {
        final m = t.onScore(end, scores[end ~/ 1600] ?? 0);
        if (m != null) {
          expect(out, isNull, reason: 'genau ein Eintrag');
          out = m;
        }
      }
      return out;
    }

    test(
      'eine Äußerung mit vielen Fenstern ergibt genau eine, Spitze zählt',
      () {
        final m = run(make(), {10: 0.55, 11: 0.8, 12: 0.7, 13: 0.6}, 40000);
        expect(m, isNotNull);
        expect(m!.peak, 0.8);
        expect(m.peakEnd, 11 * 1600);
      },
    );

    test('unter der Sammelschwelle: nichts', () {
      expect(run(make(), {10: 0.49, 11: 0.3}, 40000), isNull);
    });

    test('Lauf mit einem Wert ab 0,98 (Kandidat samt Anstieg) zählt nicht', () {
      expect(run(make(), {10: 0.6, 11: 0.99, 12: 0.7}, 40000), isNull);
    });

    test('NaN ist kein Wert', () {
      final t = make();
      expect(t.onScore(1600, double.nan), isNull);
      expect(t.onScore(40000, 0), isNull);
    });

    test('zwei Äußerungen nah beieinander: zweite wird entprellt', () {
      final t = make();
      final found = <NearMiss>[];
      for (var end = 1600; end <= 400000; end += 1600) {
        final i = end ~/ 1600;
        // Spitze bei 10 und bei 50 (64000 Samples = 4 s später), dann 150.
        final s = {10: 0.7, 50: 0.7, 150: 0.7}[i] ?? 0.0;
        final m = t.onScore(end, s);
        if (m != null) found.add(m);
      }
      // 4 s < 5 s Abstand: die zweite fällt weg, die dritte kommt.
      expect(found.map((m) => m.peakEnd), [10 * 1600, 150 * 1600]);
    });
  });

  group('DevArchiveCase', () {
    test('geht erst raus, wenn Ergebnis und Clip da sind, genau einmal', () {
      final a = _Archive();
      final c = a.hook.archiveCase('idle')!;
      c.finish('accepted', {'x': 1});
      expect(a.entries, isEmpty);
      // Zweiter Aufruf zählt nicht, auch nicht vor dem Clip (Ergebnis und
      // Zusatzfelder bleiben die des ersten).
      c.finish('rejected', {'y': 2});
      c
        ..clip(DevClip(event: 'e', pcm: Int16List(3), at: DateTime(2026)))
        ..finish('dropped') // und danach schon gar nicht
        ..giveUpClip();
      expect(a.entries, hasLength(1));
      expect(a.entries.single.outcome, 'accepted');
      expect(a.entries.single.meta, {'app': 'test', 'src': 'idle', 'x': 1});
    });

    test('aus: kein Fall', () {
      expect(_Archive(on: false).hook.archiveCase('idle'), isNull);
    });

    test('Schreibfehler wirft nicht', () {
      final a = _Archive()..throwOnWrite = true;
      final c = a.hook.archiveCase('idle')!..giveUpClip();
      expect(() => c.finish('accepted'), returnsNormally);
    });
  });

  group('WakeWordListener', () {
    late FakeAudioInput audio;
    late _Archive arch;
    late WakeWordListener listener;
    late FakeWakeVerifier verifier;
    final detections = <WakeWordDetection>[];

    Future<void> setUpListener({
      bool on = true,
      FakeWakeWordEngine? engine,
      bool verify = true,
    }) async {
      arch = _Archive(on: on);
      detections.clear();
      audio = FakeAudioInput();
      verifier = FakeWakeVerifier();
      listener = WakeWordListener(
        audio: audio,
        engine: engine ?? FakeWakeWordEngine(hitAtFrame: {99}),
        verifier: verify ? verifier : null,
        verifyTail: Duration.zero,
        devClips: arch.hook,
      );
      listener.detections.listen(detections.add);
      await listener.start();
    }

    Future<void> feed(int frames, {int from = 0}) async {
      for (var i = 0; i < frames; i++) {
        audio.push(counting((from + i) * 480));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    tearDown(() => listener.dispose());

    test(
      'angenommen: ein Eintrag mit Clip, Prüf-Ausschnitt und Zahlen',
      () async {
        await setUpListener();
        await feed(175);
        expect(arch.entries, hasLength(1));
        final e = arch.entries.single;
        expect(e.source, 'idle');
        expect(e.outcome, 'accepted');
        expect(e.cand!.pcm.length, 64000);
        expect(e.verify, isNotNull);
        expect(e.meta['verdict'], 'ok');
        expect(e.meta['verifier'], 'fake');
        expect(e.meta['text'], 'wendelin');
        expect(e.meta['lp'], -0.1);
        expect(e.meta['app'], 'test');
        expect(detections, hasLength(1));
      },
    );

    test('abgelehnt: ein Eintrag rejected, kein Treffer', () async {
      await setUpListener();
      verifier.answer = (_) => false;
      await feed(175);
      expect(arch.entries.single.outcome, 'rejected');
      expect(arch.entries.single.meta['verdict'], 'no');
      expect(detections, isEmpty);
    });

    test(
      'sicherer Treffer ohne Prüfung: accepted, Pfad direct, kein Prüf-Clip',
      () async {
        await setUpListener(
          engine: FakeWakeWordEngine(hitAtFrame: {99}, direct: true),
        );
        await feed(175);
        final e = arch.entries.single;
        expect(e.outcome, 'accepted');
        expect(e.meta['path'], 'direct');
        expect(e.verify, isNull);
      },
    );

    test('Prüfer wirft: rejected mit verdict error', () async {
      await setUpListener();
      verifier.error = StateError('x');
      await feed(175);
      expect(arch.entries.single.outcome, 'rejected');
      expect(arch.entries.single.meta['verdict'], 'error');
    });

    test('knapp verfehlt: genau ein Eintrag je Äußerung, nur Archiv', () async {
      await setUpListener(
        engine: FakeWakeWordEngine(
          scoreAtFrame: {80: 0.55, 81: 0.9, 82: 0.7, 83: 0.6},
        ),
      );
      await feed(240);
      expect(arch.entries, hasLength(1));
      final e = arch.entries.single;
      expect(e.outcome, 'near-miss');
      expect(e.meta['score'], '0.9000');
      // Spitze bei Frame 81 (Ende 82*480), ±2 s, ohne kurzlebige Datei.
      expect(e.cand!.pcm.length, 64000);
      expect(e.cand!.pcm.first, (82 * 480 - 32000) % 30000);
      expect(arch.clips.where((c) => c.event == 'near-miss'), isEmpty);
      expect(listener.stats.candidates, 0);
    });

    test('Wert unter der Sammelschwelle: kein Eintrag', () async {
      await setUpListener(
        engine: FakeWakeWordEngine(scoreAtFrame: {20: 0.49, 21: 0.3}),
      );
      await feed(160);
      expect(arch.entries, isEmpty);
    });

    test('Kandidat über 0,98: kein zusätzlicher near-miss', () async {
      await setUpListener(
        engine: FakeWakeWordEngine(
          hitAtFrame: {99},
          scoreAtFrame: {90: 0.6, 95: 0.8, 99: 0.99, 101: 0.7},
        ),
      );
      await feed(260);
      expect(arch.entries.map((e) => e.outcome), ['accepted']);
    });

    test('Entwicklermodus aus: kein Fall, kein Eintrag, keine Datei', () async {
      await setUpListener(
        on: false,
        engine: FakeWakeWordEngine(
          hitAtFrame: {99},
          scoreAtFrame: {10: 0.8, 20: 0.7},
        ),
      );
      await feed(175);
      expect(arch.entries, isEmpty);
      expect(arch.clips, isEmpty);
      expect(detections, hasLength(1));
    });

    test('Schreibfehler ändern das Ergebnis nicht', () async {
      await setUpListener();
      arch.throwOnWrite = true;
      await feed(175);
      expect(detections, hasLength(1));
      expect(listener.state, WakeListenerState.listening);
    });

    test(
      'Stopp mitten in der Prüfung: Eintrag dropped (stopped), nicht verloren',
      () async {
        await setUpListener();
        verifier.gate = Completer<void>();
        await feed(110);
        await listener.pause();
        verifier.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(arch.entries.single.outcome, 'dropped');
        expect(arch.entries.single.meta['reason'], 'stopped');
      },
    );
  });

  group('WakeWordBargeInDetector', () {
    late FakeAudioInput audio;
    late _Archive arch;
    late WakeWordBargeInDetector d;
    late _Verifier verifier;

    Future<void> setUpDetector({
      bool on = true,
      Duration cooldown = const Duration(seconds: 100),
      bool verify = true,
    }) async {
      arch = _Archive(on: on);
      verifier = _Verifier();
      audio = FakeAudioInput();
      d = WakeWordBargeInDetector(
        audio: audio,
        engine: FakeWakeWordEngine(),
        verifier: verify ? verifier : null,
        settle: Duration.zero,
        cooldown: cooldown,
        devClips: arch.hook,
      );
      await d.start();
    }

    Future<void> loud(int n) async {
      for (var i = 0; i < n; i++) {
        audio.push(Int16List(1600)..fillRange(0, 1600, 5000));
      }
      await pumpEventQueue();
    }

    Future<void> cand() async {
      audio.push(FakeWakeWordEngine.markerFrame(1600));
      await pumpEventQueue();
    }

    tearDown(() => d.dispose());

    test(
      'angenommen: ein Eintrag barge mit Clip, Prüf-Clip, Ergebnis',
      () async {
        await setUpDetector();
        verifier.verdict = const BargeVerdict(
          'wake',
          BargeInKeyword.wake,
          null,
          'b',
          0.9123,
        );
        await loud(30);
        await cand();
        await loud(25);
        expect(arch.entries, hasLength(1));
        final e = arch.entries.single;
        expect(e.source, 'barge');
        expect(e.outcome, 'accepted');
        expect(e.cand!.pcm.length, 64000);
        expect(e.verify, isNotNull);
        expect(e.meta['verifier'], 'b');
        expect(e.meta['score'], '0.9123');
        expect(e.meta['text'], 'wendelin');
        expect(e.meta['busy'], false);
      },
    );

    test('abgelehnt: rejected', () async {
      await setUpDetector();
      await loud(30);
      await cand();
      await loud(25);
      expect(arch.entries.single.outcome, 'rejected');
      expect(arch.entries.single.meta['result'], 'no');
    });

    test(
      'busy: der verworfene Kandidat hat genau einen Eintrag (dropped, busy)',
      () async {
        await setUpDetector();
        verifier.gate = Completer<void>();
        await loud(30);
        await cand(); // startet die Prüfung (settle 0)
        await loud(2);
        await cand(); // busy
        await loud(2);
        await cand(); // busy, schwächer oder gleich: einer von beiden fällt weg
        await loud(25);
        verifier.gate!.complete();
        await pumpEventQueue();
        await loud(25);
        // Genau ein Kandidat wird geprüft (rejected), genau einer als busy
        // verworfen; der stärkere busy-Kandidat wartet und wird nie doppelt
        // geschrieben.
        expect(
          arch.entries.where((e) => e.outcome == 'rejected'),
          hasLength(1),
        );
        expect(
          arch.entries.where(
            (e) => e.outcome == 'dropped' && e.meta['reason'] == 'busy',
          ),
          hasLength(1),
        );
        expect(arch.entries.map((e) => e.outcome).toList()..sort(), [
          'dropped',
          'rejected',
        ]);
      },
    );

    test('Stopp mit wartendem Kandidaten: dropped (stopped)', () async {
      await setUpDetector();
      verifier.gate = Completer<void>();
      await loud(30);
      await cand();
      await loud(1);
      await d.stop();
      verifier.gate!.complete();
      await pumpEventQueue();
      expect(arch.entries.map((e) => e.outcome), ['dropped']);
      expect(arch.entries.single.meta['reason'], 'stopped');
    });

    test('ohne Prüfer: accepted (unchecked)', () async {
      await setUpDetector(verify: false);
      await loud(30);
      await cand();
      await loud(25);
      final e = arch.entries.single;
      expect(e.outcome, 'accepted');
      expect(e.meta['path'], 'unchecked');
    });

    test('aus: nichts', () async {
      await setUpDetector(on: false);
      await loud(30);
      await cand();
      await loud(25);
      expect(arch.entries, isEmpty);
      expect(arch.clips, isEmpty);
    });
  });
}

final class _Verifier implements BargeVerifier {
  BargeVerdict verdict = BargeVerdict.no;
  Completer<void>? gate;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    await gate?.future;
    return verdict;
  }
}
