import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/audio_playback.dart';
import '../platform/voice/file_model_store.dart';
import '../platform/voice/model_installer.dart';
import '../platform/voice/record_audio_input.dart';
import '../platform/voice/sherpa_tts.dart';
import '../platform/voice/silero_vad.dart';
import '../platform/voice/system_tts.dart';
import '../platform/voice/tar_bz2.dart';
import '../platform/voice/whisper_sherpa.dart';
import '../platform/voice/whisper_stt.dart';
import 'preferences.dart';
import 'providers.dart';

// Riverpod wiring of the voice building blocks (WP17): settings, model
// downloads, microphone, Silero VAD, Whisper, system and sherpa TTS. The
// pipeline itself (with the agent) is built by the trigger side (WP18)
// from [voiceComponentsProvider].

/// Settings of Einstellungen → Sprache.
@immutable
final class VoiceSettings {
  /// Creates the settings; defaults calibrated in
  /// `docs/notes/stt-wer-2026-10-13.md`.
  const VoiceSettings({
    this.sttModel = 'whisper-base',
    this.sttLanguage = followApp,
    this.tts = TtsPreference.automatic,
    this.ttsVoice,
    this.ttsRate = 1.0,
    this.minSpeechMs = 200,
    this.vadThreshold = 0.5,
  });

  /// [sttLanguage]: use the language chosen in the onboarding.
  static const followApp = 'app';

  /// [sttLanguage]: let Whisper detect the language.
  static const detect = 'auto';

  /// Offered tempo values.
  static const rates = [0.8, 1.0, 1.2, 1.5];

  /// Offered minimum speech durations (ms).
  static const minSpeechChoices = [100, 200, 300, 400];

  /// Offered VAD thresholds.
  static const thresholds = [0.3, 0.4, 0.5, 0.6, 0.7];

  /// Whisper model id (`whisper-base`, `whisper-small`).
  final String sttModel;

  /// [followApp], [detect] or a fixed language (`de`, `fr`, `en`).
  final String sttLanguage;

  /// Speech output engine preference (K7 fallback in [TtsSelector]).
  final TtsPreference tts;

  /// Voice id (system or sherpa); `null` = default voice of the language.
  final String? ttsVoice;

  /// Speech rate (1.0 = normal).
  final double ttsRate;

  /// Minimum speech duration of the endpointing (ms).
  final int minSpeechMs;

  /// Silero speech probability threshold.
  final double vadThreshold;

  /// The STT language for app language [appLanguage] (`null` = detect).
  String? effectiveLanguage(String appLanguage) => switch (sttLanguage) {
    followApp => appLanguage,
    detect => null,
    final fixed => fixed,
  };

  /// Endpointing limits with [minSpeechMs].
  EndpointConfig get endpoint =>
      EndpointConfig(minSpeech: Duration(milliseconds: minSpeechMs));

  /// Copy with changes; [clearVoice] resets [ttsVoice].
  VoiceSettings copyWith({
    String? sttModel,
    String? sttLanguage,
    TtsPreference? tts,
    String? ttsVoice,
    bool clearVoice = false,
    double? ttsRate,
    int? minSpeechMs,
    double? vadThreshold,
  }) => VoiceSettings(
    sttModel: sttModel ?? this.sttModel,
    sttLanguage: sttLanguage ?? this.sttLanguage,
    tts: tts ?? this.tts,
    ttsVoice: clearVoice ? null : ttsVoice ?? this.ttsVoice,
    ttsRate: ttsRate ?? this.ttsRate,
    minSpeechMs: minSpeechMs ?? this.minSpeechMs,
    vadThreshold: vadThreshold ?? this.vadThreshold,
  );

  /// JSON for the settings store.
  Map<String, Object?> toJson() => {
    'sttModel': sttModel,
    'sttLanguage': sttLanguage,
    'tts': tts.name,
    'ttsVoice': ?ttsVoice,
    'ttsRate': ttsRate,
    'minSpeechMs': minSpeechMs,
    'vadThreshold': vadThreshold,
  };

