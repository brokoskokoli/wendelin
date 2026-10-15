import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/audio_playback.dart';
import '../platform/voice/engine_whisper.dart';
import '../platform/voice/record_audio_input.dart';
import '../platform/voice/sherpa_tts.dart';
import '../platform/voice/silero_vad.dart';
import '../platform/voice/system_tts.dart';
import '../platform/voice/whisper_sherpa.dart';
import '../platform/voice/whisper_stt.dart';
import '../voice/voice_log.dart';
import 'preferences.dart';
import 'vocabulary_provider.dart';
import 'voice_settings_providers.dart';

export 'package:wendelin_voice/wendelin_voice.dart'
    show ModelPhase, ModelState, VoiceSettings, downloadErrorText;

export 'voice_settings_providers.dart';

// Riverpod wiring of the voice building blocks (WP17): settings, model
// downloads, microphone, Silero VAD, Whisper, system and sherpa TTS. The
// pipeline itself (with the agent) is built by the trigger side (WP18)
// from [voiceComponentsProvider].

/// Microphone access of the `record` plugin.
final microphoneProvider = Provider<PcmRecorder>((ref) => RecordPcmRecorder());

/// Microphone as [AudioInput] (16 kHz mono PCM).
final audioInputProvider = Provider<AudioInput>(
  (ref) => RecordAudioInput(ref.watch(microphoneProvider)),
);

Future<SpeechModel> _installedModel(Ref ref, String id, String what) async {
  final model = ref.read(speechModelCatalogProvider).byId(id);
  final service = await ref.watch(speechModelServiceProvider.future);
  if (model == null || !await service.isInstalled(model)) {
    throw VoiceException(
      VoiceErrorKind.modelMissing,
      '$what ist noch nicht geladen (Einstellungen → Sprache).',
    );
  }
  return model;
}

/// Silero VAD with the threshold from the settings.
final voiceActivityDetectorProvider = FutureProvider<VoiceActivityDetector>((
  ref,
) async {
  final threshold = await ref.watch(
    voiceSettingsProvider.selectAsync((s) => s.vadThreshold),
  );
  final model = await _installedModel(
    ref,
    SpeechModelCatalog.sileroVad.id,
    'Die Sprachaktivitätserkennung',
  );
  final service = await ref.watch(speechModelServiceProvider.future);
  final watch = Stopwatch()..start();
  final vad = SileroVoiceActivityDetector(
    modelPath: '${service.directoryOf(model).path}/${model.files.single.name}',
    threshold: threshold,
  );
  voiceLog('model-load', {
    'model': model.id,
    'kind': 'vad',
    'ms': watch.elapsed,
  });
  ref.onDispose(() {
    vad.dispose();
    voiceLog('model-free', {'model': model.id, 'kind': 'vad'});
  });
  return vad;
});

/// Loads an own Whisper model of [model] from [directory] (tests replace
/// it with a counting fake).
typedef WhisperModelLoader = Future<WhisperBackend> Function(
  SpeechModel model,
  String directory,
);

/// How this engine loads a Whisper model (background isolate).
final whisperLoaderProvider = Provider<WhisperModelLoader>(
  (ref) =>
      (model, dir) => IsolateWhisperBackend.start(WhisperFiles.of(model, dir)),
);

/// Whisper models of the other engines of the process (ADR 0008, B14).
final whisperDirectoryProvider = Provider<WhisperDirectory>(
  (ref) => const IsolateWhisperDirectory(),
);

/// Whisper of this engine for the chosen model size: the model another
/// engine already loaded, otherwise an own one (at most one per process,
/// B14). The build waits until a model is ready.
final engineWhisperProvider = FutureProvider<EngineWhisper>((ref) async {
  final id = await ref.watch(
    voiceSettingsProvider.selectAsync((s) => s.sttModel),
  );
  final model = await _installedModel(ref, id, 'Das Whisper-Modell');
  final service = await ref.watch(speechModelServiceProvider.future);
  final load = ref.watch(whisperLoaderProvider);
  final whisper = EngineWhisper(
    modelId: model.id,
    load: () => load(model, service.directoryOf(model).path),
    directory: ref.watch(whisperDirectoryProvider),
  );
  // Model change or new download: the old model is freed before the new
  // one loads (EngineWhisper waits for it).
  ref.onDispose(() => unawaited(whisper.release(reason: 'replaced')));
  await whisper.warm();
  return whisper;
});

