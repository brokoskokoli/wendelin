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
import '../platform/wake/wake_detector.dart';
import '../voice/voice_log.dart';
import '../voice/wake/lazy_barge_verifier.dart';
import '../voice/wake/wake_barge_in.dart';
import '../voice/wake/wake_storage.dart';
import '../voice/wake/wake_template_audit.dart';
import 'app_settings.dart';
import 'core_providers.dart';
import 'preferences.dart';
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

/// Setting „Erkennung“ (WP129): `auto` (default), `templates`, `model`.
final wakeDetectorKey = SettingKey.string(
  'wake.detector',
  defaultValue: 'auto',
);

/// The choice of the stage 1 detection; mirrored to the service by
/// `WakeServiceNotifier`.
final wakeDetectorProvider =
    AsyncNotifierProvider<WakeDetectorNotifier, WakeDetectorChoice>(
      WakeDetectorNotifier.new,
    );

/// Whether listening needs a learned voice (WP140): the templates path does
/// (choice „Vorlagen“, „Automatisch“ (on the phone it listens with the
/// templates), or the classifier model is not installed, so the host falls
/// back to templates). Only the explicit choice „Modell“ with the model
/// installed listens without any enrolled voice.
final wakeNeedsVoiceProvider = Provider<bool>((ref) {
  final choice =
      ref.watch(wakeDetectorProvider).value ?? WakeDetectorChoice.auto;
  if (choice != WakeDetectorChoice.model) return true;
  final m = ref
      .watch(speechModelCatalogProvider)
      .byId(SpeechModelCatalog.wakeClassifierWendelin.id);
  if (m == null) return true;
  return ref.watch(modelStatesProvider)[m.id]?.phase != ModelPhase.installed;
});

/// Stores the setting.
final class WakeDetectorNotifier extends AsyncNotifier<WakeDetectorChoice> {
  @override
  Future<WakeDetectorChoice> build() async => WakeDetectorChoice.parse(
    await ref.read(storageProvider).settings.get(wakeDetectorKey),
  );

  /// Chooses the detection.
  Future<void> set(WakeDetectorChoice choice) async {
    state = AsyncData(choice);
    await ref.read(storageProvider).settings.set(wakeDetectorKey, choice.name);
  }
}

SettingKey<String> _auditKey(String id) => SettingKey.string('wake.audit.$id');

/// The learned speakers.
final wakeSpeakersProvider =
    AsyncNotifierProvider<WakeSpeakersNotifier, List<WakeSpeaker>>(
      WakeSpeakersNotifier.new,
    );

/// Speaker list with add, rename and delete (templates go with it).
final class WakeSpeakersNotifier extends AsyncNotifier<List<WakeSpeaker>> {
  @override
  Future<List<WakeSpeaker>> build() async {
    final store = ref.read(wakeStoreProvider);
    final speakers = await store.speakers();
    // WP140: once per template set, drop outliers an older enrollment let
    // in; afterwards detector and display read the pruned set.
    final settings = ref.read(storageProvider).settings;
    var changed = false;
    for (final s in speakers) {
      final key = _auditKey(s.id);
      final r = await auditTemplatesOnce(
        store,
        s.id,
        readMark: () => settings.get(key),
        writeMark: (m) => settings.set(key, m),
      );
      if (r != null && r.removed > 0) {
        changed = true;
        ref.invalidate(wakeTemplatesProvider(s.id));
      }
    }
    if (changed) ref.invalidate(wakeBargeInDetectorProvider);
    return speakers;
  }

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
    await ref.read(storageProvider).settings.remove(_auditKey(id));
    ref.invalidate(wakeBargeInDetectorProvider);
    final list = [
      for (final s in await future)
        if (s.id != id) s,
    ];
    await store.saveSpeakers(list);
    state = AsyncData(list);
  }

  /// Forgets everyone („Alles löschen“).
  Future<void> removeAll() async {
    final settings = ref.read(storageProvider).settings;
    for (final s in await future) {
      await settings.remove(_auditKey(s.id));
    }
    await ref.read(wakeStoreProvider).deleteAll();
    ref.invalidate(wakeBargeInDetectorProvider);
    state = const AsyncData([]);
  }
}

/// Templates of [id] (`null`: none).
final wakeTemplatesProvider = FutureProvider.family<WakeTemplates?, String>(
  (ref, id) => ref.watch(wakeStoreProvider).load(id),
);

/// New feature chain (tests replace it by a fake). The models come from
/// the catalog entry `wake-features`; an error if they are not downloaded.
final wakeFeaturesFactoryProvider = Provider<WakeFeatureExtractor Function()>(
  (ref) => _featuresFactory(ref, classifier: false),
);

/// WP129: the feature chain with the trained classifier (windows carry
/// `modelScore`). Needs `wake-features` and `wake-classifier-wendelin`;
/// without them an error (`modelMissing`), never a silent fallback.
final wakeClassifierFeaturesFactoryProvider =
    Provider<WakeFeatureExtractor Function()>(
      (ref) => _featuresFactory(ref, classifier: true),
    );

const _missingText =
    'Die Wake-Modelle fehlen (Einstellungen → Sprache → Aktivierungswort).';