  /// Reads [json]; unknown or invalid values fall back to the defaults.
  static VoiceSettings fromJson(Map<String, Object?> json) {
    const d = VoiceSettings();
    T? pick<T>(String key, bool Function(T) valid) {
      final v = json[key];
      return v is T && valid(v) ? v : null;
    }

    return VoiceSettings(
      sttModel:
          pick<String>('sttModel', (v) => v.startsWith('whisper-')) ??
          d.sttModel,
      sttLanguage:
          pick<String>(
            'sttLanguage',
            (v) => const {followApp, detect, 'de', 'fr', 'en'}.contains(v),
          ) ??
          d.sttLanguage,
      tts: TtsPreference.values.asNameMap()[json['tts']] ?? d.tts,
      ttsVoice: pick<String>('ttsVoice', (v) => v.isNotEmpty),
      ttsRate:
          pick<num>('ttsRate', (v) => v >= 0.5 && v <= 2)?.toDouble() ??
          d.ttsRate,
      minSpeechMs:
          pick<int>('minSpeechMs', (v) => v >= 50 && v <= 1000) ??
          d.minSpeechMs,
      vadThreshold:
          pick<num>('vadThreshold', (v) => v > 0 && v < 1)?.toDouble() ??
          d.vadThreshold,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      other.sttModel == sttModel &&
      other.sttLanguage == sttLanguage &&
      other.tts == tts &&
      other.ttsVoice == ttsVoice &&
      other.ttsRate == ttsRate &&
      other.minSpeechMs == minSpeechMs &&
      other.vadThreshold == vadThreshold;

  @override
  int get hashCode => Object.hash(
    sttModel,
    sttLanguage,
    tts,
    ttsVoice,
    ttsRate,
    minSpeechMs,
    vadThreshold,
  );
}

/// Settings key of [VoiceSettings].
final voiceSettingsKey = SettingKey<VoiceSettings>(
  'voice.settings',
  encode: (s) => s.toJson(),
  decode: (json) {
    if (json is Map<String, Object?>) return VoiceSettings.fromJson(json);
    throw const FormatException('voice.settings: Objekt erwartet');
  },
  defaultValue: const VoiceSettings(),
);

/// Voice settings (read from the settings store on first use).
final voiceSettingsProvider =
    AsyncNotifierProvider<VoiceSettingsNotifier, VoiceSettings>(
      VoiceSettingsNotifier.new,
    );

/// Voice settings notifier.
final class VoiceSettingsNotifier extends AsyncNotifier<VoiceSettings> {
  @override
  Future<VoiceSettings> build() async =>
      await ref.read(storageProvider).settings.get(voiceSettingsKey) ??
      const VoiceSettings();

  /// Stores [settings].
  Future<void> set(VoiceSettings settings) async {
    state = AsyncData(settings);
    await ref.read(storageProvider).settings.set(voiceSettingsKey, settings);
  }

  /// Applies [change] to the current settings and stores the result.
  Future<void> change(VoiceSettings Function(VoiceSettings) change) async =>
      set(change(await future));
}

/// Downloadable speech models.
final speechModelCatalogProvider = Provider<SpeechModelCatalog>(
  (ref) => SpeechModelCatalog.standard,
);

/// Model directory (`<app support>/models`, excluded from backups like all
/// app data, ADR 0004 §8).
final modelsDirectoryProvider = FutureProvider<Directory>(
  (ref) async =>
      Directory('${(await getApplicationSupportDirectory()).path}/models'),
);

/// Model storage and download (tests override it with a fake).
final speechModelServiceProvider = FutureProvider<SpeechModelService>((
  ref,
) async {
  final store = FileModelStore(await ref.watch(modelsDirectoryProvider.future));
  return ModelInstaller(
    store: store,
    downloader: ModelDownloader(
      client: ref.watch(httpClientProvider),
      store: store,
    ),
  );
});

/// Where a model stands on the device.
enum ModelPhase {
  /// Not checked yet.
  unknown,

  /// Not on the device.
  absent,

  /// Partly downloaded (cancelled or app closed); can be continued.
  partial,

  /// Download running.
  downloading,

  /// Archive being unpacked.
  unpacking,

  /// Ready to use.
  installed,
}

/// Download state of one model.
@immutable
final class ModelState {
  /// Creates a state.
  const ModelState(this.phase, {this.progress = 0, this.error});

  /// Phase.
  final ModelPhase phase;

  /// Download progress 0–1.
  final double progress;

  /// Message of the last failure (German), if any.
  final String? error;

  /// Whether a download or unpacking is running.
  bool get busy =>
      phase == ModelPhase.downloading || phase == ModelPhase.unpacking;

  @override
  bool operator ==(Object other) =>
      other is ModelState &&
      other.phase == phase &&
      other.progress == progress &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, progress, error);

  @override
  String toString() => 'ModelState(${phase.name}, $progress, $error)';
}

/// Download state per model id; starts, cancels and deletes downloads.
final modelStatesProvider =
    NotifierProvider<ModelStatesNotifier, Map<String, ModelState>>(
      ModelStatesNotifier.new,
    );

/// Model download states.
final class ModelStatesNotifier extends Notifier<Map<String, ModelState>> {
  final _tokens = <String, CancelToken>{};

