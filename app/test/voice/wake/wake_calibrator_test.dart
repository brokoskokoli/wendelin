import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/wake_calibrator.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/wake_support.dart';

Float32List v(List<double> x) => Float32List.fromList(x);

/// Audio that streams [minutes] of silent 100 ms frames, as fast as the
/// consumer pulls.
final class SilentAudio implements AudioInput {
  SilentAudio(this.minutes);
  final int minutes;
  bool stopped = false;
  @override
  bool get isRunning => !stopped;
  @override
  Stream<Int16List> start() async* {
    stopped = false;
    for (var i = 0; i < minutes * 600 && !stopped; i++) {
      yield Int16List(1600);
    }
  }

  @override
  Future<void> stop() async => stopped = true;
}

WakeTemplates templates() => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.9,
  embeddings: [
    v([1, 0, 0, 0]),
    v([0.98, 0.2, 0, 0]),
    v([0.97, 0, 0.24, 0]),
  ],
);

void main() {
  test(
    'Ergebnis: Schwelle aus Hintergrund und Aufforderungen, gespeichert',
    () async {
      final store = FakeWakeTemplateStore();
      final tones = <int>[];
      var calls = 0;
      // Hintergrund: ab und zu Ähnlichkeit 0.7 (Ereignis), nie darüber.
      // Aufforderungsfenster: Sprecher sagt es (Ähnlichkeit 1.0).
      final features = fakeFeatures(
        vector: (end) =>
            ++calls % 40 == 0 ? v([0.7, 0.7, 0, 0]) : v([0, 0, 1, 0]),
      );
      final audio = SilentAudio(12);
      final cal = WakeCalibrator(
        audio: audio,
        features: features,
        templates: templates(),
        store: store,
        onPrompt: () async => tones.add(1),
        duration: const Duration(minutes: 10),
        firstPrompt: const Duration(minutes: 1),
        promptEvery: const Duration(minutes: 3),
      );
      await cal.run();
      expect(cal.phase, CalibrationPhase.done);
      expect(audio.isRunning, isFalse); // Mikrofon freigegeben
      expect(cal.elapsed.inMinutes, 10);
      expect(tones.length, cal.prompts);
      expect(cal.prompts, 4); // 1, 4, 7, 10 min
      final r = cal.result!;
      expect(r.meetsTarget, isTrue);
      expect(r.falseAlarmsPerHour, lessThanOrEqualTo(1));
      expect(r.threshold, greaterThanOrEqualTo(wakeMinThreshold));
      expect(cal.stored, isTrue);
      expect((await store.load('a'))!.threshold, r.threshold);
    },
  );

  test(
    'Schwelle über 0,95 wird gedeckelt, Rate gilt für die gespeicherte',
    () async {
      final store = FakeWakeTemplateStore();
      var calls = 0;
      // Hintergrund: ein Ereignis mit 0.99 (Schwelle müsste darüber liegen).
      final cal = WakeCalibrator(
        audio: SilentAudio(12),
        features: fakeFeatures(
          vector: (_) => ++calls == 200 ? v([1, 0, 0, 0]) : v([0, 0, 1, 0]),
        ),
        templates: templates(),
        store: store,
        onPrompt: () async {},
        duration: const Duration(minutes: 10),
        firstPrompt: const Duration(hours: 1),
      );
      await cal.run();
      final r = cal.result!;
      expect(r.threshold, lessThanOrEqualTo(calibrationMaxThreshold));
      expect(
        (await store.load('a'))?.threshold ?? 0.9,
        lessThanOrEqualTo(0.95),
      );
    },
  );

  /// Prompts at 1, 4, 7 min: [answer] inside the answer window, else [other].
  Float32List Function(int) answering(Float32List answer, Float32List other) =>
      (end) {
        final sec = end / 16000;
        final into = (sec - 60) % 180;
        return sec >= 60 && into >= 0.6 && into <= 4 ? answer : other;
      };

  test('Antworten auf die Aufforderung sind keine Fehlalarme', () async {
    final store = FakeWakeTemplateStore();
    final cal = WakeCalibrator(
      audio: SilentAudio(12),
      features: fakeFeatures(
        vector: answering(v([1, 0, 0, 0]), v([0, 0, 1, 0])),
      ),
      templates: templates(),
      store: store,
      onPrompt: () async {},
      duration: const Duration(minutes: 10),
    );
    await cal.run();
    expect(cal.answered, cal.prompts - 1); // die letzte kommt zu spät
    expect(cal.result!.falseAlarmsPerHour, 0);
    expect(cal.result!.meetsTarget, isTrue);
    expect(cal.stored, isTrue);
  });

  test('Schwelle folgt den Antworten, nicht den Wiederholungen', () async {
    final cal = WakeCalibrator(
      audio: SilentAudio(12),
      // Antworten mit Ähnlichkeit 0.9; die Einlern-Aufnahmen gleichen
      // einander fast völlig (Leave-one-out nahe 1.0).
      features: fakeFeatures(
        vector: answering(v([0.9, 0, 0, 0.436]), v([0, 0, 1, 0])),
      ),
      templates: templates(),
      store: FakeWakeTemplateStore(),
      onPrompt: () async {},
      duration: const Duration(minutes: 10),
    );
    await cal.run();
    final r = cal.result!;
    expect(r.meetsTarget, isTrue);
    expect(r.threshold, closeTo(0.9, 0.01));
    expect(r.threshold, lessThan(calibrationMaxThreshold));
  });

  test('ruhiger Hintergrund ohne Ereignisse ist verwertbar', () async {
    final store = FakeWakeTemplateStore();
    final cal = WakeCalibrator(
      audio: SilentAudio(12),
      features: fakeFeatures(vector: (_) => v([0, 0, 1, 0])),
      templates: templates(),
      store: store,
      onPrompt: () async {},
      duration: const Duration(minutes: 10),
      firstPrompt: const Duration(hours: 1),
    );
    await cal.run();
    final r = cal.result!;
    expect(r.meetsTarget, isTrue);
    expect(r.falseAlarmsPerHour, 0);
    expect(r.threshold, greaterThanOrEqualTo(wakeMinThreshold));
    expect(cal.stored, isTrue);
  });

  test('Abbruch: keine Änderung, keine Ergebnis', () async {
    final store = FakeWakeTemplateStore();
    final cal = WakeCalibrator(
      audio: SilentAudio(12),
      features: fakeFeatures(),
      templates: templates(),
      store: store,
      onPrompt: () async {},
      duration: const Duration(minutes: 10),
    );
    cal.addListener(() {
      if (cal.elapsed.inMinutes >= 2 &&
          cal.phase == CalibrationPhase.listening) {
        unawaited(cal.cancel());
      }
    });
    await cal.run();
    expect(cal.phase, CalibrationPhase.cancelled);
    expect(cal.result, isNull);
    expect(await store.load('a'), isNull);
  });

  test('früh beenden geht erst nach der Mindestzeit', () async {
    final cal = WakeCalibrator(
      audio: SilentAudio(12),
      features: fakeFeatures(vector: (_) => v([0, 0, 1, 0])),
      templates: templates(),
      store: FakeWakeTemplateStore(),
      onPrompt: () async {},
      duration: const Duration(minutes: 10),
      firstPrompt: const Duration(hours: 1),
    );
    var early = false;
    cal.addListener(() {
      if (cal.elapsed < cal.minimumEarly) {
        cal.finish(); // wirkungslos
      } else if (!early) {
        early = true;
        expect(cal.canFinishEarly, isTrue);
        cal.finish();
      }
    });
    await cal.run();
    expect(cal.phase, CalibrationPhase.done);
    expect(cal.elapsed.inMinutes, inInclusiveRange(5, 6));
  });

  test(
    'Hintergrund nah an der Stimme: nicht verwertbar, nichts gespeichert',
    () async {
      final store = FakeWakeTemplateStore();
      final cal = WakeCalibrator(
        audio: SilentAudio(12),
        // Immer sehr ähnlich: jede 1,5-s-Spanne ist ein Ereignis.
        features: fakeFeatures(vector: (_) => v([1, 0, 0, 0])),
        templates: templates(),
        store: store,
        onPrompt: () async {},
        duration: const Duration(minutes: 10),
        firstPrompt: const Duration(hours: 1),
      );
      await cal.run();
      expect(cal.phase, CalibrationPhase.done);
      expect(cal.result!.meetsTarget, isFalse);
      expect(cal.stored, isFalse);
      expect(await store.load('a'), isNull);
    },
  );

  test('Mikrofonfehler: abgebrochen mit Grund', () async {
    final cal = WakeCalibrator(
      audio: FakeAudioInput(startError: StateError('weg')),
      features: fakeFeatures(),
      templates: templates(),
      store: FakeWakeTemplateStore(),
      onPrompt: () async {},
    );
    await cal.run();
    expect(cal.phase, CalibrationPhase.cancelled);
    expect(cal.error, isA<StateError>());
  });
}