WakeFeatureExtractor Function() _featuresFactory(
  Ref ref, {
  required bool classifier,
}) {
  return () => ChainWakeFeatureExtractor(() async {
    final service = await ref.read(speechModelServiceProvider.future);
    final catalog = ref.read(speechModelCatalogProvider);
    final model = catalog.byId(SpeechModelCatalog.wakeFeatures.id)!;
    if (!await service.isInstalled(model)) {
      throw const VoiceException(VoiceErrorKind.modelMissing, _missingText);
    }
    String? classifierPath;
    if (classifier) {
      final c = catalog.byId(SpeechModelCatalog.wakeClassifierWendelin.id)!;
      if (!await service.isInstalled(c)) {
        throw const VoiceException(VoiceErrorKind.modelMissing, _missingText);
      }
      classifierPath =
          '${service.directoryOf(c).path}/'
          '${SpeechModelCatalog.wakeClassifierFile}';
    }
    return OnnxWakeModels.open(
      service.directoryOf(model).path,
      classifierPath: classifierPath,
    );
  });
}

/// Stage 2 on Whisper; `null` while Whisper is not loaded.
final wakeVerifierProvider = FutureProvider<WakeVerifier?>((ref) async {
  try {
    return TranscriptWakeVerifier(await ref.watch(speechToTextProvider.future));
  } on Object {
    return null;
  }
});

/// Feature chain of the enrollment (WP140): with the classifier when its
/// model is installed (its score is evidence (b) of the content check),
/// otherwise the plain chain.
final wakeEnrollFeaturesFactoryProvider =
    FutureProvider<WakeFeatureExtractor Function()>((ref) async {
      var useClassifier = false;
      try {
        final service = await ref.read(speechModelServiceProvider.future);
        final c = ref
            .read(speechModelCatalogProvider)
            .byId(SpeechModelCatalog.wakeClassifierWendelin.id);
        if (c != null && await service.isInstalled(c)) {
          useClassifier = true;
        }
      } on Object {
        // Falls through to the plain chain.
      }
      return ref.read(
        useClassifier
            ? wakeClassifierFeaturesFactoryProvider
            : wakeFeaturesFactoryProvider,
      );
    });

/// Content check of the enrollment (WP140): the configured recognizer
/// (Whisper or Parakeet, as the pipeline), clip scaled to the verify peak
/// like stage 2 with Parakeet. The check log carries only the category.
final wakeEnrollVerifierProvider = FutureProvider<WakeVerifier?>((ref) async {
  final stt = await ref.watch(speechToTextProvider.future);
  return TranscriptWakeVerifier(
    stt,
    language: ref.read(languageProvider),
    normalize: true,
    onCategory: (category, ms) =>
        voiceLog('enroll-check-text', {'cat': category, 'audio': ms}),
  );
});

/// How long the enrollment waits for the recognizer to load (WP140).
final wakeEnrollVerifierWaitProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 90),
);

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

/// Barge-in on the wake word chain (WP50): „Wendelin“ interrupts the spoken
/// answer in the conversation mode. `null` while the conversation
/// mode is off. `bootstrap/run_app.dart` puts it in place of the empty
/// [bargeInDetectorProvider]; tests keep that one.
final wakeBargeInDetectorProvider = Provider<BargeInDetector?>((ref) {
  final conversation = ref.watch(
    voiceSettingsProvider.select((s) => s.value?.conversationMode ?? false),
  );
  if (!conversation) return null;
  // Newly learned or deleted voices: the callers invalidate this provider;
  // the old detector ends only when idle, so a running answer is never cut
  // off.
  final store = ref.read(wakeStoreProvider);
  final makeFeatures = ref.read(wakeFeaturesFactoryProvider);
  // Switching stage 2 or the language rebuilds the provider; a running answer
  // keeps its old detector (`disposeWhenIdle`), whose verifier holds the
  // language fixed instead of reading a disposed ref.
  final verify = ref.watch(wakeVerifyProvider.select((v) => v.value ?? true));
  final language = ref.watch(languageProvider);
  // Held now: after a rebuild during the answer the old ref is disposed and
  // a later `ref.read` in the verifier would fail (check skipped).
  final sttFuture = verify ? ref.read(speechToTextProvider.future) : null;
  // Also held now: the callbacks run after awaits, when this provider may
  // have been rebuilt (disposed ref -> `UnmountedRefException`, no start).
  final settings = ref.read(storageProvider).settings;
  final listening = ref.read(bargeListeningProvider.notifier);
  final detector = LazyWakeBargeInDetector(
    audio: ref.watch(audioInputProvider),
    // WP123: the capture before the answer primes the feature chain.
    warm: ref.read(micTailProvider).take,
    // Developer setting (WP72): other margin than +0.05.
    marginOverride: () async =>
        double.tryParse(await settings.get(AppSettings.bargeMargin) ?? ''),
    // WP113 (K84): the big recognizer checks every candidate, unless stage 2
    // is switched off in the wake word settings.
    verifier: verify
        ? (spoken) => LazyBargeVerifier(
            stt: () => sttFuture!,
            language: () => language,
            spokenText: spoken,
          )
        : null,
    onListening: ({required on}) {
      // The container may be gone (end of a test, rebuild).
      try {
        listening.set(on);
      } on Object {
        // Nobody shows it any more.
      }
    },
    features: () => makeFeatures(),
    templates: () async => [
      for (final s in await store.speakers()) ?await store.load(s.id),
    ],
  );
  ref.onDispose(() => unawaited(detector.disposeWhenIdle()));
  return detector;
});
