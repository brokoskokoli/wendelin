import 'dart:convert';
import 'dart:io';
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
}) => WakeEnroller(
  audio: audio,
  features: features ?? fakeFeatures(),
  store: store,
  speakerId: 'a',
  target: target,
  minimum: minimum,
  pause: Duration.zero,
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
    expect(t.threshold, 0.85); // vorläufig, bis kalibriert wird (WP44)
    expect((await store.load('a'))!.embeddings, hasLength(3));
  });

  test('ungültige Aufnahmen werden verworfen und gezählt', () async {
    final audio = SequenceAudio([
      recording(amplitude: 350), // zu leise
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
}

Future<void> enrollTwice(WakeTemplateStore store, String _) async {
  for (final n in [2, 3]) {
    final audio = SequenceAudio([for (var i = 0; i < n; i++) recording()]);
    final e = enroller(audio, store, target: n, minimum: n);
    await e.run();
    await e.finish();
  }
}