/// Whisper as [SpeechToText] for the chosen model size.
final speechToTextProvider = FutureProvider<SpeechToText>((ref) async {
  final whisper = await ref.watch(engineWhisperProvider.future);
  return WhisperSpeechToText(
    backend: whisper,
    modelId: whisper.modelId,
    // Durations only, never the text (measurements on the device, WP19).
    onTiming: (t) => debugPrint('$t'),
  );
});

/// Android system TTS.
final systemTtsProvider = Provider<TextToSpeech>((ref) => SystemTextToSpeech());

/// Installed sherpa-onnx voices: each voice archive is unpacked into
/// `<model dir>/<archive name>/` (see `ModelInstaller.unpackedDir`).
Future<List<SherpaVoice>> installedSherpaVoices(
  SpeechModelService service,
  SpeechModelCatalog catalog,
) async {
  final voices = <SherpaVoice>[];
  for (final m in catalog.ofKind(SpeechModelKind.tts)) {
    if (!await service.isInstalled(m)) continue;
    final base = m.files.first.name.replaceFirst(RegExp(r'\.tar\.bz2$'), '');
    final files = PiperVoiceFiles.find(
      Directory('${service.directoryOf(m).path}/$base'),
    );
    if (files == null) continue;
    voices.add(
      SherpaVoice(
        id: m.id,
        language: m.languages.first,
        name: m.displayName,
        files: files,
      ),
    );
  }
  return voices;
}

/// The sherpa-onnx synthesizer of the offline voices; its `dispose` frees
/// the loaded voices, the next answer loads them again (B14).
final sherpaSynthesizerProvider = Provider<SpeechSynthesizer>((ref) {
  final synthesizer = IsolateSherpaSynthesizer(
    () async => {
      for (final v in await installedSherpaVoices(
        await ref.read(speechModelServiceProvider.future),
        ref.read(speechModelCatalogProvider),
      ))
        v.id: v.files,
    },
  );
  ref.onDispose(() => unawaited(synthesizer.dispose()));
  return synthesizer;
});

/// Offline voices (sherpa-onnx), K7 fallback.
final sherpaTtsProvider = Provider<TextToSpeech>(createSherpaTts);

/// Builds the offline speech output with the voice chosen in the settings
/// (WP66); the body of [sherpaTtsProvider], also used by tests.
@visibleForTesting
TextToSpeech createSherpaTts(
  Ref ref, {
  AudioPlayback? playback,
  Future<List<SherpaVoice>> Function()? installed,
}) {
  Future<List<SherpaVoice>> voices() async => installed != null
      ? installed()
      : installedSherpaVoices(
          await ref.read(speechModelServiceProvider.future),
          ref.read(speechModelCatalogProvider),
        );
  final own = playback == null ? AudioplayersPlayback() : null;
  if (own != null) ref.onDispose(() => unawaited(own.dispose()));
  final out = playback ?? own!;
  return SherpaTextToSpeech(
    installed: voices,
    synthesizer: ref.watch(sherpaSynthesizerProvider),
    playback: out,
    preferred: () =>
        ref.read(voiceSettingsProvider).value?.sherpaVoices ?? const {},
  );
}

/// Chooses system or offline voice per answer (K7).
final ttsSelectorProvider = Provider<TtsSelector>(
  (ref) => TtsSelector(
    system: ref.watch(systemTtsProvider),
    sherpa: ref.watch(sherpaTtsProvider),
    preference: () =>
        ref.read(voiceSettingsProvider).value?.tts ?? TtsPreference.automatic,
  ),
);

