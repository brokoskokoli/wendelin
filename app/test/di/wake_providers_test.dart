import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin/voice/wake/wake_template_audit.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
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