  @override
  Map<String, ModelState> build() {
    ref.onDispose(() {
      for (final t in _tokens.values) {
        t.cancel();
      }
    });
    unawaited(Future.microtask(refresh));
    return const {};
  }

  /// State of [modelId].
  ModelState of(String modelId) =>
      state[modelId] ?? const ModelState(ModelPhase.unknown);

  void _put(String id, ModelState s) {
    if (!ref.mounted) return;
    state = {...state, id: s};
  }

  /// Re-reads which models are installed or partly downloaded.
  Future<void> refresh() async {
    final SpeechModelService service;
    try {
      service = await ref.read(speechModelServiceProvider.future);
    } on Object catch (e) {
      // No model directory (e.g. platform without path_provider): the
      // models stay „unknown“ and nothing can be downloaded.
      debugPrint('Modellverzeichnis nicht verfügbar: $e');
      return;
    }
    for (final m in ref.read(speechModelCatalogProvider).models) {
      if (of(m.id).busy) continue;
      final phase = await service.isInstalled(m)
          ? ModelPhase.installed
          : await service.hasPartial(m)
          ? ModelPhase.partial
          : ModelPhase.absent;
      _put(m.id, ModelState(phase));
    }
  }

  /// Downloads [modelId] (continues a partial download). Failures end in
  /// [ModelState.error]; cancelling keeps the partial file.
  Future<void> download(String modelId) async {
    final model = ref.read(speechModelCatalogProvider).byId(modelId);
    if (model == null || of(modelId).busy) return;
    final token = _tokens[modelId] = CancelToken();
    _put(modelId, const ModelState(ModelPhase.downloading));
    try {
      final service = await ref.read(speechModelServiceProvider.future);
      await service.install(
        model,
        cancel: token,
        onProgress: (p) => _put(
          modelId,
          ModelState(ModelPhase.downloading, progress: p.fraction),
        ),
        onUnpacking: () =>
            _put(modelId, const ModelState(ModelPhase.unpacking, progress: 1)),
      );
      _put(modelId, const ModelState(ModelPhase.installed, progress: 1));
      _onInstalled(model);
    } on Object catch (e) {
      final cancelled =
          e is CancelledException ||
          (e is ModelDownloadException &&
              e.kind == DownloadErrorKind.cancelled);
      _put(
        modelId,
        ModelState(
          cancelled ? ModelPhase.partial : ModelPhase.absent,
          error: cancelled ? null : downloadErrorText(e),
        ),
      );
      if (!cancelled) {
        // A failed download may still have left a resumable part.
        unawaited(refreshKeepingError(modelId));
      }
    } finally {
      if (identical(_tokens[modelId], token)) _tokens.remove(modelId);
    }
  }