/// Which engine would speak an answer in the app language (for the
/// settings: „Systemstimme fehlt – Offline-Stimme“).
final ttsSelectionProvider = FutureProvider.autoDispose<TtsSelection>((
  ref,
) async {
  await ref.watch(voiceSettingsProvider.selectAsync((s) => s.tts));
  return ref
      .watch(ttsSelectorProvider)
      .select(language: ref.watch(languageProvider));
});

/// Detector for „Wendelin“/„Stopp“ during the speech output (K23 c).
/// `null` = not available: the wake word model comes with WP58 (and the
/// engine with WP44), until then the setting says „nicht verfügbar“ and
/// the pipeline gets barge-in `off`. Tests and WP58 override it.
final bargeInDetectorProvider = Provider<BargeInDetector?>((ref) => null);

/// Whether barge-in works on this device (a detector exists).
final bargeInAvailableProvider = Provider<bool>(
  (ref) => ref.watch(bargeInDetectorProvider) != null,
);

/// Pipeline settings from Einstellungen → Sprache.
final voicePipelineConfigProvider = FutureProvider<VoicePipelineConfig>((
  ref,
) async {
  final s = await ref.watch(voiceSettingsProvider.future);
  return VoicePipelineConfig(
    endpoint: s.endpoint,
    language: s.effectiveLanguage(ref.watch(languageProvider)),
    voice: s.ttsVoice,
    rate: s.ttsRate,
    conversationMode: s.conversationMode,
    // Without a detector there is nothing to interrupt with (WP58).
    bargeIn: ref.watch(bargeInAvailableProvider) ? s.bargeIn : BargeInMode.off,
  );
});

/// Everything a `VoicePipeline` needs besides the agent and the triggers.
@immutable
final class VoiceComponents {
  /// Creates the bundle.
  const VoiceComponents({
    required this.audio,
    required this.vad,
    required this.stt,
    required this.textToSpeech,
    required this.config,
    this.bargeInDetector,
    this.warmUp,
    this.release,
  });

  /// Microphone.
  final AudioInput audio;

  /// Silero VAD.
  final VoiceActivityDetector vad;

  /// Whisper.
  final SpeechToText stt;

  /// Speech output per answer language (`TtsSelector.current`).
  final Future<TextToSpeech?> Function(String? language) textToSpeech;

  /// Pipeline settings.
  final VoicePipelineConfig config;

  /// Detector for barge-in (`null`: none, see [bargeInDetectorProvider]).
  final BargeInDetector? bargeInDetector;

  /// Loads the models again after [release] (`null`: always loaded).
  final Future<void> Function()? warmUp;

  /// Frees the large models (Whisper, offline voice) until [warmUp] or the
  /// next use (B14: idle in the background).
  final Future<void> Function()? release;
}

/// The voice building blocks; fails with `VoiceException(modelMissing)`
/// while Whisper or Silero are not downloaded.
///
/// Whoever runs a `VoicePipeline` on them must call `cancel()` when the
/// app goes to the background (ADR 0007 §12), so the microphone is freed.
final voiceComponentsProvider = FutureProvider<VoiceComponents>((ref) async {
  final selector = ref.watch(ttsSelectorProvider);
  final whisper = await ref.watch(engineWhisperProvider.future);
  final sherpa = ref.watch(sherpaSynthesizerProvider);
  return VoiceComponents(
    audio: ref.watch(audioInputProvider),
    vad: await ref.watch(voiceActivityDetectorProvider.future),
    // Names from the vault are corrected after recognition (WP33, B6).
    stt: CorrectingSpeechToText(
      await ref.watch(speechToTextProvider.future),
      vocabulary: ref.read(vocabularySourceProvider).current,
      onCorrected: ref.read(correctedTitlesProvider).record,
    ),
    textToSpeech: selector.current,
    config: await ref.watch(voicePipelineConfigProvider.future),
    bargeInDetector: ref.watch(bargeInDetectorProvider),
    warmUp: whisper.warm,
    release: () async {
      await whisper.release(reason: 'idle');
      await sherpa.dispose();
    },
  );
});
