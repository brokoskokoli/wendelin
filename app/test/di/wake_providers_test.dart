import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/voice/dev_audio.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin/voice/wake/wake_template_audit.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

Float32List _tpl(int i, {bool stray = false}) {
  final r = math.Random(i);
  return Float32List.fromList([
    for (var k = 0; k < 1536; k++)
      wakeCenterMean[k] +
          (stray ? (k.isEven ? 1 : -1) : (k % 3 == 0 ? 1 : -0.3)) +
          (r.nextDouble() - 0.5) * 0.2,
  ]);
}

WakeTemplates _set(List<Float32List> e) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'v',
  threshold: 0.5,
  embeddings: e,
  center: wakeCenterId,
);

void main() {
  test(
    'Audit: einmal je Vorlagenstand, zweiter Start entfernt nichts',
    () async {
      final env = TestEnv();
      final store = env.container().read(wakeStoreProvider);
      await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'Anna')]);
      await store.save(
        _set([for (var i = 0; i < 9; i++) _tpl(i), _tpl(100, stray: true)]),
      );
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(wakeSpeakersProvider.future);
      expect((await store.load('a'))!.embeddings, hasLength(9));
      final mark = await env.storage.settings.get(
        SettingKey.string('wake.audit.a'),
      );
      expect(mark, templateFingerprint((await store.load('a'))!));
      // The set is marked as audited: a stray in it now stays at the next
      // start (the audit is relative and would otherwise nibble further).
      final withStray = _set([
        for (var i = 0; i < 9; i++) _tpl(i),
        _tpl(101, stray: true),
      ]);
      await store.save(withStray);
      await env.storage.settings.set(
        SettingKey.string('wake.audit.a'),
        templateFingerprint(withStray),
      );
      final again = env.container();
      addTearDown(again.dispose);
      await again.read(wakeSpeakersProvider.future);
      expect((await store.load('a'))!.embeddings, hasLength(10));
      // A new enrollment (other set) is audited once more.
      await store.save(
        _set([for (var i = 0; i < 9; i++) _tpl(i), _tpl(102, stray: true)]),
      );
      final third = env.container();
      addTearDown(third.dispose);
      await third.read(wakeSpeakersProvider.future);
      expect((await store.load('a'))!.embeddings, hasLength(9));
    },
  );

  test('Stimme löschen entfernt auch den Audit-Marker', () async {
    final env = TestEnv();
    final store = env.container().read(wakeStoreProvider);
    await store.saveSpeakers([
      const WakeSpeaker(id: 'a', name: 'Anna'),
      const WakeSpeaker(id: 'b', name: 'Ben'),
    ]);
    await store.save(_set([for (var i = 0; i < 9; i++) _tpl(i)]));
    final c = env.container();
    addTearDown(c.dispose);
    await c.read(wakeSpeakersProvider.future);
    final keyA = SettingKey.string('wake.audit.a');
    final keyB = SettingKey.string('wake.audit.b');
    expect(await env.storage.settings.get(keyA), isNotNull);
    await env.storage.settings.set(keyB, 'x');
    await c.read(wakeSpeakersProvider.notifier).remove('a');
    expect(await env.storage.settings.get(keyA), isNull);
    expect(await env.storage.settings.get(keyB), isNotNull);
    await c.read(wakeSpeakersProvider.notifier).removeAll();
    expect(await env.storage.settings.get(keyB), isNull);
  });

  test('Nachprüfung ist standardmäßig an und bleibt gespeichert', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    expect(await c.read(wakeVerifyProvider.future), isTrue);
    await c.read(wakeVerifyProvider.notifier).set(enabled: false);
    expect(await env.storage.settings.get(wakeVerifyKey), isFalse);

    final again = env.container();
    addTearDown(again.dispose);
    expect(await again.read(wakeVerifyProvider.future), isFalse);
  });

  test('Sprecher: anlegen, Namen ersetzen, löschen mit Vorlagen', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    final speakers = c.read(wakeSpeakersProvider.notifier);
    expect(await c.read(wakeSpeakersProvider.future), isEmpty);
    await speakers.upsert('a', 'Anna');
    await speakers.upsert('b', '');
    await speakers.upsert('a', 'Anna S.');
    final list = await c.read(wakeSpeakersProvider.future);
    expect([for (final s in list) '${s.id}:${s.name}'], ['b:', 'a:Anna S.']);

    await c
        .read(wakeStoreProvider)
        .save(
          WakeTemplates(
            speakerId: 'a',
            featureVersion: 'v',
            threshold: 0.9,
            embeddings: const [],
          ),
        );
    await speakers.remove('a');
    expect(await c.read(wakeStoreProvider).load('a'), isNull);
    expect((await c.read(wakeSpeakersProvider.future)).single.id, 'b');
    await speakers.removeAll();
    expect(await env.secrets.listKeys(), isEmpty);
  });

  test('Merkmalskette ohne geladene Modelle: Fehler „Modell fehlt“', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    final features = c.read(wakeFeaturesFactoryProvider)();
    await expectLater(
      features.open(),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.modelMissing,
        ),
      ),
    );
  });

  test('Erkennung ist standardmäßig auto und bleibt gespeichert', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    expect(await c.read(wakeDetectorProvider.future), WakeDetectorChoice.auto);
    await c.read(wakeDetectorProvider.notifier).set(WakeDetectorChoice.model);
    expect(await env.storage.settings.get(wakeDetectorKey), 'model');
    final again = env.container();
    addTearDown(again.dispose);
    expect(
      await again.read(wakeDetectorProvider.future),
      WakeDetectorChoice.model,
    );
    expect(WakeDetectorChoice.parse('x'), WakeDetectorChoice.auto);
  });

  test('Klassifikator-Kette ohne Modelle: Fehler „Modell fehlt“', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    final features = c.read(wakeClassifierFeaturesFactoryProvider)();
    await expectLater(
      features.open(),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.modelMissing,
        ),
      ),
    );
  });

  test(
    'Prüfer im Ausprobieren trägt den Namen des Erkenners (WP146)',
    () async {
      for (final (engine, kind) in [
        ('Parakeet (sherpa-onnx)', 'parakeet'),
        ('Whisper (sherpa-onnx)', 'whisper'),
      ]) {
        final env = TestEnv(
          extraOverrides: [
            speechToTextProvider.overrideWith(
              (ref) async => FakeSpeechToText(
                const [],
                SpeechToTextEngineInfo(
                  name: engine,
                  languages: const {'de'},
                  model: 'm',
                ),
              ),
            ),
          ],
        );
        final c = env.container();
        addTearDown(c.dispose);
        expect((await c.read(wakeVerifierProvider.future))!.kind, kind);
      }
    },
  );

  test('Prüfer fehlt ohne Whisper (null statt Absturz)', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    expect(await c.read(wakeVerifierProvider.future), isNull);
  });

  test(
    'Warmstart nimmt das Mikrofon-Ende einmal (take, nicht snapshot)',
    () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      await c
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(conversationMode: true));
      c.read(micTailProvider).add(Int16List.fromList([1, 2, 3]));
      final detector = c.read(wakeBargeInDetectorProvider);
      expect(detector, isA<LazyWakeBargeInDetector>());
      final warm = (detector! as LazyWakeBargeInDetector).warm!;
      expect(warm(), [1, 2, 3]);
      // Used once: no speech stays in memory, no stale lead-in next time.
      expect(warm(), isEmpty);
    },
  );

  test('WP148: der Barge-in-Erkenner bekommt den Aufnahme-Haken', () async {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    await c.read(voiceSettingsProvider.future);
    await c
        .read(voiceSettingsProvider.notifier)
        .change((s) => s.copyWith(conversationMode: true));
    final detector = c.read(wakeBargeInDetectorProvider)!;
    expect((detector as LazyWakeBargeInDetector).devClips, same(devAudioClips));
  });

  group('WP151: Verdrahtung der Prüfer-Auswahl im Barge-in', () {
    // Live clip and enrolled „Hey Wendelin“ sequence are the same, so B
    // always has a score (reason `b`); the transcript hears „Wendelin“.
    Float32List seq() => Float32List.fromList([
      for (var f = 0; f < 25; f++)
        for (var k = 0; k < 96; k++) math.sin(f * 0.7 + k * 0.3 + 1),
    ]);

    final extractors = <FakeWakeFeatureExtractor>[];

    Future<LazyWakeBargeInDetector> build() async {
      extractors.clear();
      final env = TestEnv(
        extraOverrides: [
          speechToTextProvider.overrideWith(
            (ref) async => FixedTranscriptStt('Wendelin'),
          ),
          wakeFeaturesFactoryProvider.overrideWithValue(() {
            final e = FakeWakeFeatureExtractor(
              featureVersion: wakeVerifierBFeatureVersion,
              sequenceFor: (_) => seq(),
            );
            extractors.add(e);
            return e;
          }),
        ],
      );
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      await c.read(wakeVerifyProvider.future);
      final store = c.read(wakeStoreProvider);
      await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'A')]);
      await store.save(
        WakeTemplates(
          speakerId: 'a',
          featureVersion: wakeVerifierBFeatureVersion,
          threshold: 0.5,
          embeddings: [Float32List(4)],
          sequences: [
            for (var i = 0; i < 3; i++)
              WakeTemplateSequence(word: WakeTemplates.wordHw, values: seq()),
          ],
        ),
      );
      return c.read(wakeBargeInDetectorProvider)! as LazyWakeBargeInDetector;
    }

    final clip = Int16List(16000)..fillRange(0, 16000, 7000);

    test('Text ohne Weckwort: B entscheidet', () async {
      final detector = await build();
      final v = detector.verifier!(() => 'Am Bahnhof ist Halt.');
      final r = await v.verify(clip, candidate: BargeInKeyword.wake);
      expect(r.verifier, 'b');
    });

    test(
      'Text mit Weckwort: das echte spoken erreicht die Weiche (Echo)',
      () async {
        final detector = await build();
        final v = detector.verifier!(() => 'Ich bin Wendelin.');
        final r = await v.verify(clip, candidate: BargeInKeyword.wake);
        expect(r.result, 'echo'); // Transkript mit Echo-Filter, nicht B
        expect(r.verifier, 'transcript');
      },
    );

    test('dispose schließt die Merkmalskette von B', () async {
      final detector = await build();
      final v = detector.verifier!(() => 'Am Bahnhof ist Halt.');
      await v.verify(clip, candidate: BargeInKeyword.wake);
      expect(extractors.single.isOpen, isTrue); // B hat sie geöffnet
      await detector.dispose();
      expect(extractors.single.isOpen, isFalse);
    });
  });
}
