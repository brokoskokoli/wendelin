import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/utterance_capture.dart';
import 'package:wendelin/voice/wake/wake_enroller.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/wake_support.dart';

WakeEnroller enroller(
  SequenceAudio audio,
  WakeTemplateStore store, {
  int target = 3,
  int minimum = 2,
  WakeFeatureExtractor? features,
  WakeEnrollVerifier? verifier,
}) => WakeEnroller(
  audio: audio,
  features: features ?? fakeFeatures(),
  store: store,
  speakerId: 'a',
  target: target,
  minimum: minimum,
  pause: Duration.zero,
  verifier: verifier ?? FakeWakeVerifier(),
);

void main() {
  test('drei gültige Aufnahmen: Fortschritt, Abschluss, Speichern', () async {
    final store = FakeWakeTemplateStore();
    final audio = SequenceAudio([recording(), recording(), recording()]);
    final e = enroller(audio, store);
    final progress = <int>[];
    e.addListener(() => progress.add(e.accepted));
    await e.run();
    expect(e.phase, EnrollPhase.complete);
    expect(e.accepted, 3);
    expect(progress, containsAllInOrder([1, 2, 3]));
    expect(audio.stops, 3, reason: 'Mikrofon nach jeder Aufnahme frei');
    expect(await store.load('a'), isNull, reason: 'erst finish speichert');

    final t = await e.finish();
    expect(e.phase, EnrollPhase.saved);
    expect(t.embeddings, hasLength(3));
    expect(t.featureVersion, 'fake-1');
    expect(t.threshold, wakeProvisionalThreshold);
    expect(t.threshold, 0.58); // vorläufig, bis kalibriert wird (WP44, WP134)
    expect((await store.load('a'))!.embeddings, hasLength(3));
  });

  test(
    'Folgen für den Prüfer B werden je Aufnahme gespeichert (WP143)',
    () async {
      final store = FakeWakeTemplateStore();
      final features = fakeFeatures()
        ..sequenceFor = (clip) =>
            Float32List(3 * 96)..[0] = clip.length.toDouble();
      final e = enroller(
        SequenceAudio([recording(), recording()]),
        store,
        target: 2,
        features: features,
      );
      await e.run();
      final t = await e.finish();
      expect(t.sequences, hasLength(2));
      expect(t.sequences.first.word, WakeTemplates.wordHw);
      expect(t.sequences.first.frames, 3);
      // Zuschnitt: 900 ms Sprache, -0,12 s / +0,20 s, ohne Trim.
      expect(
        features.sequenceCalls.first.length,
        inInclusiveRange(16000, 16 * 1300),
      );
      final back = (await store.load('a'))!;
      expect(back.sequences, hasLength(2));
    },
  );

  test(
    'ohne Folge (Zuschnitt zu kurz) bleibt die Vorlage ohne Prüfer B',
    () async {
      final e = enroller(
        SequenceAudio([recording(), recording()]),
        FakeWakeTemplateStore(),
        target: 2,
      ); // fakeFeatures liefert keine Folge
      await e.run();
      final t = await e.finish();
      expect(t.embeddings, hasLength(2));
      expect(t.hasSequences, isFalse);
      expect(e.sequencesDropped, 2, reason: 'gemeldet, nicht still');
    },
  );

  test('Wort über 2,2 s Zuschnitt: keine Folge, gemeldet (WP143)', () async {
    final features = fakeFeatures()
      ..sequenceFor = (clip) => Float32List(3 * 96);
    final e = enroller(
      SequenceAudio([recording(speech: 1950), recording()]),
      FakeWakeTemplateStore(),
      target: 2,
      features: features,
    );
    await e.run();
    final t = await e.finish();
    expect(t.embeddings, hasLength(2));
    expect(t.sequences, hasLength(1));
    expect(e.sequencesDropped, 1);
  });

  test('Folge entsteht aus dem Kontext: kurzes Wort wird aufgefüllt', () async {
    final features = fakeFeatures()
      ..sequenceFor = (clip) => Float32List(3 * 96);
    final e = enroller(
      SequenceAudio([recording(speech: 300), recording(speech: 300)]),
      FakeWakeTemplateStore(),
      target: 2,
      features: features,
    );
    await e.run();
    await e.finish();
    // 300 ms Sprache: Zuschnitt 0,62 s, aufgefüllt auf 1,0 s echtes Audio.
    expect(features.sequenceCalls.map((c) => c.length), [16000, 16000]);
    expect(e.sequencesDropped, 0);
  });

  test('ungültige Aufnahmen werden verworfen und gezählt', () async {
    final audio = SequenceAudio([
      recording(amplitude: 200), // zu leise
      recording(lead: 0), // abgeschnitten
      recording(speech: 4000), // zu lang
      recording(), // gut
    ]);
    final e = enroller(audio, FakeWakeTemplateStore(), target: 1, minimum: 1);
    final verdicts = <UtteranceVerdict?>[];
    e.addListener(() => verdicts.add(e.lastVerdict));
    await e.run();
    expect(e.accepted, 1);
    expect(e.rejected, 3);
    expect(
      verdicts.toSet(),
      containsAll([
        UtteranceVerdict.tooQuiet,
        UtteranceVerdict.cutOff,
        UtteranceVerdict.tooLong,
        UtteranceVerdict.accepted,
      ]),
    );
    expect(audio.starts, 4);
  });

  test('Abbruch: nichts wird gespeichert, Modelle freigegeben', () async {
    final store = FakeWakeTemplateStore();
    final features = fakeFeatures();
    final audio = SequenceAudio([recording(), recording(), recording()]);
    final e = enroller(audio, store, target: 15, features: features);
    e.addListener(() {
      if (e.accepted == 1) e.cancel();
    });
    await e.run();
    expect(e.phase, EnrollPhase.cancelled);
    expect(e.accepted, 1);
    expect(e.canFinish, isFalse);
    expect(() => e.finish(), throwsStateError);
    expect(await store.load('a'), isNull);
    expect(features.isOpen, isFalse);
  });

  test('zu wenige Aufnahmen: finish lehnt ab, ab dem Minimum nicht', () async {
    final audio = SequenceAudio([recording(), recording()]);
    final e = enroller(audio, FakeWakeTemplateStore(), target: 5, minimum: 2);
    e.addListener(() {
      if (e.accepted == 2) e.cancel();
    });
    await e.run();
    expect(e.canFinish, isTrue);
    expect((await e.finish()).embeddings, hasLength(2));
  });

  test('Mikrofonfehler beenden das Einlernen mit Grund', () async {
    final e = WakeEnroller(
      audio: FakeAudioInput(startError: StateError('Mikrofon weg')),
      features: fakeFeatures(),
      store: FakeWakeTemplateStore(),
      speakerId: 'a',
      verifier: FakeWakeVerifier(),
    );
    await e.run();
    expect(e.phase, EnrollPhase.cancelled);
    expect(e.error, isA<StateError>());
  });

  test('Mikrofon endet mitten drin: abgebrochen mit Grund', () async {
    final audio = SequenceAudio([recording(), <Int16List>[]]);
    final e = enroller(audio, FakeWakeTemplateStore(), target: 3);
    await e.run();
    expect(e.phase, EnrollPhase.cancelled);
    expect(e.error, isA<MicrophoneEnded>());
    expect(e.accepted, 1);
  });

  test('Neu einlernen ersetzt die Vorlagen des Sprechers', () async {
    final store = FakeWakeTemplateStore();
    await enrollTwice(store, 'alt');
    final t = (await store.load('a'))!;
    expect(t.embeddings, hasLength(3));
  });

  group('Datenschutz: kein Rohaudio', () {
    test(
      'gespeichert werden nur Embeddings (Kennzeichen-Sample fehlt)',
      () async {
        final secrets = InMemorySecretStore();
        final store = SecretWakeTemplateStore(secrets);
        const marker = 12345;
        final audio = SequenceAudio([
          recording(amplitude: marker),
          recording(amplitude: marker),
        ]);
        final opened = <String>[];
        await IOOverrides.runZoned(
          () async {
            final e = enroller(audio, store, target: 2);
            await e.run();
            await e.finish();
          },
          createFile: (path) {
            opened.add(path);
            return File(path);
          },
        );

        final raw = await secrets.read('wake.templates.a');
        final json = jsonDecode(raw!) as Map<String, Object?>;
        expect(json.keys, {
          'speakerId',
          'featureVersion',
          'center',
          'threshold',
          'embeddings',
        });
        final emb = json['embeddings']! as List<Object?>;
        expect(emb, hasLength(2));
        // Jede Vorlage ist genau ein Embedding (4 Floats im Fake), kein Audio.
        for (final b in emb) {
          expect(base64Decode(b! as String), hasLength(16));
        }
        final audioBytes = Int16List.fromList(List.filled(64, marker)).buffer
            .asUint8List();
        expect(
          base64Decode(emb.first! as String).toString(),
          isNot(contains(audioBytes.toString())),
        );
        expect(await secrets.listKeys(), {'wake.templates.a'});
        expect(opened, isEmpty, reason: 'keine Datei angelegt');
      },
    );

    test(
      'embedUtterance verwirft das Audio: nur das Fenster kommt zurück',
      () async {
        final f = fakeFeatures();
        final emb = await embedUtterance(f, Int16List(16000), 12000);
        expect(emb, isA<Float32List>());
        expect(emb!.length, 4);
      },
    );
  });

  test('embedUtterance wählt das Fenster 0,3 s nach dem Wortende', () async {
    final chosen = <int>[];
    final f = FakeWakeFeatureExtractor(
      windowFor: (end, _) {
        chosen.add(end);
        return WakeWindow(
          endSample: end,
          embedding: Float32List.fromList([end.toDouble()]),
        );
      },
    );
    // 16 000 Lead + Wortende 8 000 + 4 800 = 28 800 Sample.
    final e = await embedUtterance(f, Int16List(10000), 8000);
    expect(e!.single, closeTo(16000 + 8000 + 4800, 1280));
    expect(chosen.length, greaterThan(5));
  });

  group('Rauschpolster statt digitaler Nullen (WP134)', () {
    Int16List word() => Int16List.fromList([
      for (var i = 0; i < 8000; i++)
        i < 3200 ? ((i * 37) % 81) - 40 : ((i * 91) % 20001) - 10000,
    ]);

    double rms(Int16List x, int a, int b) {
      var s = 0.0;
      for (var i = a; i < b; i++) {
        s += x[i] * x[i];
      }
      return math.sqrt(s / (b - a));
    }

    test(
      'Polster hat den Pegel des Vorlaufs, ist nicht null und deterministisch',
      () {
        final pcm = word();
        final p = padWithNoise(pcm, 16000, 32000);
        expect(p.length, 16000 + 8000 + 32000);
        expect(p.sublist(16000, 24000), pcm, reason: 'Aufnahme unverändert');
        final lead = rms(pcm, 0, 3200);
        for (final (a, b) in [(0, 16000), (24000, 56000)]) {
          expect(rms(p, a, b), closeTo(lead, lead * 0.1));
          expect(
            p.sublist(a, b).where((x) => x == 0).length,
            lessThan((b - a) ~/ 10),
          );
        }
        expect(padWithNoise(pcm, 16000, 32000), p);
      },
    );

    test('digitale Stille als Vorlauf: Polster nie digital null', () {
      final p = padWithNoise(Int16List(8000), 16000, 32000);
      expect(p.sublist(0, 16000).any((x) => x != 0), isTrue);
      expect(rms(p, 0, 16000), closeTo(1, 0.2));
      expect(padWithNoise(Int16List(0), 100, 100).length, 200);
    });

    test('embedUtterance speist das Rauschpolster in die Kette', () async {
      var zeros = 0, total = 0;
      final f = FakeWakeFeatureExtractor(
        windowFor: (end, frame) {
          total += frame.length;
          zeros += frame.where((x) => x == 0).length;
          return WakeWindow(endSample: end, embedding: Float32List(1));
        },
      );
      await embedUtterance(f, word(), 8000);
      expect(zeros / total, lessThan(0.1), reason: 'sonst digitale Nullen');
    });

    test('Vorlagen tragen die Mittel-Kennung der Kette', () async {
      final store = FakeWakeTemplateStore();
      final e = enroller(
        SequenceAudio([recording(), recording(), recording()]),
        store,
      );
      await e.run();
      await e.finish();
      expect((await store.load('a'))!.center, wakeCenterId);
    });
  });
}

Future<void> enrollTwice(WakeTemplateStore store, String _) async {
  for (final n in [2, 3]) {
    final audio = SequenceAudio([for (var i = 0; i < n; i++) recording()]);
    final e = enroller(audio, store, target: n, minimum: n);
    await e.run();
    await e.finish();
  }
}
