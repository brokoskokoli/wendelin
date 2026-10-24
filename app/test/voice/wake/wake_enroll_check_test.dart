import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/speaker/speaker_recording.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/utterance_capture.dart';
import 'package:wendelin/voice/wake/wake_enroller.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/wake_fixtures.dart';
import '../../support/wake_support.dart';

/// Feature chain whose embedding depends on the number of the recording
/// (counted by `reset`, called twice per embedding) and whose classifier
/// score is scripted per recording.
final class _Chain implements WakeFeatureExtractor {
  _Chain({this.vectorOf, this.scoreOf});

  final List<double> Function(int recording)? vectorOf;
  final double? Function(int recording)? scoreOf;
  var _resets = 0;
  final _inner = FakeWakeFeatureExtractor(centerId: wakeCenterId);

  int get _n => (_resets - 1) ~/ 2;

  @override
  String get featureVersion => 'fake-1';
  @override
  Float32List? get embeddingMean => null;
  @override
  String? get centerId => wakeCenterId;
  @override
  Future<void> open() => _inner.open();
  @override
  Future<void> close() => _inner.close();
  @override
  void reset() {
    _resets++;
    _inner.reset();
  }

  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    final n = _n < 0 ? 0 : _n;
    return [
      for (final w in await _inner.accept(frame))
        WakeWindow(
          endSample: w.endSample,
          embedding: Float32List.fromList(
            vectorOf?.call(n) ?? [1, 0.01 * (n % 7), 0.5, 0],
          ),
          modelScore: scoreOf?.call(n),
        ),
    ];
  }
}

WakeEnroller make(
  List<List<Int16List>> clips, {
  WakeFeatureExtractor? features,
  WakeEnrollVerifier? verifier,
  int target = 3,
  Duration checkTimeout = wakeEnrollCheckTimeout,
}) => WakeEnroller(
  // No endless loop on the first clip: a missing recording ends the run.
  audio: SequenceAudio(clips, loop: false),
  checkTimeout: checkTimeout,
  features: features ?? fakeFeatures(),
  store: FakeWakeTemplateStore(),
  speakerId: 'a',
  target: target,
  minimum: 1,
  pause: Duration.zero,
  verifier: verifier,
);

Transcript said(String t) => Transcript(text: t);

