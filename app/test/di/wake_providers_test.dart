import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

void main() {
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
}
