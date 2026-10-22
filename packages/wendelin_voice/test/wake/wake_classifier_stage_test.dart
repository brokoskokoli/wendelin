// WP129: Stufe-1-Regel des trainierten Klassifikators (Band: verwerfen /
// Stufe 2 / direkt annehmen) und WP126-Folgepunkt (Stille löst „Wendelin“
// nicht aus, weder über Vorlagen noch über den Klassifikator).
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _band = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.995);

Float32List _v(List<double> x) => Float32List.fromList(x);

/// Engine with a classifier whose score is [score] in every window.
CandidateWakeEngine _classifier(
  double score, {
  SpeechGate? mainGate,
  WakeTemplates? templates,
  Float32List? embedding,
}) => CandidateWakeEngine(
  features: FakeWakeFeatureExtractor(
    windowEvery: 100,
    windowFor: (end, _) => WakeWindow(
      endSample: end,
      embedding: embedding ?? _v([0, 1]),
      modelScore: score,
    ),
  ),
  templates: templates,
  modelThreshold: _band.verifyFrom,
  directThreshold: _band.acceptFrom,
  mainGate: mainGate,
);

Int16List _loud(int n) => Int16List(n)..fillRange(0, n, 3000);

Future<List<WakeWordHit>> _run(
  CandidateWakeEngine e, {
  Int16List? frame,
}) async {
  await e.open([KeywordSpec.wendelin]);
  return e.accept(frame ?? _loud(100));
}

/// Quiet room first (the gate learns its floor), then speech.
Future<List<WakeWordHit>> _speech(CandidateWakeEngine e) async {
  await e.open([KeywordSpec.wendelin]);
  await e.accept(Int16List(3200));
  return e.accept(_loud(1600));
}

