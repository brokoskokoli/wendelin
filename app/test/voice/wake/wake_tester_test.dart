import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/wake_tester.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/wake_support.dart';

Float32List v(List<double> x) => Float32List.fromList(x);

WakeTemplates tmpl({double threshold = 0.9, String id = 'a'}) => WakeTemplates(
  speakerId: id,
  featureVersion: 'fake-1',
  center: wakeCenterId,
  threshold: threshold,
  embeddings: [
    v([1, 0, 0, 0]),
  ],
);

/// One-second frames; the audio ends after [seconds].
List<Int16List> frames(int seconds) => [
  for (var i = 0; i < seconds * 10; i++) Int16List(1600),
];

Future<WakeTester> run(WakeTester t) async {
  await t.run();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return t;
}

void main() {
  test('Kandidat über der Schwelle, Nachprüfung getrennt: bestätigt', () async {
    final verifier = FakeWakeVerifier();
    // Ein Treffer bei Fenster 30 (Ende 38 400).
    final features = fakeFeatures(
      vector: (end) => end == 38400 ? v([1, 0, 0, 0]) : v([0, 1, 0, 0]),
    );
    final t = WakeTester(
      audio: FakeAudioInput(frames: frames(8), closeAfterFrames: true),
      features: features,
      speakers: [tmpl()],
      verifier: verifier,
    );
    await run(t);
    expect(t.events, hasLength(1));
    expect(t.events.single.similarity, closeTo(1, 1e-6));
    expect(t.events.single.speakerId, 'a');
    expect(t.events.single.confirmation, WakeConfirmation.confirmed);
    // 2 s davor plus 0,9 s danach.
    expect(verifier.calls.single.length, 32000 + 14400);
  });

  test('Kandidat, aber Whisper bestätigt nicht: getrennt sichtbar', () async {
    final t = WakeTester(
      audio: FakeAudioInput(frames: frames(8), closeAfterFrames: true),
      features: fakeFeatures(vector: (end) => v([1, 0, 0, 0])),
      speakers: [tmpl()],
      verifier: FakeWakeVerifier(answer: (_) => false),
    );
    await run(t);
    expect(t.events.first.confirmation, WakeConfirmation.rejected);
  });

  test('Sperrzeit: ein Treffer je 1,5 s, nicht je Fenster', () async {
    final t = WakeTester(
      audio: FakeAudioInput(frames: frames(8), closeAfterFrames: true),
      features: fakeFeatures(vector: (end) => v([1, 0, 0, 0])),
      speakers: [tmpl()],
    );
    await run(t);
    // Ab Sekunde 0: Treffer bei 1,28 s, 2,8 s, 4,3 s … nicht 6 pro Sekunde.
    expect(t.events.length, lessThanOrEqualTo(6));
    expect(t.events.length, greaterThan(2));
    expect(t.events.map((e) => e.confirmation).toSet(), {
      WakeConfirmation.unavailable,
    }, reason: 'ohne Prüfer: nicht möglich statt still bestätigt');
  });

  test(
    'unter der Schwelle: kein Kandidat, höchste Ähnlichkeit sichtbar',
    () async {
      final t = WakeTester(
        audio: FakeAudioInput(frames: frames(4), closeAfterFrames: true),
        features: fakeFeatures(vector: (end) => v([0.8, 0.6, 0, 0])),
        speakers: [tmpl()],
        verifier: FakeWakeVerifier(),
      );
      await run(t);
      expect(t.events, isEmpty);
      expect(t.maxSimilarity, closeTo(0.8, 1e-6));
    },
  );

  test('mehrere Sprecher: jeder mit eigener Schwelle', () async {
    final t = WakeTester(
      audio: FakeAudioInput(frames: frames(4), closeAfterFrames: true),
      features: fakeFeatures(vector: (end) => v([0.95, 0.31, 0, 0])),
      speakers: [
        tmpl(id: 'streng', threshold: 0.99),
        tmpl(id: 'locker', threshold: 0.9),
      ],
    );
    await run(t);
    expect(t.events.map((e) => e.speakerId).toSet(), {'locker'});
  });

  test('Fehler im Prüfer: nicht möglich, Test läuft weiter', () async {
    final t = WakeTester(
      audio: FakeAudioInput(frames: frames(8), closeAfterFrames: true),
      features: fakeFeatures(vector: (end) => v([1, 0, 0, 0])),
      speakers: [tmpl()],
      verifier: FakeWakeVerifier()..error = StateError('Whisper weg'),
    );
    await run(t);
    expect(t.events.first.confirmation, WakeConfirmation.unavailable);
  });

  test('stop beendet das Zuhören und gibt das Mikrofon frei', () async {
    final audio = FakeAudioInput(
      frames: frames(60),
      frameInterval: const Duration(milliseconds: 1),
    );
    final t = WakeTester(
      audio: audio,
      features: fakeFeatures(),
      speakers: [tmpl()],
    );
    final done = t.run();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(t.running, isTrue);
    await t.stop();
    await done;
    expect(t.running, isFalse);
    expect(audio.isRunning, isFalse);
  });
}
