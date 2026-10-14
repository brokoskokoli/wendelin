import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/device_memory.dart';
import '../platform/voice/file_model_store.dart';
import '../platform/voice/model_installer.dart';
import 'providers.dart';
import 'voice_providers.dart';

// Riverpod wiring of the voice settings and the model downloads. The
// logic lives in `wendelin_voice` (`VoiceSettings`, `ModelInstallStates`).

/// Settings key of [VoiceSettings]. No default value: whether settings
/// were ever stored decides the model of older installations (see
/// [VoiceSettingsNotifier]).
final voiceSettingsKey = SettingKey<VoiceSettings>(
  'voice.settings',
  encode: (s) => s.toJson(),
  decode: (json) {
    if (json is Map<String, Object?>) return VoiceSettings.fromJson(json);
    throw const FormatException('voice.settings: Objekt erwartet');
  },
);

/// Voice settings (read from the settings store on first use).
final voiceSettingsProvider =
    AsyncNotifierProvider<VoiceSettingsNotifier, VoiceSettings>(
      VoiceSettingsNotifier.new,
    );

/// Total RAM of the device in bytes (`null` = unknown); tests override it.
final deviceMemoryProvider = FutureProvider<int?>((ref) => deviceTotalMemory());

/// Voice settings notifier.
final class VoiceSettingsNotifier extends AsyncNotifier<VoiceSettings> {
  @override
  Future<VoiceSettings> build() async =>
      await ref.read(storageProvider).settings.get(voiceSettingsKey) ??
      VoiceSettings(sttModel: await _unsetModel());

  /// Model while nothing is stored: small (WP33), but base if only base is
  /// on the device (installation from before WP33, else the microphone
  /// would be greyed out) or the device has little memory and small is not
  /// there yet.
  Future<String> _unsetModel() async {
    const base = SpeechModelCatalog.whisperBase;
    const small = SpeechModelCatalog.whisperSmall;
    final SpeechModelService service;
    try {
      service = await ref.read(speechModelServiceProvider.future);
    } on Object catch (e) {
      debugPrint('Modellverzeichnis nicht verfügbar: $e');
      return small.id;
    }
    if (await service.isInstalled(small)) return small.id;
    if (await service.isInstalled(base) ||
        isLowMemory(await ref.read(deviceMemoryProvider.future))) {
      return base.id;
    }
    return small.id;
  }

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

/// Download state per model id; starts, cancels and deletes downloads.
final modelStatesProvider =
    NotifierProvider<ModelStatesNotifier, Map<String, ModelState>>(
      ModelStatesNotifier.new,
    );

/// Model download states: publishes a [ModelInstallStates] (package) as
/// Riverpod state and rebuilds the engines of an installed model.
final class ModelStatesNotifier extends Notifier<Map<String, ModelState>> {
  late ModelInstallStates _core;

  @override
  Map<String, ModelState> build() {
    _core = ModelInstallStates(
      catalog: () => ref.read(speechModelCatalogProvider),
      service: () => ref.read(speechModelServiceProvider.future),
      onChanged: (states) {
        if (ref.mounted) state = states;
      },
      onInstalled: _onInstalled,
      log: debugPrint,
    );
    ref.onDispose(_core.dispose);
    unawaited(Future.microtask(refresh));
    return const {};
  }

  /// State of [modelId].
  ModelState of(String modelId) => state[modelId] ?? _core.of(modelId);

  /// Re-reads which models are installed or partly downloaded.
  Future<void> refresh() => _core.refresh();

  /// Downloads [modelId] (continues a partial download).
  Future<void> download(String modelId) => _core.download(modelId);

  /// Re-checks [modelId] after a failure but keeps the error message.
  @visibleForTesting
  Future<void> refreshKeepingError(String modelId) =>
      _core.refreshKeepingError(modelId);

  /// Cancels the download of [modelId] (the partial file stays).
  void cancel(String modelId) => _core.cancel(modelId);

  /// Deletes [modelId] from the device.
  Future<void> delete(String modelId) => _core.delete(modelId);

  /// Continues every partly downloaded model (after an app restart).
  Future<void> resumePartial() => _core.resumePartial();

  void _onInstalled(SpeechModel model) {
    if (!ref.mounted) return;
    switch (model.kind) {
      case SpeechModelKind.stt:
        ref.invalidate(engineWhisperProvider);
      case SpeechModelKind.vad:
        ref.invalidate(voiceActivityDetectorProvider);
      case SpeechModelKind.tts:
        ref.invalidate(ttsSelectionProvider);
    }
  }
}