void main() {
  group('Störgeräusche (synthetische Fixtures) beim Einlernen', () {
    test('Klick und Klopfen sind schon für die Aufnahme zu kurz', () {
      for (final kind in [Noise.click, Noise.knock, Noise.silence]) {
        final c = UtteranceCapture();
        Utterance? r;
        for (final f in clip(kind)) {
          r = c.feed(f) ?? r;
        }
        expect(r?.verdict, isNot(UtteranceVerdict.accepted), reason: '$kind');
      }
    });

    test('Husten, Rauschen und ein anderes Wort kommen durch die Aufnahme, '
        'aber nicht durch die Inhaltsprüfung', () async {
      // Was die Aufnahme annimmt, sieht der Erkenner: kein „Wendelin“.
      final stt = FakeSpeechToText([
        said(''),
        said('[Husten]'),
        said('Hallo zusammen'),
        said('Hey Wendelin'),
        said('Hey Wendelin.'),
        said('äh Wendlin'),
      ]);
      final e = make([
        clip(Noise.cough),
        clip(Noise.steadyNoise),
        clip(Noise.anotherWord),
        recording(),
        recording(),
        recording(),
      ], verifier: TranscriptWakeVerifier(stt));
      final verdicts = <UtteranceVerdict?>[];
      e.addListener(() => verdicts.add(e.lastVerdict));
      await e.run();
      expect(e.accepted, 3);
      expect(e.rejected, 3, reason: 'sichtbare Ablehnungszahl');
      expect(verdicts, contains(UtteranceVerdict.notWord));
      expect(stt.calls, hasLength(6));
    });

    test('Ein anderes Wort, das nur ähnlich klingt, wird nicht angenommen', () {
      for (final text in ['Wendel in den Keller', 'Wanderweg', 'Wandern']) {
        expect(matchesWakeWord(text), isFalse, reason: text);
      }
      for (final text in ['Wendelin', 'Hey Wendelin', 'Wendlin', 'Wende Lin']) {
        expect(matchesWakeWord(text), isTrue, reason: text);
      }
    });
  });

  group('Beweis: nur der Erkenner mit „Hey“', () {
    test('„Wendelin“ ohne „Hey“: eigenes Verdikt, nicht angenommen', () async {
      final e = make(
        [recording(), recording()],
        verifier: TranscriptWakeVerifier(
          FakeSpeechToText([said('Wendelin.'), said('Hey Wendelin')]),
        ),
        target: 1,
      );
      final verdicts = <UtteranceVerdict?>[];
      e.addListener(() => verdicts.add(e.lastVerdict));
      await e.run();
      expect(verdicts, contains(UtteranceVerdict.missingHey));
      expect(e.rejected, 1);
      expect(e.accepted, 1);
    });

    test('anderes Wort oder Geräusch: notWord', () async {
      final e = make(
        [recording(), recording()],
        verifier: TranscriptWakeVerifier(
          FakeSpeechToText([said('Hey Octavia'), said('Hey Wendelin')]),
        ),
        target: 1,
      );
      final verdicts = <UtteranceVerdict?>[];
      e.addListener(() => verdicts.add(e.lastVerdict));
      await e.run();
      expect(verdicts, contains(UtteranceVerdict.notWord));
      expect(verdicts, isNot(contains(UtteranceVerdict.missingHey)));
    });

    test(
      'Klassifikator sicher, Erkenner hört etwas anderes: angenommen',
      () async {
        final v = FakeWakeVerifier(answer: (_) => false);
        final e = make(
          [recording()],
          features: _Chain(scoreOf: (_) => 0.99),
          verifier: v,
          target: 1,
        );
        await e.run();
        expect(e.accepted, 1);
        expect(v.calls, hasLength(1), reason: 'Erkenner wird immer gefragt');
      },
    );

    test(
      'Klassifikator sicher plus klares „Wendelin“ allein: missingHey',
      () async {
        final e = make(
          [recording(), recording()],
          features: _Chain(scoreOf: (_) => 1.0),
          verifier: TranscriptWakeVerifier(
            FakeSpeechToText([said('Wendelin'), said('Hey Wendelin')]),
          ),
          target: 1,
        );
        final verdicts = <UtteranceVerdict?>[];
        e.addListener(() => verdicts.add(e.lastVerdict));
        await e.run();
        expect(verdicts, contains(UtteranceVerdict.missingHey));
        expect(e.rejected, 1);
        expect(e.accepted, 1);
      },
    );

    test('Grenze: 0,98 nimmt an, 0,97 lehnt ab', () async {
      Future<int> acceptedAt(double score) async {
        final e = make(
          [recording()],
          features: _Chain(scoreOf: (_) => score),
          verifier: FakeWakeVerifier(answer: (_) => false),
          target: 1,
        );
        await e.run();
        return e.accepted;
      }

      expect(WakeEnrollRules.classifierMinScore, 0.98);
      expect(await acceptedAt(0.98), 1);
      expect(await acceptedAt(0.97), 0);
    });

    test('Klassifikator sicher, Erkenner fällt aus: angenommen', () async {
      final v = FakeWakeVerifier()..error = StateError('Modell weg');
      final e = make(
        [recording()],
        features: _Chain(scoreOf: (_) => 1.0),
        verifier: v,
        target: 1,
      );
      await e.run();
      expect(e.accepted, 1);
    });

    test(
      'Klassifikator allein ohne Erkenner nimmt an, unsicher nicht',
      () async {
        final sure = make(
          [recording()],
          features: _Chain(scoreOf: (_) => 1.0),
          target: 1,
        );
        await sure.run();
        expect(sure.accepted, 1);
        final unsure = make(
          [recording(), recording()],
          features: _Chain(scoreOf: (_) => 0.5),
          target: 1,
        );
        final verdicts = <UtteranceVerdict?>[];
        unsure.addListener(() => verdicts.add(unsure.lastVerdict));
        await unsure.run();
        expect(unsure.accepted, 0);
        expect(verdicts, contains(UtteranceVerdict.notWord));
      },
    );

    test('weder Erkenner noch Klassifikator: nichts wird angenommen, '
        'klarer Hinweis statt stiller Dauerablehnung', () async {
      final e = make([recording(), recording()], target: 1);
      await e.run();
      expect(e.accepted, 0);
      expect(e.error, isA<EnrollCheckUnavailable>());
      expect(e.phase, EnrollPhase.cancelled);
      expect(e.lastVerdict, UtteranceVerdict.unchecked);
    });

    test('Erkenner wirft immer: nach drei Versuchen Hinweis, nie '
        'angenommen', () async {
      final v = FakeWakeVerifier()..error = StateError('Modell weg');
      final e = make([recording(), recording(), recording()], verifier: v);
      await e.run();
      expect(e.accepted, 0);
      expect(e.rejected, wakeEnrollMaxUnchecked);
      expect(e.error, isA<EnrollCheckUnavailable>());
    });

    test('Erkenner wirft einmal: weiter, danach angenommen', () async {
      final v = FakeWakeVerifier(
        answer: (n) => n == 1 ? throw StateError('lädt') : true,
      );
      final e = make([recording(), recording()], verifier: v, target: 1);
      await e.run();
      expect(e.error, isNull);
      expect(e.accepted, 1);
      expect(e.rejected, 1);
    });

    test('Erkenner lädt noch: die Prüfung wartet und nimmt dann an', () async {
      final loaded = Completer<void>();
      final v = FakeWakeVerifier()..gate = loaded;
      final e = make([recording()], verifier: v, target: 1);
      final run = e.run();
      await pumpEventQueue();
      expect(e.accepted, 0);
      expect(e.rejected, 0, reason: 'noch nicht abgelehnt, nur gewartet');
      loaded.complete();
      await run;
      expect(e.accepted, 1);
      expect(e.rejected, 0);
    });

    test('Erkenner lädt nie fertig: Zeitlimit, dann Hinweis', () async {
      final e = make(
        [recording(), recording(), recording()],
        verifier: FakeWakeVerifier()..gate = Completer<void>(),
        checkTimeout: const Duration(milliseconds: 5),
      );
      await e.run();
      expect(e.accepted, 0);
      expect(e.error, isA<EnrollCheckUnavailable>());
    });

    test('Rechenzeit je Prüfung wird ohne Text geloggt', () async {
      final lines = <String>[];
      final old = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = old);
      final e = make(
        [recording()],
        verifier: TranscriptWakeVerifier(
          FakeSpeechToText([said('Geheimes Wendelin Wort')]),
        ),
        target: 1,
      );
      await e.run();
      final line = lines.firstWhere((l) => l.contains('enroll-check '));
      expect(line, contains('source=stt'));
      expect(line, matches(RegExp(r'ms=\d+')));
      expect(line, isNot(contains('Geheimes')));
    });
  });

  group('Mindestpegel nur beim Wake-Einlernen (WP142)', () {
    test('Standardaufnahme nimmt 0,012 an, die Utterance-Vorgabe nicht', () {
      // Spitze (RMS eines 20-ms-Blocks) etwa 0,012: zwischen 0,008 und 0,02.
      final quiet = recording(amplitude: 400);
      Utterance? run(UtteranceCapture c) {
        Utterance? r;
        for (final f in quiet) {
          r = c.feed(f) ?? r;
        }
        return r;
      }

      expect(wakeEnrollMinPeak, 0.008);
      expect(UtteranceCapture().minPeak, 0.02);
      expect(run(UtteranceCapture())?.verdict, UtteranceVerdict.tooQuiet);
      expect(
        run(UtteranceCapture(minPeak: wakeEnrollMinPeak))?.verdict,
        UtteranceVerdict.accepted,
      );
    });

    test('der Einlerner nutzt 0,008, die Sprecher-Aufnahme 0,02', () async {
      final e = make(
        [recording(amplitude: 400)],
        verifier: FakeWakeVerifier(),
        target: 1,
      );
      await e.run();
      expect(e.accepted, 1, reason: 'leise, aber über 0,008');
      expect(newSentenceCapture().minPeak, 0.02);
    });
  });

  group('Tipp nach zwei „zu leise“ in Folge (WP142)', () {
    Future<List<bool>> tips(List<List<Int16List>> clips) async {
      final e = make(clips, verifier: FakeWakeVerifier(), target: 1);
      final seen = <bool>[];
      e.addListener(() => seen.add(e.showQuietTip));
      await e.run();
      return seen;
    }

    test('erst die zweite leise Aufnahme in Folge zeigt den Tipp', () async {
      final quiet = recording(amplitude: 200);
      expect(await tips([quiet, recording()]), isNot(contains(true)));
      expect(await tips([quiet, quiet, recording()]), contains(true));
    });

    test('eine andere Ablehnung dazwischen setzt zurück', () async {
      final quiet = recording(amplitude: 200);
      final early = recording(lead: 0);
      expect(
        await tips([quiet, early, quiet, recording()]),
        isNot(contains(true)),
      );
    });

    test('eine Annahme setzt zurück, der Tipp verschwindet', () async {
      final quiet = recording(amplitude: 200);
      final e = make(
        [quiet, quiet, recording(), recording()],
        verifier: FakeWakeVerifier(),
        target: 2,
      );
      final seen = <bool>[];
      e.addListener(() => seen.add(e.showQuietTip));
      await e.run();
      expect(seen, contains(true));
      expect(e.showQuietTip, isFalse);
    });
  });

  group('Konsistenz im zentrierten Raum', () {
    // Zwei Gruppen von Richtungen: „Wendelin“ liegt eng beieinander.
    List<double> good(int n) => [1, 0.02 * (n % 5), 0.3, 0.1 * (n % 3)];
    final mean = Float32List(4);

    test('ein Ausreißer unter acht passenden wird erkannt', () {
      final all = [
        for (var n = 0; n < 8; n++) Float32List.fromList(good(n)),
        Float32List.fromList([-1, 0.5, -0.4, 0.9]),
      ];
      expect(outlierIndices(all, mean), [8]);
    });

    test('gleichmäßig gestreute Vorlagen bleiben alle', () {
      final all = [for (var n = 0; n < 9; n++) Float32List.fromList(good(n))];
      expect(outlierIndices(all, mean), isEmpty);
    });

    test('zu wenige Vorlagen: kein Urteil', () {
      final all = [
        for (var n = 0; n < 3; n++) Float32List.fromList(good(n)),
        Float32List.fromList([-1, 0.5, -0.4, 0.9]),
      ];
      expect(outlierIndices(all, mean), isEmpty);
    });

    test('höchstens ein Viertel wird je Durchgang entfernt', () {
      final all = [
        for (var n = 0; n < 6; n++) Float32List.fromList(good(n)),
        for (var n = 0; n < 4; n++)
          Float32List.fromList([-1, 0.5 + n * 0.01, -0.4, 0.9]),
      ];
      final r = pruneOutliers(all, mean);
      expect(r.removed, lessThanOrEqualTo(2));
      expect(r.kept.length + r.removed, 10);
    });

    test(
      'Einlernen: der unpassende Ausreißer wird entfernt und gezählt',
      () async {
        // Aufnahme 5 (0-basiert) ist anders als alle, aber „Wendelin“ gehört.
        final e = make(
          [for (var i = 0; i < 7; i++) recording()],
          features: _Chain(
            vectorOf: (n) => n == 5 ? [-1, 0.5, -0.4, 0.9] : good(n),
          ),
          verifier: FakeWakeVerifier(),
          target: 6,
        );
        final verdicts = <UtteranceVerdict?>[];
        e.addListener(() => verdicts.add(e.lastVerdict));
        await e.run();
        expect(
          e.accepted,
          6,
          reason: 'Ausreißer entfernt, weiter bis zum Ziel',
        );
        expect(e.rejected, 1);
        expect(verdicts, contains(UtteranceVerdict.inconsistent));
      },
    );
  });
}