  /// Re-checks [modelId] after a failure but keeps the error message.
  @visibleForTesting
  Future<void> refreshKeepingError(String modelId) async {
    final model = ref.read(speechModelCatalogProvider).byId(modelId);
    if (model == null || !ref.mounted) return;
    final service = await ref.read(speechModelServiceProvider.future);
    final partial = await service.hasPartial(model);
    final current = of(modelId);
    if (partial && !current.busy) {
      _put(modelId, ModelState(ModelPhase.partial, error: current.error));
    }
  }

  void _onInstalled(SpeechModel model) {
    if (!ref.mounted) return;
    switch (model.kind) {
      case SpeechModelKind.stt:
        ref.invalidate(speechToTextProvider);
      case SpeechModelKind.vad:
        ref.invalidate(voiceActivityDetectorProvider);
      case SpeechModelKind.tts:
        ref.invalidate(ttsSelectionProvider);
    }
  }

  /// Cancels the download of [modelId] (the partial file stays).
  void cancel(String modelId) => _tokens[modelId]?.cancel();

  /// Deletes [modelId] from the device.
  Future<void> delete(String modelId) async {
    final model = ref.read(speechModelCatalogProvider).byId(modelId);
    if (model == null || of(modelId).busy) return;
    final service = await ref.read(speechModelServiceProvider.future);
    await service.delete(model);
    _put(modelId, const ModelState(ModelPhase.absent));
    _onInstalled(model);
  }

  /// Continues every partly downloaded model (after an app restart).
  Future<void> resumePartial() async {
    await refresh();
    for (final e in state.entries.toList()) {
      if (e.value.phase == ModelPhase.partial && e.value.error == null) {
        unawaited(download(e.key));
      }
    }
  }
}

/// German text for a failed download.
String downloadErrorText(Object e) => switch (e) {
  InsufficientSpaceException() => e.message,
  ModelDownloadException() => e.message,
  ArchiveRejected() => e.message,
  _ => 'Der Download ist fehlgeschlagen.',
};

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
  final vad = SileroVoiceActivityDetector(
    modelPath: '${service.directoryOf(model).path}/${model.files.single.name}',
    threshold: threshold,
  );
  ref.onDispose(vad.dispose);
  return vad;
});

/// Whisper (in a background isolate) for the chosen model size.
final speechToTextProvider = FutureProvider<SpeechToText>((ref) async {
  final id = await ref.watch(
    voiceSettingsProvider.selectAsync((s) => s.sttModel),
  );
  final model = await _installedModel(ref, id, 'Das Whisper-Modell');
  final service = await ref.watch(speechModelServiceProvider.future);
  final backend = await IsolateWhisperBackend.start(
    WhisperFiles.of(model, service.directoryOf(model).path),
  );
  ref.onDispose(() => unawaited(backend.dispose()));
  return WhisperSpeechToText(backend: backend, modelId: model.id);
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

/// Offline voices (sherpa-onnx), K7 fallback.
final sherpaTtsProvider = Provider<TextToSpeech>((ref) {
  Future<List<SherpaVoice>> voices() async => installedSherpaVoices(
    await ref.read(speechModelServiceProvider.future),
    ref.read(speechModelCatalogProvider),
  );
  final synthesizer = IsolateSherpaSynthesizer(
    () async => {for (final v in await voices()) v.id: v.files},
  );
  final playback = AudioplayersPlayback();
  ref.onDispose(() {
    unawaited(synthesizer.dispose());
    unawaited(playback.dispose());
  });
  return SherpaTextToSpeech(
    installed: voices,
    synthesizer: synthesizer,
    playback: playback,
  );
});

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
}

/// The voice building blocks; fails with `VoiceException(modelMissing)`
/// while Whisper or Silero are not downloaded.
final voiceComponentsProvider = FutureProvider<VoiceComponents>((ref) async {
  final selector = ref.watch(ttsSelectorProvider);
  return VoiceComponents(
    audio: ref.watch(audioInputProvider),
    vad: await ref.watch(voiceActivityDetectorProvider.future),
    stt: await ref.watch(speechToTextProvider.future),
    textToSpeech: selector.current,
    config: await ref.watch(voicePipelineConfigProvider.future),
  );
});
