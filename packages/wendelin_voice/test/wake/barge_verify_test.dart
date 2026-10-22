// WP113 (K84): „Stopp“ während der Antwort. Wertung bei zwei Treffern
// (Gerätebefund 2026-10-20) und Stufe 2 (Gegenprüfung des Kandidaten).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Float32List _v(double deg) {
  final r = deg * math.pi / 180;
  return Float32List.fromList([math.cos(r), math.sin(r)]);
}

double _deg(double similarity) => math.acos(similarity) * 180 / math.pi;

WakeTemplates _tpl(double deg, double threshold) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: threshold,
  embeddings: [_v(deg)],
);

/// Hits of an engine with the wake template at 0 deg (threshold [thr]) and the
/// stop template at [stopDeg] (threshold [sthr]) for the window sequence
/// [windows] (angle in degrees), one window per 100 samples.
Future<List<String>> _hits(
  List<double> windows, {
  required double stopDeg,
  double thr = 0.85,
  double sthr = 0.90,
  SpeechGate? gate,
  bool verify = true,
}) async {
  var i = 0;
  final e = CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: 100,
      windowFor: (end, _) =>
          WakeWindow(endSample: end, embedding: _v(windows[i++])),
    ),
    templates: _tpl(0, thr),
    stopTemplates: [_tpl(stopDeg, sthr)],
    modelThreshold: null,
    refractory: Duration.zero,
    stopGate: gate,
    stopOverridesWake: verify,
  );
  await e.open([KeywordSpec.wendelin]);
  final ids = <String>[];
  for (var k = 0; k < windows.length; k++) {
    ids.addAll([for (final h in await e.accept(Int16List(100))) h.keywordId]);
  }
  return ids;
}

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
  group('Wertung Stopp vor Wake (Gerätebefund 2026-10-20)', () {
    // Log: sim 0.85 (thr 0.85) und stop 0.94 (sthr 0.90) im selben Fenster.
    // Stopp-Vorlage bei a, Fenster bei w: cos(w) = 0.85, cos(w - a) = 0.94.
    final w = _deg(0.85);
    final a = w - _deg(0.94);

    test('beide über der Schwelle im selben Fenster: stop', () async {
      expect(await _hits([w], stopDeg: a), ['stop']);
      // Gegenprobe: das Fenster ist wirklich über beiden Schwellen.
      expect(math.cos(w * math.pi / 180), closeTo(0.85, 1e-6));
      expect(math.cos((w - a) * math.pi / 180), closeTo(0.94, 1e-6));
    });

    test('Stopp-Spitze, im nächsten Fenster nur noch Wake: stop', () async {
      // Wake-Vorlage 0 Grad, Stopp-Vorlage 90 Grad: Fenster 1 ist nur Stopp
      // (eine Spitze), Fenster 2 nur Wake.
      expect(await _hits([85, 0], stopDeg: 90), ['stop']);
    });

    test('Gerätelog 2026-10-21: stop 0.96 > sthr, still danach: stop', () async {
      // sim 0.85 (thr 0.75), stop 0.96 (sthr 0.70); nach dem Wort ist es still,
      // der Pegelfilter hält die Stopp-Wertung zurück, das Wort bleibt Stopp.
      final w = _deg(0.85);
      final a = w - _deg(0.96);
      expect(
        await _hits([w], stopDeg: a, thr: 0.75, sthr: 0.70, gate: SpeechGate()),
        ['stop'],
      );
      // Nur Wake über der Schwelle (Stopp darunter): bleibt wake.
      expect(
        await _hits(
          [w],
          stopDeg: w + 60,
          thr: 0.75,
          sthr: 0.70,
          gate: SpeechGate(),
        ),
        ['wake'],
      );
    });

    test(
      'ohne Stufe 2 wird Wendelin nicht zu Stopp (WP80-Gate bleibt)',
      () async {
        final w = _deg(0.85);
        final a = w - _deg(0.96);
        // Gleiches Fenster wie oben (Stopp roh über der Schwelle, Pegelfilter
        // hält zurück): mit Stufe 2 stop, ohne bleibt es wake.
        expect(
          await _hits(
            [w],
            stopDeg: a,
            thr: 0.75,
            sthr: 0.70,
            gate: SpeechGate(),
            verify: false,
          ),
          ['wake'],
        );
      },
    );

    test('reines Wendelin (Stopp deutlich darunter) bleibt wake', () async {
      expect(await _hits([0, 0], stopDeg: 80), ['wake', 'wake']);
    });

    test('Wake lange nach einer Stopp-Spitze ist wieder wake', () async {
      expect(await _hits([85, 45, 45, 45, 0], stopDeg: 90), ['wake']);
    });
  });

  group('Stopp-Wörter', () {
    test('de/en/fr', () {
      expect(containsStopWord('Stopp!'), isTrue);
      expect(containsStopWord('Stop.'), isTrue);
      expect(containsStopWord('Stop', language: 'en'), isTrue);
      expect(containsStopWord('Arrête !', language: 'fr'), isTrue);
      expect(containsStopWord('arrete', language: 'fr'), isTrue);
      expect(containsStopWord('Stopp', language: 'xx'), isTrue); // -> de
    });
    test('kein Treffer', () {
      expect(containsStopWord('Haltestelle'), isFalse);
      expect(containsStopWord('Arrête', language: 'de'), isFalse);
      expect(containsStopWord(''), isFalse);
    });
  });

  group('TranscriptBargeVerifier', () {
    Future<BargeVerdict> run(
      String heard, {
      String spoken = '',
      String lang = 'de',
    }) => TranscriptBargeVerifier(
      FixedTranscriptStt(heard),
      language: lang,
      spokenText: () => spoken,
    ).verify(Int16List(16000), candidate: BargeInKeyword.stop);

    test('Stopp / Wendelin / anderes', () async {
      expect((await run('Stopp.')).keyword, BargeInKeyword.stop);
      expect((await run('Wendelin')).keyword, BargeInKeyword.wake);
      expect((await run('Wendelin, stopp')).keyword, BargeInKeyword.wake);
      expect((await run('Arrête', lang: 'fr')).keyword, BargeInKeyword.stop);
      expect((await run('Guten Tag')).keyword, isNull);
      expect((await run('')).result, 'no');
    });

    test('Eigen-Echo: Wort im vorgelesenen Text zählt nicht', () async {
      final v = await run('Stopp', spoken: 'Am Bahnhof Stopp und weiter.');
      expect(v.keyword, isNull);
      expect(v.result, 'echo');
      final w = await run('Wendelin', spoken: 'Ich bin Wendelin.');
      expect(w.result, 'echo');
      // Anderes Wort der Antwort: „Stopp“ des Nutzers gilt.
      expect(
        (await run('Stopp', spoken: 'Ich bin Wendelin.')).keyword,
        BargeInKeyword.stop,
      );
    });

    test('vorgelesener Text wird vor der Transkription gelesen', () async {
      var spoken = 'Am Bahnhof Stopp und weiter.';
      final gate = Completer<void>();
      final v = TranscriptBargeVerifier(
        _SlowStt('Stopp', gate.future),
        spokenText: () => spoken,
      ).verify(Int16List(16000), candidate: BargeInKeyword.stop);
      // Der Ring rutscht weiter, waehrend die Transkription laeuft.
      spoken = 'Ganz anderer Satz.';
      gate.complete();
      expect((await v).result, 'echo');
    });

    test('nur die letzten 2,5 s gehen an die Erkennung', () async {
      final stt = FixedTranscriptStt('Stopp');
      await TranscriptBargeVerifier(stt)
          .verify(Int16List(100000), candidate: BargeInKeyword.stop);
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
      String keyword = 'stop',
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
      v = _Verifier(const BargeVerdict('stop', BargeInKeyword.stop));
      d = WakeWordBargeInDetector(
        audio: audio,
        engine: eng,
        verifier: v,
        clip: clip,
        cooldown: cooldown,
        settle: settle,
        verifyTimeout: timeout,
        onCandidate: (k, {required busy}) => cands.add('${k.name} $busy'),
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
      v.verdict = const BargeVerdict('stop', BargeInKeyword.stop);
      await hit();
      expect(got, ['keyword-stop']); // Erkenner entscheidet, nicht Stufe 1
      expect(cands, ['wake false']);
      expect(verdicts, ['stop']);
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
      expect(cands, ['stop false', 'stop true']);
      v.hold!.complete();
      await pumpEventQueue();
      await hit(); // Cooldown
      expect(cands.last, 'stop true');
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
      expect(got, ['keyword-stop']);
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
        expect(got, ['keyword-stop']);
        // Der Ausschnitt reicht über den Kandidaten hinaus (Nachlauf).
        expect(v.calls.single, 1600 * 9);
      });

      test(
        'später Kandidat: Ausschnitt endet an der Sprache, Wort drin',
        () async {
          // Wort bei 1,5 bis 2,1 s, Stufe 1 meldet erst bei 3,9 s.
          await setUp0(settle: const Duration(milliseconds: 800), hitAt: {38});
          v.decide = (pcm) => pcm.contains(7000)
              ? const BargeVerdict('stop', BargeInKeyword.stop)
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
          expect(got, ['keyword-stop']);
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
            {0: 'stop', 2: 'stop', 4: 'stop'},
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
          v.verdict = const BargeVerdict('stop', BargeInKeyword.stop);
          await frames(1, loud: true);
          // Das Wort des stärkeren liegt 0,5 s zurück: noch im Ausschnitt.
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-stop']);
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
        expect(cands, ['stop false', 'stop true']);
        v.hold!.complete();
        await pumpEventQueue();
        expect(got, isEmpty);
        v
          ..hold = null
          ..verdict = const BargeVerdict('stop', BargeInKeyword.stop);
        await frames(6, loud: true); // Cooldown endet
        expect(v.calls, hasLength(2));
        expect(got, ['keyword-stop']);
      });

      test(
        'echtes Stopp im Cooldown nach verworfenem Echo wird geprüft',
        () async {
          await setUp0(cooldown: const Duration(milliseconds: 1500));
          v.verdict = BargeVerdict.no;
          await hit(); // Echo-Kandidat, Urteil no, Cooldown 1,5 s
          expect(verdicts, ['no']);
          v.verdict = const BargeVerdict('stop', BargeInKeyword.stop);
          await frames(10, loud: true); // 1 s später
          await hit(); // das echte Stopp, im Cooldown
          expect(cands.last, 'stop true');
          expect(v.calls, hasLength(1));
          await frames(8, loud: true); // Cooldown endet
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-stop']);
        },
      );

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
          ..verdict = const BargeVerdict('stop', BargeInKeyword.stop);
        await frames(10, loud: true);
        expect(v.calls, hasLength(1));
        expect(got, isEmpty);
      });

      test('Stopp hat Vorrang vor Wake im selben Wartefenster', () async {
        final script = _ScriptEngine({0: 'stop', 1: 'wake'});
        await setUp0(settle: const Duration(milliseconds: 800), custom: script);
        // Stopp zuerst, dann Wake im Settle: der Prüfer bekommt stop.
        audio.push(FakeWakeWordEngine.markerFrame(1600));
        await pumpEventQueue();
        audio.push(FakeWakeWordEngine.markerFrame(1600));
        await frames(8, loud: true);
        expect(v.candidates, [BargeInKeyword.stop]);
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

      // WP126, lokale Logs: Stille (rms 0) bekommt stop=0.85 > sthr,
      // das echte Stopp (0.96) kommt danach.
      test('Fenster ohne Pegel ist kein Kandidat (Stille-Score)', () async {
        await setUp0(
          settle: const Duration(milliseconds: 800),
          custom: _ScriptEngine({1: 'stop'}, conf: {1: 0.85}),
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
            await setUp0(custom: _ScriptEngine({1: 'stop'}));
            audio.push(level(v));
            audio.push(level(v));
            await pumpEventQueue();
          }

          await run(149);
          expect(cands, isEmpty);
          await d.dispose();
          await run(150);
          expect(cands, ['stop false']);
        },
      );

      test('Stille-Fehlkandidat, danach echtes Stopp: Signal', () async {
        final script = _ScriptEngine(
          {1: 'stop', 12: 'stop'},
          conf: {1: 0.85, 12: 0.96},
        );
        await setUp0(
          settle: const Duration(milliseconds: 800),
          cooldown: const Duration(milliseconds: 1500),
          custom: script,
        );
        // Nur ein Ausschnitt mit ganzem Wort (>= 5 laute Frames) ist "stop".
        v.decide = (pcm) {
          var loud = 0;
          for (var i = 0; i + 1600 <= pcm.length; i += 1600) {
            if (pcm[i] > 1000) loud++;
          }
          return loud >= 5
              ? const BargeVerdict('stop', BargeInKeyword.stop)
              : BargeVerdict.no;
        };
        await frames(6); // 0,6 s Stille, Fehltreffer in Frame 1
        await frames(16, loud: true); // Wort ab Frame 6, Treffer in Frame 12
        expect(got, ['keyword-stop']); // vor dem Ende eines Cooldowns
        expect(v.calls, hasLength(1)); // nur das echte Wort wurde geprüft
      });

      test(
        'stärkerer Kandidat nach "no" wartet nicht auf den Cooldown',
        () async {
          final script = _ScriptEngine(
            {0: 'stop', 12: 'stop'},
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
          v.verdict = const BargeVerdict('stop', BargeInKeyword.stop);
          await frames(2, loud: true); // Frame 12: stärker, im Cooldown
          expect(cands.last, 'stop false');
          await frames(8, loud: true); // eigene Wartezeit, Cooldown läuft noch
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-stop']);
        },
      );

      test('gleich starker Kandidat im Cooldown bleibt gesperrt', () async {
        final script = _ScriptEngine(
          {0: 'stop', 12: 'stop'},
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
        expect(cands.last, 'stop true');
        expect(v.calls, hasLength(1));
      });

      test(
        'Kandidat während der Prüfung, stärker: eigenes Fenster nach "no"',
        () async {
          final script = _ScriptEngine(
            {0: 'stop', 3: 'stop'},
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
          expect(cands, ['stop false', 'stop true']);
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..verdict = const BargeVerdict('stop', BargeInKeyword.stop);
          await frames(2, loud: true); // weit vor dem Ende des Cooldowns
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-stop']);
        },
      );

      test(
        'schwächerer busy-Kandidat verschiebt das Fenster des stärkeren nicht',
        () async {
          final script = _ScriptEngine(
            {0: 'stop', 3: 'stop', 4: 'stop'},
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
          expect(cands, ['stop false', 'stop true', 'stop true']);
          v.hold!.complete();
          await pumpEventQueue();
          v
            ..hold = null
            ..verdict = const BargeVerdict('stop', BargeInKeyword.stop);
          await frames(
            1,
            loud: true,
          ); // Fenster des stärkeren, nicht des schwächeren
          expect(v.calls, hasLength(2));
          expect(got, ['keyword-stop']);
        },
      );
    });

    test('ohne Prüfer ist der Treffer das Signal (wie bisher)', () async {
      final a = FakeAudioInput();
      final plain = WakeWordBargeInDetector(
        audio: a,
        engine: FakeWakeWordEngine(keywordId: 'stop'),
      );
      final out = <String>[];
      plain.signals.listen((s) => out.add(s.code));
      await plain.start();
      a.push(FakeWakeWordEngine.markerFrame());
      await pumpEventQueue();
      expect(out, ['keyword-stop']);
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
