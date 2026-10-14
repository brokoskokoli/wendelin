import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/audio_playback.dart';
import '../platform/voice/onnx_wake_models.dart';
import '../platform/voice/pcm.dart';
import '../platform/voice/wake_feature_chain.dart';
import '../voice/wake/wake_barge_in.dart';
import '../voice/wake/wake_storage.dart';
import 'core_providers.dart';
import 'voice_providers.dart';

// Personal wake word (WP60): templates, speakers, the second-stage setting
// and the feature chain. WP50 builds the live engine from the same pieces.

/// Setting „Nachprüfung mit Whisper“ (default on).
final wakeVerifyKey = SettingKey.boolean('wake.verify', defaultValue: true);

/// Templates and speakers in the encrypted secret store.
final wakeStoreProvider = Provider<SecretWakeTemplateStore>(
  (ref) => SecretWakeTemplateStore(ref.watch(secretStoreProvider)),
);

/// Whether stage 2 (Whisper) confirms candidates in everyday use. Switch
/// off if it is too strict with the real voice; the test mode always shows
/// both stages. Default on.
final wakeVerifyProvider = AsyncNotifierProvider<WakeVerifyNotifier, bool>(
  WakeVerifyNotifier.new,
);

/// Stores the setting.
final class WakeVerifyNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      await ref.read(storageProvider).settings.get(wakeVerifyKey) ?? true;

  /// Switches stage 2 on or off.
  Future<void> set({required bool enabled}) async {
    state = AsyncData(enabled);
    await ref.read(storageProvider).settings.set(wakeVerifyKey, enabled);
  }
}

/// The learned speakers.
final wakeSpeakersProvider =
    AsyncNotifierProvider<WakeSpeakersNotifier, List<WakeSpeaker>>(
      WakeSpeakersNotifier.new,
    );

/// Speaker list with add, rename and delete (templates go with it).
final class WakeSpeakersNotifier extends AsyncNotifier<List<WakeSpeaker>> {
  @override
  Future<List<WakeSpeaker>> build() => ref.read(wakeStoreProvider).speakers();

  /// Adds (or keeps) the speaker [id]; the templates come from the
  /// enrollment.
  Future<void> upsert(String id, String name) async {
    final list = [
      for (final s in await future)
        if (s.id != id) s,
      WakeSpeaker(id: id, name: name),
    ];
    await ref.read(wakeStoreProvider).saveSpeakers(list);
    state = AsyncData(list);
  }

  /// Forgets speaker [id] with all templates.
  Future<void> remove(String id) async {
    final store = ref.read(wakeStoreProvider);
    await store.delete(id);
    final list = [
      for (final s in await future)
        if (s.id != id) s,
    ];
    await store.saveSpeakers(list);
    state = AsyncData(list);
  }

  /// Forgets everyone („Alles löschen“).
  Future<void> removeAll() async {
    await ref.read(wakeStoreProvider).deleteAll();
    state = const AsyncData([]);
  }
}

/// Templates of [id] (`null`: none).
final wakeTemplatesProvider = FutureProvider.family<WakeTemplates?, String>(
  (ref, id) => ref.watch(wakeStoreProvider).load(id),
);

/// New feature chain (tests replace it by a fake). The models come from
/// the catalog entry `wake-features`; an error if they are not downloaded.
final wakeFeaturesFactoryProvider = Provider<WakeFeatureExtractor Function()>((
  ref,
) {
  return () => ChainWakeFeatureExtractor(() async {
    final service = await ref.read(speechModelServiceProvider.future);
    final model = ref
        .read(speechModelCatalogProvider)
        .byId(SpeechModelCatalog.wakeFeatures.id)!;
    if (!await service.isInstalled(model)) {
      throw const VoiceException(
        VoiceErrorKind.modelMissing,
        'Die Merkmalsmodelle fehlen (Einstellungen → Sprache → '
        'Aktivierungswort).',
      );
    }
    return OnnxWakeModels.open(service.directoryOf(model).path);
  });
});

/// Stage 2 on Whisper; `null` while Whisper is not loaded.
final wakeVerifierProvider = FutureProvider<WakeVerifier?>((ref) async {
  try {
    return TranscriptWakeVerifier(await ref.watch(speechToTextProvider.future));
  } on Object {
    return null;
  }
});

/// Microphone for enrollment, calibration and test (the same as the
/// voice pipeline; device tests replace it by WAV files).
final wakeAudioProvider = Provider<AudioInput>(
  (ref) => ref.watch(audioInputProvider),
);

/// Short tone (880 Hz, 0.35 s) asking the speaker to say „Wendelin“ during
/// the calibration (replaced in tests).
final wakePromptToneProvider = Provider<Future<void> Function()>((ref) {
  final playback = AudioplayersPlayback();
  ref.onDispose(() => unawaited(playback.dispose()));
  final samples = Int16List(5600);
  for (var i = 0; i < samples.length; i++) {
    final fade = math.min(1.0, math.min(i, samples.length - i) / 800);
    samples[i] = (math.sin(2 * math.pi * 880 * i / 16000) * 9000 * fade)
        .round();
  }
  return () => playback.play(Wav(samples));
});

/// Pause between two recordings of the enrollment (tests set it to zero).
final wakeEnrollPauseProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 900),
);

/// Barge-in on the wake word chain (WP50): „Wendelin“ interrupts the
/// spoken answer in the conversation mode. `null` while the conversation
/// mode is off. `bootstrap/run_app.dart` puts it in place of the empty
/// [bargeInDetectorProvider]; tests keep that one.
final wakeBargeInDetectorProvider = Provider<BargeInDetector?>((ref) {
  final conversation = ref.watch(
    voiceSettingsProvider.select((s) => s.value?.conversationMode ?? false),
  );
  if (!conversation) return null;
  final store = ref.read(wakeStoreProvider);
  final detector = LazyWakeBargeInDetector(
    audio: ref.watch(audioInputProvider),
    features: () => ref.read(wakeFeaturesFactoryProvider)(),
    templates: () async => [
      for (final s in await store.speakers()) ?await store.load(s.id),
    ],
  );
  ref.onDispose(() => unawaited(detector.dispose()));
  return detector;
});