void main() {
  group('WakeScoreBand', () {
    test('Katalog: Station ist nicht lockerer als das Handy', () {
      expect(
        WakeClassifierRules.station.verifyFrom,
        greaterThanOrEqualTo(WakeClassifierRules.phone.verifyFrom),
      );
      expect(
        SpeechModelCatalog.standard.byId('wake-classifier-wendelin'),
        isNotNull,
      );
    });

    test('Stufe 2: Fenster und Nachlauf kommen aus dem Katalog (WP129)', () {
      expect(WakeClassifierRules.verifyWindow, const Duration(seconds: 2));
      expect(WakeClassifierRules.verifyTail, const Duration(milliseconds: 900));
      final l = WakeWordListener(
        audio: FakeAudioInput(),
        engine: FakeWakeWordEngine(),
      );
      expect(l.verifyWindow, WakeClassifierRules.verifyWindow);
      expect(l.verifyTail, WakeClassifierRules.verifyTail);
    });

    test('Lizenzhinweis: M-AILABS mit Copyright und Haftungsausschluss', () {
      final a = WakeClassifierCatalog.model.attribution!;
      expect(a, contains('Copyright (c) 2017-2019'));
      expect(a, contains('ohne Gewähr'));
      expect(a, contains('haften nicht'));
    });
  });

  group('Stufe 1 mit Klassifikator', () {
    test('unter der unteren Grenze: verworfen', () async {
      expect(await _run(_classifier(0.979)), isEmpty);
    });

    test('untere Grenze genau: Kandidat für Stufe 2, nicht direkt', () async {
      final hits = await _run(_classifier(0.98));
      expect(hits, hasLength(1));
      expect(hits.single.direct, isFalse);
      expect(hits.single.reason, 'model');
      expect(hits.single.score, 0.98);
    });

    test('knapp unter der oberen Grenze: weiter Stufe 2', () async {
      final hits = await _run(_classifier(0.9949));
      expect(hits.single.direct, isFalse);
    });

    test('obere Grenze genau: direkt angenommen', () async {
      final hits = await _run(_classifier(0.995));
      expect(hits.single.direct, isTrue);
    });
  });

  group('Listener', () {
    Future<(int, int)> run({required bool direct}) async {
      final audio = FakeAudioInput();
      final engine = FakeWakeWordEngine(hitAtFrame: {3}, direct: direct);
      final verifier = FakeWakeVerifier();
      final listener = WakeWordListener(
        audio: audio,
        engine: engine,
        verifier: verifier,
        verifyTail: Duration.zero,
      );
      final found = <WakeWordDetection>[];
      listener.detections.listen(found.add);
      await listener.start();
      for (var i = 0; i < 6; i++) {
        audio.push(Int16List(480));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await listener.dispose();
      return (verifier.calls.length, found.length);
    }

    test('Band: Stufe 2 wird gefragt', () async {
      expect(await run(direct: false), (1, 1));
    });

    test('direkt: Stufe 2 wird übersprungen, Treffer zählt', () async {
      expect(await run(direct: true), (0, 1));
    });
  });

  group('WP126: Stille löst „Wendelin“ nicht aus', () {
    final tpl = WakeTemplates(
      speakerId: 's',
      featureVersion: 'fake-1',
      threshold: 0.75,
      embeddings: [
        _v([1, 0]),
      ],
    );
    // Silence embeddings look like the templates (0.82 > 0.75).
    final like = _v([0.82, 0.57]);

    CandidateWakeEngine templated({SpeechGate? gate}) => CandidateWakeEngine(
      features: FakeWakeFeatureExtractor(
        windowEvery: 100,
        windowFor: (end, _) => WakeWindow(endSample: end, embedding: like),
      ),
      templates: tpl,
      modelThreshold: null,
      mainGate: gate,
    );

    test('Vorlagen-Weg: Stille ohne Gate ist (Ausgangsfehler) ein Treffer, '
        'mit Gate nicht', () async {
      expect(await _run(templated(), frame: Int16List(100)), isNotEmpty);
      expect(
        await _run(templated(gate: SpeechGate()), frame: Int16List(100)),
        isEmpty,
      );
    });

    test('Vorlagen-Weg: Sprachpegel löst aus', () async {
      expect(await _speech(templated(gate: SpeechGate())), isNotEmpty);
    });

    test('Klassifikator-Weg: Stille mit hohem Score löst nicht aus', () async {
      final e = _classifier(0.999, mainGate: SpeechGate());
      expect(await _run(e, frame: Int16List(100)), isEmpty);
    });

    test('Klassifikator-Weg: warmUp mit lautem Audio füttert das Gate nicht, '
        'danach Stille löst nicht aus', () async {
      final e = _classifier(0.999, mainGate: SpeechGate());
      await e.open([KeywordSpec.wendelin]);
      // Quiet first (the floor), then loud: would be speech if the gate saw it.
      await e.warmUp(Int16List(3200));
      await e.warmUp(_loud(1600));
      expect(await e.accept(Int16List(100)), isEmpty);
    });

    test('Klassifikator-Weg: Sprachpegel mit hohem Score löst aus', () async {
      final e = _classifier(0.999, mainGate: SpeechGate());
      final hits = await _speech(e);
      expect(hits.single.direct, isTrue);
    });

    test('Stille: das Hauptwort-Gate verhindert auch den Weg über stopOverridesWake', () async {
      final stop = WakeTemplates(
        speakerId: 's',
        featureVersion: 'fake-1',
        threshold: 0.7,
        embeddings: [
          _v([0, 1]),
        ],
      );
      // Window similar to both words, silent stream.
      final both = _v([0.7, 0.72]);
      CandidateWakeEngine make() => CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: both),
        ),
        templates: WakeTemplates(
          speakerId: 's',
          featureVersion: 'fake-1',
          threshold: 0.65,
          embeddings: [
            _v([1, 0]),
          ],
        ),
        stopTemplates: [stop],
        modelThreshold: null,
        stopGate: SpeechGate(),
        mainGate: SpeechGate(),
        stopOverridesWake: true,
      );
      final e = make();
      await e.open([KeywordSpec.wendelin]);
      final silent = await e.accept(Int16List(300));
      expect(silent, isEmpty, reason: 'ohne Pegel weder Stopp noch Wendelin');
    });
  });
}
