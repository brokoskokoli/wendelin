import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  group('keywordsFile', () {
    const two = KeywordSpec(
      id: 'stop',
      variants: ['S T OH1 P', 'SH T OH1 P'],
      thresholds: {
        WakeSensitivity.low: 0.9,
        WakeSensitivity.medium: 0.5,
        WakeSensitivity.high: 0.1,
      },
      boost: 3,
    );

    test('Tabelle Varianten x Stufen im sherpa-Format', () {
      final cases = <(List<KeywordSpec>, WakeSensitivity, String)>[
        (
          [KeywordSpec.wendelin],
          WakeSensitivity.low,
          'W EH1 N D AH0 L IH0 N :2.0 #0.98 @wake\n',
        ),
        (
          [KeywordSpec.wendelin],
          WakeSensitivity.medium,
          'W EH1 N D AH0 L IH0 N :2.0 #0.9 @wake\n',
        ),
        (
          [KeywordSpec.wendelin],
          WakeSensitivity.high,
          'W EH1 N D AH0 L IH0 N :2.0 #0.6 @wake\n',
        ),
        (
          [two],
          WakeSensitivity.low,
          'S T OH1 P :3.0 #0.9 @stop\n'
              'SH T OH1 P :3.0 #0.9 @stop\n',
        ),
        (
          [two],
          WakeSensitivity.high,
          'S T OH1 P :3.0 #0.1 @stop\n'
              'SH T OH1 P :3.0 #0.1 @stop\n',
        ),
        (
          [KeywordSpec.wendelin, two],
          WakeSensitivity.medium,
          'W EH1 N D AH0 L IH0 N :2.0 #0.9 @wake\n'
              'S T OH1 P :3.0 #0.5 @stop\n'
              'SH T OH1 P :3.0 #0.5 @stop\n',
        ),
        ([], WakeSensitivity.medium, ''),
      ];
      for (final (k, level, want) in cases) {
        expect(keywordsFile(k, level), want);
      }
    });
  });

  group('matchesWakeWord', () {
    test('Tabelle', () {
      final cases = <String, bool>{
        'Wendelin': true,
        'wendelin, wie spät ist es': true,
        'Hey Wendelin!': true,
        'Wendeling': true,
        'Vendelin': true,
        'Wende Lin': true,
        'Wendlin': true,
        'WENDELIN?': true,
        'Wendelmann': true,
        'wendemann': true,
        'Wendelen': true,
        'Fendelien': true,
        'Wändelein': true,
        'Fandelin': true,
        'Wendelmann, wie spät': true,
        'Wendel': false,
        'Windel': false,
        'Wendeltreppe': false,
        'Berlin': false,
        'Wenzel': false,
        'Wandelnd': false,
        'Wettelin': false,
        'Handelmann': false,
        '': false,
        'Danke schön': false,
      };
      cases.forEach((text, want) {
        expect(matchesWakeWord(text, maxDistance: 1), want, reason: text);
      });
      expect(matchesWakeWord('Wendel'), isFalse);
    });

    test(
      'Nachprüfung toleriert zwei Änderungen nur bei Einzelwörtern (WP73)',
      () {
        const cases = {
          // Echte Varianten.
          'Wendelin': true,
          'Wendolin': true,
          'Wändelin': true,
          'Vendelin': true,
          // Nur mit zwei Änderungen (nicht phonetisch gleich): Einzelwort ≥ 7.
          'Wengelion': true,
          'Hey Wengelion': true,
          // Satzfetzen und ähnliche Wörter.
          'Weil in': false,
          'Wand in': false,
          'Wenden': false,
          'Wedeln': false,
          'Wendland': false,
          'Wendel': false,
          'Mandelin': false,
          'Welle': false,
          'Wandern': false,
        };
        cases.forEach((text, want) {
          expect(matchesWakeWord(text), want, reason: text);
        });
        // Eine Änderung genügt weiter, zwei nur bei der Nachprüfung.
        expect(matchesWakeWord('Wengelion', maxDistance: 1), isFalse);
        expect(matchesWakeWord('Wendelxyz', maxDistance: 1), isFalse);
      },
    );

    test('Erkennen und Entfernen nutzen dieselbe Toleranz (WP73)', () {
      for (final w in ['Wendelin', 'Wengelion', 'Vendelin', 'Wende Lin']) {
        expect(matchesWakeWord('$w mach Licht'), isTrue, reason: w);
        expect(stripWakeWord('$w, mach Licht'), 'mach Licht', reason: w);
      }
      for (final w in ['Weil in', 'Wand in', 'Wenden', 'Wedeln']) {
        expect(matchesWakeWord('$w den Keller'), isFalse, reason: w);
        expect(stripWakeWord('$w den Keller'), '$w den Keller', reason: w);
      }
    });

    test('Kategorie der Nachprüfung ohne Text (WP73)', () async {
      expect(wakeTranscriptCategory(''), 'empty');
      expect(wakeTranscriptCategory('Hey Wendelin'), 'exact');
      expect(wakeTranscriptCategory('Vendelin'), 'variant');
      expect(wakeTranscriptCategory('Guten Tag'), 'other');
      final seen = <String>[];
      final v = TranscriptWakeVerifier(
        FixedTranscriptStt('Wandeln'),
        onCategory: (c, ms) => seen.add('$c $ms'),
      );
      expect(await v.confirm(Int16List(32000)), isTrue);
      expect(seen, ['variant 2000']);
    });

    test('TranscriptWakeVerifier kürzt auf die letzten 3 s', () async {
      final stt = FixedTranscriptStt('Hey Wendelin');
      final v = TranscriptWakeVerifier(stt);
      expect(await v.confirm(Int16List(100000)), isTrue);
      expect(stt.lastSamples, 48000);
      stt.text = 'Guten Tag';
      expect(await v.confirm(Int16List(1000)), isFalse);
      expect(stt.lastSamples, 1000);
    });
  });

  group('CandidateWakeEngine', () {
    test('onWindow meldet beste Ähnlichkeit je Fenster (WP72)', () async {
      Float32List v(List<double> e) => Float32List.fromList(e);
      WakeTemplates one(List<double> e) => WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.9,
        embeddings: [v(e)],
      );
      final seen = <double>[];
      final e = CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 100,
          windowFor: (end, _) =>
              WakeWindow(endSample: end, embedding: v([1, 0])),
        ),
        templates: one([1, 0]),
        modelThreshold: null,
        onWindow: (m, _) => seen.add(m),
      );
      await e.open([KeywordSpec.wendelin]);
      await e.accept(Int16List(200));
      expect(seen, hasLength(2));
      expect(seen.first, closeTo(1, 1e-6));
    });

    Float32List v(List<double> x) => Float32List.fromList(x);

    CandidateWakeEngine make({
      WakeTemplates? templates,
      double? modelThreshold = 0.5,
      required Map<int, WakeWindow> windows,
    }) {
      final features = FakeWakeFeatureExtractor(
        windowEvery: 100,
        windowFor: (end, _) =>
            windows[end ~/ 100] ??
            WakeWindow(endSample: end, embedding: v([0, 1]), modelScore: 0),
      );
      return CandidateWakeEngine(
        features: features,
        templates: templates,
        modelThreshold: modelThreshold,
        refractory: const Duration(milliseconds: 20), // 320 Samples
      );
    }

    final tpl = WakeTemplates(
      speakerId: 's',
      featureVersion: 'fake-1',
      threshold: 0.9,
      embeddings: [
        v([1, 0]),
      ],
    );

    test('Modell ODER Vorlage, Sperrzeit, Konfidenz und Grund', () async {
      final e = make(
        templates: tpl,
        windows: {
          2: WakeWindow(endSample: 200, embedding: v([0, 1]), modelScore: 0.6),
          3: WakeWindow(endSample: 300, embedding: v([0, 1]), modelScore: 0.7),
          8: WakeWindow(
            endSample: 800,
            embedding: v([1, 0.1]),
            modelScore: 0.1,
          ),
        },
      );
      await e.open([KeywordSpec.wendelin]);
      final hits = [
        for (var i = 0; i < 10; i++) ...await e.accept(Int16List(100)),
      ];
      expect(hits.map((h) => (h.endSample, h.reason)), [
        (200, 'model'), // 300 liegt in der Sperrzeit (320 Samples)
        (800, 'template'),
      ]);
      expect(hits.first.confidence, 0.6);
      expect(e.maxSimilarity, greaterThan(0.99));
      expect(e.maxModelScore, 0.7);
    });

    test('mehrere Sprecher: jede Vorlage mit eigener Schwelle', () async {
      final strict = WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.99,
        embeddings: [
          v([1, 0]),
        ],
      );
      final loose = WakeTemplates(
        speakerId: 'b',
        featureVersion: 'fake-1',
        threshold: 0.5,
        embeddings: [
          v([1, 1]),
        ],
      );
      CandidateWakeEngine twoSpeakers(Float32List embedding) =>
          CandidateWakeEngine(
            features: FakeWakeFeatureExtractor(
              windowEvery: 100,
              windowFor: (end, _) =>
                  WakeWindow(endSample: end, embedding: embedding),
            ),
            templates: strict,
            moreTemplates: [loose],
            modelThreshold: null,
          );
      // [1, 0.3] is below the strict threshold of speaker a but above the
      // loose one of speaker b.
      final e = twoSpeakers(v([1, 0.3]));
      await e.open([KeywordSpec.wendelin]);
      expect(await e.accept(Int16List(100)), hasLength(1));
      // [0, 1] fits nobody.
      final other = twoSpeakers(v([-1, 0]));
      await other.open([KeywordSpec.wendelin]);
      expect(await other.accept(Int16List(100)), isEmpty);
    });

    test('WP134: ein Fenster im Stopp-Muster löst nichts aus', () async {
      // Das Muster [0, 1] gehörte der „Stopp“-Vorlage; es gibt keine mehr.
      // Echo oder andere Sprache (ähnlich keiner Vorlage) bleibt still.
      final wake = WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.9,
        embeddings: [v([1, 0])],
      );
      Future<List<String>> run(List<double> embedding) async {
        final e = CandidateWakeEngine(
          features: FakeWakeFeatureExtractor(
            windowEvery: 100,
            windowFor: (end, _) =>
                WakeWindow(endSample: end, embedding: v(embedding)),
          ),
          templates: wake,
          modelThreshold: null,
        );
        await e.open([KeywordSpec.wendelin]);
        return [for (final h in await e.accept(Int16List(200))) h.keywordId];
      }

      expect(await run([1, 0.05]), ['wake', 'wake']);
      expect(await run([0.05, 1]), isEmpty);
      expect(await run([-1, -1]), isEmpty);
    });

    test('Vorlagen anderer Merkmalsversion werden ignoriert', () async {
      final e = make(
        templates: WakeTemplates(
          speakerId: 's',
          featureVersion: 'alt',
          threshold: 0.1,
          embeddings: [
            v([0, 1]),
          ],
        ),
        modelThreshold: null,
        windows: {},
      );
      await e.open([KeywordSpec.wendelin]);
      expect(await e.accept(Int16List(1000)), isEmpty);
    });

    test('ohne Klassifikator genügt die Vorlage; reset und close', () async {
      final e = make(
        templates: tpl,
        modelThreshold: null,
        windows: {
          1: WakeWindow(endSample: 100, embedding: v([1, 0])),
        },
      );
      await e.open([KeywordSpec.wendelin]);
      expect(await e.accept(Int16List(100)), hasLength(1));
      e.reset();
      expect(await e.accept(Int16List(100)), hasLength(1)); // Sperre gelöscht
      await e.close();
      await e.close();
      await expectLater(
        e.open([
          const KeywordSpec(
            id: 'stop',
            variants: [],
            thresholds: {
              WakeSensitivity.low: 1,
              WakeSensitivity.medium: 1,
              WakeSensitivity.high: 1,
            },
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('Verträge', () {
    wakeWordEngineContract(
      FakeWakeWordEngine.new,
      name: 'FakeWakeWordEngine',
      wakeAudio: () => [Int16List(480), FakeWakeWordEngine.markerFrame()],
      quietAudio: () => [Int16List(480), Int16List(480)],
    );

    wakeWordEngineContract(
      () => CandidateWakeEngine(
        features: FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, f) => WakeWindow(
            endSample: end,
            embedding: Float32List(1),
            modelScore: f.first == FakeWakeWordEngine.marker ? 0.9 : 0,
          ),
        ),
      ),
      name: 'CandidateWakeEngine',
      wakeAudio: () => [Int16List(480), FakeWakeWordEngine.markerFrame()],
      quietAudio: () => [Int16List(480), Int16List(480)],
    );

    bargeInDetectorContract(
      () => WakeWordBargeInDetector(
        audio: FakeAudioInput(),
        engine: FakeWakeWordEngine(),
      ),
      name: 'WakeWordBargeInDetector',
      fire: (d, s) async {
        final det = d as WakeWordBargeInDetector;
        final audio = det.audio as FakeAudioInput;
        if (!audio.isRunning) return;
        audio.push(FakeWakeWordEngine.markerFrame());
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );
  });

  test(
    'WakeWordBargeInDetector: Schlüsselwörter, stop gibt das Mikro frei',
    () async {
      final audio = FakeAudioInput();
      final engine = FakeWakeWordEngine(keywordId: 'stop');
      final d = WakeWordBargeInDetector(audio: audio, engine: engine);
      final got = <String>[];
      d.signals.listen((s) => got.add(s.code));
      await d.start();
      audio.push(FakeWakeWordEngine.markerFrame());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(got, ['keyword-stop']);
      await d.stop();
      expect(
        audio.isRunning,
        isFalse,
      ); // vor dem Rückkehren frei (VOICE_RECOGNITION)
      expect(engine.isOpen, isTrue);
      await d.start();
      expect(engine.resetCount, 2);
      await d.dispose();
      expect(engine.isOpen, isFalse);
      expect(audio.isRunning, isFalse);
    },
  );

  test('FakeWakeTemplateStore: Speichern, Laden, Löschen', () async {
    final s = FakeWakeTemplateStore();
    expect(await s.load('a'), isNull);
    final t = WakeTemplates(
      speakerId: 'a',
      featureVersion: 'v',
      threshold: 0.8,
      embeddings: [Float32List(2)],
    );
    await s.save(t);
    expect(await s.load('a'), same(t));
    await s.delete('a');
    expect(await s.load('a'), isNull);
  });

  group('Katalog wake-features', () {
    const m = SpeechModelCatalog.wakeFeatures;

    test(
      'Eintrag: Art, Lizenz, Attribution, SHA-256, gepinnte Release-URL',
      () {
        expect(SpeechModelCatalog.standard.byId('wake-features'), same(m));
        expect(m.kind, SpeechModelKind.wake);
        expect(m.license, contains('Apache-2.0'));
        expect(m.attribution, contains('openWakeWord'));
        expect(m.files.map((f) => f.name), [
          'melspectrogram.onnx',
          'embedding_model.onnx',
        ]);
        for (final f in m.files) {
          expect(f.url, contains('/openWakeWord/releases/download/v0.5.1/'));
          expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        }
        expect(m.sizeBytes, lessThan(3 * 1024 * 1024));
      },
    );

    test('Download prüft die Summe (FakeModelStore)', () async {
      final bytes = utf8.encode('x' * 300);
      final model = SpeechModel(
        id: 'wake-features',
        kind: SpeechModelKind.wake,
        displayName: 'W',
        languages: const {},
        license: 'Apache-2.0',
        source: 'Test',
        files: [
          for (final n in ['melspectrogram.onnx', 'embedding_model.onnx'])
            ModelFile(
              name: n,
              url: 'https://m.example/$n',
              sizeBytes: bytes.length,
              sha256: sha256.convert(bytes).toString(),
            ),
        ],
      );
      final client = MockClient.streaming(
        (r, _) async => http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length,
        ),
      );
      final store = FakeModelStore();
      final d = ModelDownloader(client: client, store: store);
      expect(await d.isInstalled(model), isFalse);
      await d.download(model);
      expect(await d.isInstalled(model), isTrue);
      expect(store.finalBytes('wake-features', 'embedding_model.onnx'), bytes);

      final bad = MockClient.streaming(
        (r, _) async => http.StreamedResponse(
          Stream.value(utf8.encode('y' * 300)),
          200,
          contentLength: 300,
        ),
      );
      final store2 = FakeModelStore();
      await expectLater(
        ModelDownloader(client: bad, store: store2).download(model),
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.kind,
            'kind',
            DownloadErrorKind.checksum,
          ),
        ),
      );
      expect(
        await ModelDownloader(client: bad, store: store2).isInstalled(model),
        isFalse,
      );
    });
  });

  test('TriggerEvent trägt den Pre-Roll, Gleichheit ignoriert ihn', () {
    final at = DateTime(2026);
    final a = TriggerEvent(
      source: TriggerKind.wakeWord,
      at: at,
      preRoll: Int16List(3),
    );
    expect(a, TriggerEvent(source: TriggerKind.wakeWord, at: at));
    expect(a.preRoll, hasLength(3));
  });
}
