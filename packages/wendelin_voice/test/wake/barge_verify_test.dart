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
    return verdict;
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
      Duration cooldown = const Duration(seconds: 100),
      Duration timeout = const Duration(seconds: 6),
      String keyword = 'stop',
    }) async {
      got.clear();
      cands.clear();
      verdicts.clear();
      audio = FakeAudioInput();
      engine = FakeWakeWordEngine(keywordId: keyword);
      v = _Verifier(const BargeVerdict('stop', BargeInKeyword.stop));
      d = WakeWordBargeInDetector(
        audio: audio,
        engine: engine,
        verifier: v,
        cooldown: cooldown,
        verifyTimeout: timeout,
        onCandidate: (k, {required busy}) => cands.add('${k.name} $busy'),
        onVerdict: (r, ms) => verdicts.add(r.result),
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
      expect(verdicts, ['skip']);
    });

    test('Zeitüberschreitung: fail closed', () async {
      await setUp0(timeout: const Duration(milliseconds: 20));
      v.hold = Completer<void>();
      await hit();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(got, isEmpty);
      expect(verdicts, ['skip']);
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
      expect(verdicts, isEmpty);
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
