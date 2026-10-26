// WP113 (K84): „Wendelin“ während der Antwort, Stufe 2 (Gegenprüfung des
// Kandidaten). WP134: das gesprochene „Stopp“ ist ausgebaut.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _Verifier implements BargeVerifier {
  _Verifier(this.verdict);
  BargeVerdict verdict;
  Completer<void>? hold;
  Object? error;
  BargeVerdict Function(Int16List pcm)? decide;
  final calls = <int>[];
  final candidates = <BargeInKeyword>[];

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    calls.add(pcm.length);
    candidates.add(candidate);
    await hold?.future;
    if (error != null) throw error!;
    return decide?.call(pcm) ?? verdict;
  }
}

void main() {
  group('TranscriptBargeVerifier', () {
    Future<BargeVerdict> run(
      String heard, {
      String spoken = '',
      String lang = 'de',
    }) => TranscriptBargeVerifier(
      FixedTranscriptStt(heard),
      language: lang,
      spokenText: () => spoken,
    ).verify(Int16List(16000), candidate: BargeInKeyword.wake);

    test('Wendelin / anderes', () async {
      expect((await run('Wendelin')).keyword, BargeInKeyword.wake);
      expect((await run('Wendelin, stopp')).keyword, BargeInKeyword.wake);
      expect((await run('Guten Tag')).keyword, isNull);
      expect((await run('')).result, 'no');
    });

    test('WP134: „Stopp“ allein unterbricht nicht mehr', () async {
      for (final (heard, lang) in [
        ('Stopp.', 'de'),
        ('Stop', 'en'),
        ('Arrête', 'fr'),
      ]) {
        final v = await run(heard, lang: lang);
        expect(v.keyword, isNull, reason: heard);
        expect(v.result, 'no', reason: heard);
      }
    });

    test('Eigen-Echo: Wort im vorgelesenen Text zählt nicht', () async {
      final w = await run('Wendelin', spoken: 'Ich bin Wendelin.');
      expect(w.keyword, isNull);
      expect(w.result, 'echo');
      // Anderes Wort der Antwort: „Wendelin“ des Nutzers gilt.
      expect(
        (await run('Wendelin', spoken: 'Am Bahnhof ist Halt.')).keyword,
        BargeInKeyword.wake,
      );
    });

    test('vorgelesener Text wird vor der Transkription gelesen', () async {
      var spoken = 'Ich bin Wendelin.';
      final gate = Completer<void>();
      final v = TranscriptBargeVerifier(
        _SlowStt('Wendelin', gate.future),
        spokenText: () => spoken,
      ).verify(Int16List(16000), candidate: BargeInKeyword.wake);
      // Der Ring rutscht weiter, waehrend die Transkription laeuft.
      spoken = 'Ganz anderer Satz.';
      gate.complete();
      expect((await v).result, 'echo');
    });

    test('nur die letzten 2,5 s gehen an die Erkennung', () async {
      final stt = FixedTranscriptStt('Wendelin');
      await TranscriptBargeVerifier(stt)
          .verify(Int16List(100000), candidate: BargeInKeyword.wake);
      expect(stt.lastSamples, 40000);
    });
  });

  group('WakeWordBargeInDetector mit Stufe 2', () {
    late FakeAudioInput audio;
    late FakeWakeWordEngine engine;
    late _Verifier v;
    late WakeWordBargeInDetector d;
    final got = <String>[];
    final cands = <String>[];
    final verdicts = <String>[];

    Future<void> setUp0({
      Duration settle = Duration.zero,
      Duration cooldown = const Duration(seconds: 100),
      Duration timeout = const Duration(seconds: 6),
      String keyword = 'wake',
      Set<int> hitAt = const {},
      Duration clip = const Duration(milliseconds: 2500),
      WakeWordEngine? custom,
    }) async {
      got.clear();
      cands.clear();
      verdicts.clear();
      audio = FakeAudioInput();
      engine = FakeWakeWordEngine(keywordId: keyword, hitAtFrame: hitAt);
      final eng = custom ?? engine;
      v = _Verifier(const BargeVerdict('wake', BargeInKeyword.wake));
      d = WakeWordBargeInDetector(
        audio: audio,
        engine: eng,
        verifier: v,
        clip: clip,
        cooldown: cooldown,
        settle: settle,
        verifyTimeout: timeout,
        onCandidate: (k, {required busy, required score}) =>
            cands.add('${k.name} $busy'),
        onVerdict: (r, ms) => verdicts.add(
          r.reason == null ? r.result : '${r.result}/${r.reason}',
        ),
      );
      d.signals.listen((s) => got.add(s.code));
      await d.start();
    }

    Future<void> hit() async {
      audio.push(FakeWakeWordEngine.markerFrame());
      await pumpEventQueue();
    }

    tearDown(() => d.dispose());

    test('Kandidat bestätigt: Signal mit dem erkannten Wort', () async {
      await setUp0(keyword: 'wake');
      v.verdict = const BargeVerdict('wake', BargeInKeyword.wake);
      await hit();
      expect(got, ['keyword-wake']); // Erkenner entscheidet, nicht Stufe 1
      expect(cands, ['wake false']);
      expect(verdicts, ['wake']);
      expect(v.candidates, [BargeInKeyword.wake]);
    });

    test('Kandidat verworfen: kein Signal', () async {
      await setUp0();
      v.verdict = BargeVerdict.no;
      await hit();
      expect(got, isEmpty);
      expect(verdicts, ['no']);
    });

    test('Fehler der Gegenprüfung: fail closed', () async {
      await setUp0();
      v.error = StateError('model gone');
      await hit();
      expect(got, isEmpty);
      expect(verdicts, [startsWith('skip')]);
    });

    test('Zeitüberschreitung: fail closed', () async {
      await setUp0(timeout: const Duration(milliseconds: 20));
      v.hold = Completer<void>();
      await hit();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(got, isEmpty);
      expect(verdicts, [startsWith('skip')]);
    });

    test('während der Prüfung und im Cooldown: Kandidat verworfen', () async {
      await setUp0();
      v
        ..verdict = BargeVerdict.no
        ..hold = Completer<void>();
      await hit();
      await hit(); // während der Prüfung
      expect(cands, ['wake false', 'wake true']);
      v.hold!.complete();
      await pumpEventQueue();
      await hit(); // Cooldown
      expect(cands.last, 'wake true');
      expect(v.calls, hasLength(1));
    });

    test('Cooldown endet', () async {
      await setUp0(cooldown: Duration.zero);
      v.verdict = BargeVerdict.no;
      await hit();
      await hit();
      expect(v.calls, hasLength(2));
    });

    test(
      'Audio: die letzten 2,5 s samt Kandidat gehen an die Prüfung',
      () async {
        await setUp0();
        for (var i = 0; i < 20; i++) {
          audio.push(Int16List(4000));
        }
        await pumpEventQueue();
        await hit();
        expect(v.calls.single, 40000);
      },
    );

    test('stop() während der Prüfung: Ergebnis wird verworfen', () async {
      await setUp0();
      v.hold = Completer<void>();
      await hit();
      await d.stop();
      v.hold!.complete();
      await pumpEventQueue();
      expect(got, isEmpty);
      expect(verdicts, ['skip/stopped']);
    });

    test('Neustart während der Prüfung: altes Urteil gilt nicht', () async {
      await setUp0();
      v.hold = Completer<void>();
      await hit();
      await d.stop();
      await d.start(); // neue Sitzung, neue Generation
      v.hold!.complete();
      await pumpEventQueue();
      expect(got, isEmpty);
      expect(verdicts, ['skip/stopped']);
      // Die neue Sitzung prüft wieder (nicht durch die alte blockiert).
      v.hold = null;
      await hit();
      expect(got, ['keyword-wake']);
    });

    test('stop() mit wartendem Kandidat: skip/stopped im Log', () async {
      await setUp0(settle: const Duration(milliseconds: 800));
      await hit();
      expect(v.calls, isEmpty);
      await d.stop();
      expect(verdicts, ['skip/stopped']);
      expect(got, isEmpty);
    });

    group('Timing und Stille (Gerätelog 2026-10-21)', () {
      Future<void> frames(int n, {bool loud = false}) async {
        for (var i = 0; i < n; i++) {
          audio.push(
            loud
                ? (Int16List(1600)..fillRange(0, 1600, 5000))
                : Int16List(1600),
          );
        }
        await pumpEventQueue();
      }

      test('Prüfung erst nach dem Wort: Ausschnitt enthält es', () async {
        await setUp0(settle: const Duration(milliseconds: 800));
        // Kandidat, das Wort beginnt gerade (Marker = laut, hier auch Wort).
        audio.push(FakeWakeWordEngine.markerFrame(1600));
        await pumpEventQueue();
        expect(v.calls, isEmpty); // noch nicht: das Wort läuft
        await frames(4, loud: true); // 400 ms
        expect(v.calls, isEmpty);
        await frames(4, loud: true); // 800 ms
        expect(v.calls, hasLength(1));
        expect(got, ['keyword-wake']);
        // Der Ausschnitt reicht über den Kandidaten hinaus (Nachlauf).
        expect(v.calls.single, 1600 * 9);
      });

      test(
        'später Kandidat: Ausschnitt endet an der Sprache, Wort drin',
        () async {
          // Wort bei 1,5 bis 2,1 s, Stufe 1 meldet erst bei 3,9 s.
          await setUp0(settle: const Duration(milliseconds: 800), hitAt: {38});
          v.decide = (pcm) => pcm.contains(7000)
              ? const BargeVerdict('wake', BargeInKeyword.wake)
              : BargeVerdict.no;
          await frames(15);
          for (var i = 0; i < 6; i++) {
            audio.push(Int16List(1600)..fillRange(0, 1600, 7000));
          }
          await frames(4); // Stille bis 2,5 s
          await frames(1, loud: true); // Nachhall bei 2,5 bis 2,6 s
          await frames(12); // bis 3,8 s
          await frames(1); // Kandidat bei 3,9 s
          expect(v.calls, isEmpty);
          await frames(8); // settle
          expect(v.calls, hasLength(1));
          expect(got, ['keyword-wake']);
        },
      );

      test(
        'Ausschnitt endet genau settle nach dem letzten lauten Block',
        () async {
          // Wort 2,0 bis 2,6 s, Kandidat 3,9 s: Nachlauf-Stille = settle
          // (Whisper braucht Stille nach einem kurzen Wort, Gerätebefund).
          await setUp0(settle: const Duration(milliseconds: 800), hitAt: {38});
          Int16List? clip;
          v.decide = (pcm) {
            clip = pcm;
            return BargeVerdict.no;
          };
          await frames(20);
          for (var i = 0; i < 6; i++) {
            audio.push(Int16List(1600)..fillRange(0, 1600, 7000));
          }
          await frames(13); // Kandidat im letzten Frame (3,9 s)
          await frames(8); // settle
          expect(clip, isNotNull);
          expect(clip!.length, 40000);
          var trailing = 0;
          for (var i = clip!.length - 1; i >= 0 && clip![i] != 7000; i--) {
            trailing++;
          }
          expect(trailing, 12800); // 800 ms, Wort vorhanden
          expect(clip!.contains(7000), isTrue);
        },
      );

      test(
        'erst schwacher, dann stärkerer busy-Kandidat: Fenster des stärkeren',
        () async {
          final script = _ScriptEngine(
            {0: 'wake', 2: 'wake', 4: 'wake'},
            conf: {0: 0.5, 2: 0.6, 4: 0.95},
          );
          await setUp0(
            clip: const Duration(milliseconds: 500),
            cooldown: const Duration(seconds: 100),
            custom: script,
          );
          final hold = Completer<void>();
          v
            ..verdict = BargeVerdict.no
            ..hold = hold;
          await frames(10, loud: true); // Treffer bei Frame 0, 2 und 4 (1,0 s)
          expect(v.calls, hasLength(1)); // die Prüfung läuft noch
          v.hold = null;
          hold.complete(); // Urteil der ersten Prüfung: no
          await pumpEventQueue();
          v.verdict = const BargeVerdict('wake', BargeInKeyword.wake);
          await frames(1, loud: true);
          // Das Wort des stärkeren liegt 0,5 s zurück: noch im Ausschnitt.
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );

      test('Kandidat während der Prüfung wird danach erneut geprüft', () async {
        await setUp0(
          settle: Duration.zero,
          cooldown: const Duration(milliseconds: 400),
        );
        v
          ..verdict = BargeVerdict.no
          ..hold = Completer<void>();
        await hit();
        await frames(1, loud: true);
        await hit(); // busy
        expect(cands, ['wake false', 'wake true']);
        v.hold!.complete();
        await pumpEventQueue();
        expect(got, isEmpty);
        v
          ..hold = null
          ..verdict = const BargeVerdict('wake', BargeInKeyword.wake);
        await frames(6, loud: true); // Cooldown endet
        expect(v.calls, hasLength(2));
        expect(got, ['keyword-wake']);
      });

      test(
        'echtes Wendelin im Cooldown nach verworfenem Echo wird geprüft',
        () async {
          await setUp0(cooldown: const Duration(milliseconds: 1500));
          v.verdict = BargeVerdict.no;
          await hit(); // Echo-Kandidat, Urteil no, Cooldown 1,5 s
          expect(verdicts, ['no']);
          v.verdict = const BargeVerdict('wake', BargeInKeyword.wake);
          await frames(10, loud: true); // 1 s später
          await hit(); // das echte Wort, im Cooldown
          expect(cands.last, 'wake true');
          expect(v.calls, hasLength(1));
          await frames(8, loud: true); // Cooldown endet
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );

      test('Echo verworfen, schwaches Echo im Cooldown, dann echter Ruf: '
          'Schnitt am echten Wort (WP151)', () async {
        final script = _ScriptEngine(
          {0: 'wake', 12: 'wake', 22: 'wake'},
          conf: {0: 0.85, 12: 0.86, 22: 0.96},
        );
        await setUp0(
          settle: const Duration(milliseconds: 800),
          cooldown: const Duration(milliseconds: 1500),
          custom: script,
        );
        // Nur ein Ausschnitt mit dem Wort des Nutzers (7000) ist "wake".
        v.decide = (pcm) => pcm.contains(7000)
            ? const BargeVerdict('wake', BargeInKeyword.wake)
            : BargeVerdict.no;
        Future<void> frame(int level) async {
          audio.push(Int16List(1600)..fillRange(0, 1600, level));
          await pumpEventQueue();
        }

        for (var i = 0; i < 3; i++) {
          await frame(5000); // Echo (Frames 0 bis 2)
        }
        for (var i = 3; i < 10; i++) {
          await frame(0);
        }
        expect(verdicts, ['no']); // erste Prüfung nach dem Echo
        await frame(0);
        await frame(0);
        await frame(5000); // Frame 12: schwaches Echo im Cooldown
        for (var i = 13; i < 22; i++) {
          await frame(0);
        }
        await frame(7000); // Frame 22: der echte Ruf, stärker
        for (var i = 23; i < 40; i++) {
          await frame(0);
        }
        expect(v.calls, hasLength(2));
        expect(got, ['keyword-wake']);
      });

      test('Kandidat im Cooldown außerhalb des Ausschnitts verfällt', () async {
        await setUp0(
          cooldown: const Duration(milliseconds: 3000),
          clip: const Duration(milliseconds: 500),
        );
        v.verdict = BargeVerdict.no;
        await hit();
        await hit(); // im Cooldown
        await frames(40, loud: true); // Cooldown endet, Wort lange vorbei
        expect(v.calls, hasLength(1));
        expect(got, isEmpty);
      });

      test('Kandidat früh in langer Prüfung, kurzer Ausschnitt: keine zweite Prüfung', () async {
        await setUp0(
          cooldown: const Duration(milliseconds: 400),
          clip: const Duration(milliseconds: 500),
        );
        v
          ..verdict = BargeVerdict.no
          ..hold = Completer<void>();
        await hit();
        await frames(1, loud: true);
        await hit(); // busy
        await frames(10, loud: true); // die Prüfung dauert lange
        v.hold!.complete();
        await pumpEventQueue();
        v
          ..hold = null
          ..verdict = const BargeVerdict('wake', BargeInKeyword.wake);
        await frames(10, loud: true);
        expect(v.calls, hasLength(1));
        expect(got, isEmpty);
        // WP151: nicht still verworfen, das Log nennt den Grund.
        expect(verdicts, contains('skip/stale'));
      });

      test('Stille im Ausschnitt: skip/silent ohne Erkenner', () async {
        // Kandidat 1,5 s nach lautem Audio, der Ring (1 s) ist still.
        await setUp0(hitAt: {14}, clip: const Duration(milliseconds: 500));
        await frames(1, loud: true);
        await frames(14); // Lautes ist älter als der Ring (2 x Ausschnitt)
        expect(v.calls, isEmpty);
        expect(verdicts, ['skip/silent']);
        expect(got, isEmpty);
      });

      // WP126, lokale Logs: Stille (rms 0) bekommt sim=0.85 > thr,
      // das echte Wort (0.96) kommt danach.
      test('Fenster ohne Pegel ist kein Kandidat (Stille-Score)', () async {
        await setUp0(
          settle: const Duration(milliseconds: 800),
          custom: _ScriptEngine({1: 'wake'}, conf: {1: 0.85}),
        );
        await frames(4); // 400 ms Stille, Treffer in Frame 1
        expect(cands, isEmpty);
        expect(verdicts, ['skip/silent']);
        await frames(20);
        expect(v.calls, isEmpty);
      });

      test(
        'Pegel knapp unter der Grenze zählt nicht, knapp darüber schon',
        () async {
          Int16List level(int v) => Int16List(1600)..fillRange(0, 1600, v);
          Future<void> run(int v) async {
            await setUp0(custom: _ScriptEngine({1: 'wake'}));
            audio.push(level(v));
            audio.push(level(v));
            await pumpEventQueue();
          }

          await run(149);
          expect(cands, isEmpty);
          await d.dispose();
          await run(150);
          expect(cands, ['wake false']);
        },
      );

      test('Stille-Fehlkandidat, danach echtes Wendelin: Signal', () async {
        final script = _ScriptEngine(
          {1: 'wake', 12: 'wake'},
          conf: {1: 0.85, 12: 0.96},
        );
        await setUp0(
          settle: const Duration(milliseconds: 800),
          cooldown: const Duration(milliseconds: 1500),
          custom: script,
        );
        // Nur ein Ausschnitt mit ganzem Wort (>= 5 laute Frames) ist "wake".
        v.decide = (pcm) {
          var loud = 0;
          for (var i = 0; i + 1600 <= pcm.length; i += 1600) {
            if (pcm[i] > 1000) loud++;
          }
          return loud >= 5
              ? const BargeVerdict('wake', BargeInKeyword.wake)
              : BargeVerdict.no;
        };
        await frames(6); // 0,6 s Stille, Fehltreffer in Frame 1
        await frames(16, loud: true); // Wort ab Frame 6, Treffer in Frame 12
        expect(got, ['keyword-wake']); // vor dem Ende eines Cooldowns
        expect(v.calls, hasLength(1)); // nur das echte Wort wurde geprüft
      });

      test(
        'stärkerer Kandidat nach "no" wartet nicht auf den Cooldown',
        () async {
          final script = _ScriptEngine(
            {0: 'wake', 12: 'wake'},
            conf: {0: 0.85, 12: 0.96},
          );
          await setUp0(
            settle: const Duration(milliseconds: 800),
            cooldown: const Duration(milliseconds: 1500),
            custom: script,
          );
          v.verdict = BargeVerdict.no;
          await frames(1, loud: true);
          await frames(10, loud: true); // Echo geprüft: no, Cooldown 1,5 s
          expect(v.calls, hasLength(1));
          v.verdict = const BargeVerdict('wake', BargeInKeyword.wake);
          await frames(2, loud: true); // Frame 12: stärker, im Cooldown
          expect(cands.last, 'wake false');
          await frames(8, loud: true); // eigene Wartezeit, Cooldown läuft noch
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );

      test('gleich starker Kandidat im Cooldown bleibt gesperrt', () async {
        final script = _ScriptEngine(
          {0: 'wake', 12: 'wake'},
          conf: {0: 0.9, 12: 0.92},
        );
        await setUp0(
          settle: const Duration(milliseconds: 800),
          cooldown: const Duration(milliseconds: 1500),
          custom: script,
        );
        v.verdict = BargeVerdict.no;
        await frames(12, loud: true);
        await frames(8, loud: true);
        expect(cands.last, 'wake true');
        expect(v.calls, hasLength(1));
      });

      test(
        'Kandidat während der Prüfung, stärker: eigenes Fenster nach "no"',
        () async {
          final script = _ScriptEngine(
            {0: 'wake', 3: 'wake'},
            conf: {0: 0.85, 3: 0.96},
          );
          await setUp0(
            settle: const Duration(milliseconds: 200),
            cooldown: const Duration(milliseconds: 1500),
            custom: script,
          );
          v
            ..verdict = BargeVerdict.no
            ..hold = Completer<void>();
          await frames(1, loud: true);
          await frames(3, loud: true); // Prüfung läuft, Frame 3 ist busy
          expect(cands, ['wake false', 'wake true']);
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..verdict = const BargeVerdict('wake', BargeInKeyword.wake);
          await frames(2, loud: true); // weit vor dem Ende des Cooldowns
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );

      test(
        'WP151: stärkerer Kandidat in langer Prüfung geht nicht verloren',
        () async {
          // Gerätelog 2026-10-26: sim 0,73 mit busy=true kam nie an die Reihe,
          // weil die Prüfung des ersten länger als der Ausschnitt dauerte.
          final script = _ScriptEngine(
            {0: 'wake', 3: 'wake'},
            conf: {0: 0.54, 3: 0.73},
          );
          await setUp0(
            settle: const Duration(milliseconds: 200),
            cooldown: const Duration(milliseconds: 1500),
            custom: script,
          );
          v
            ..verdict = BargeVerdict.no
            ..hold = Completer<void>();
          await frames(3, loud: true);
          audio.push(Int16List(1600)..fillRange(0, 1600, 7000)); // Wort, busy
          await pumpEventQueue();
          await frames(40, loud: true); // die Prüfung dauert 4 s
          expect(cands, ['wake false', 'wake true']);
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..decide = (pcm) => pcm.contains(7000)
                ? const BargeVerdict('wake', BargeInKeyword.wake)
                : BargeVerdict.no;
          await frames(1, loud: true);
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );

      test(
        'WP151: Wort des Kandidaten in der Prüfung läuft bis settle weiter',
        () async {
          final script = _ScriptEngine(
            {0: 'wake', 3: 'wake'},
            conf: {0: 0.54, 3: 0.73},
          );
          await setUp0(
            settle: const Duration(milliseconds: 200),
            cooldown: const Duration(milliseconds: 1500),
            custom: script,
          );
          v
            ..verdict = BargeVerdict.no
            ..hold = Completer<void>();
          await frames(3, loud: true);
          audio.push(Int16List(1600)..fillRange(0, 1600, 5000)); // Kandidat
          await frames(2, loud: true); // das Wort geht weiter
          // Nachlauf des Wortes (leise, unter dem Pegel) mit Kennzeichen.
          audio.push(Int16List(1600)..fillRange(0, 1600, 100));
          await pumpEventQueue();
          await frames(40, loud: true); // die Prüfung dauert 4 s
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..decide = (pcm) => pcm.contains(100)
                ? const BargeVerdict('wake', BargeInKeyword.wake)
                : BargeVerdict.no;
          await frames(1, loud: true);
          expect(got, ['keyword-wake']);
        },
      );

      test(
        'schwächerer busy-Kandidat verschiebt das Fenster des stärkeren nicht',
        () async {
          final script = _ScriptEngine(
            {0: 'wake', 3: 'wake', 4: 'wake'},
            conf: {0: 0.85, 3: 0.96, 4: 0.9},
          );
          await setUp0(
            settle: const Duration(milliseconds: 200),
            cooldown: const Duration(milliseconds: 1500),
            custom: script,
          );
          v
            ..verdict = BargeVerdict.no
            ..hold = Completer<void>();
          await frames(1, loud: true);
          await frames(4, loud: true); // Frame 3 stark, Frame 4 schwächer, busy
          expect(cands, ['wake false', 'wake true', 'wake true']);
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..verdict = const BargeVerdict('wake', BargeInKeyword.wake);
          await frames(
            1,
            loud: true,
          ); // Fenster des stärkeren, nicht des schwächeren
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-wake']);
        },
      );
    });

    test('ohne Prüfer ist der Treffer das Signal (wie bisher)', () async {
      final a = FakeAudioInput();
      final plain = WakeWordBargeInDetector(
        audio: a,
        engine: FakeWakeWordEngine(keywordId: 'wake'),
      );
      final out = <String>[];
      plain.signals.listen((s) => out.add(s.code));
      await plain.start();
      a.push(FakeWakeWordEngine.markerFrame());
      await pumpEventQueue();
      expect(out, ['keyword-wake']);
      await plain.dispose();
    });
  });
}

/// Engine with a script: frame index -> keyword id (a hit per entry).
final class _ScriptEngine implements WakeWordEngine {
  _ScriptEngine(this.ids, {this.conf = const {}});
  final Map<int, String> ids;
  final Map<int, double> conf;
  int _i = 0, _samples = 0;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {}

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final index = _i++;
    final id = ids[index];
    _samples += frame.length;
    return id == null
        ? const []
        : [
            WakeWordHit(
              keywordId: id,
              endSample: _samples,
              confidence: conf[index] ?? 0.9,
            ),
          ];
  }

  @override
  void reset() {
    _i = 0;
    _samples = 0;
  }

  @override
  Future<void> close() async {}
}

final class _SlowStt implements SpeechToText {
  _SlowStt(this.text, this.gate);
  final String text;
  final Future<void> gate;

  @override
  SpeechToTextEngineInfo get info =>
      const SpeechToTextEngineInfo(name: 'slow', languages: {'de'});

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    await gate;
    return Transcript(text: text);
  }
}
