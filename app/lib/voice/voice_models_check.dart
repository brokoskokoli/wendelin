import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/voice_providers.dart';

/// Whether the installed state of the chosen Whisper and Silero is
/// known (a fresh engine checks it in the background first).
bool voiceModelsChecked(Ref ref) {
  final states = ref.read(modelStatesProvider.notifier);
  final stt =
      ref.read(voiceSettingsProvider).value?.sttModel ??
      const VoiceSettings().sttModel;
  return states.of(stt).phase != ModelPhase.unknown &&
      states.of(SpeechModelCatalog.sileroVad.id).phase != ModelPhase.unknown;
}

/// Whether the two needed models (Whisper, Silero) are installed; `false`
/// on any failure.
Future<bool> voiceModelsInstalled(Ref ref) async {
  try {
    final service = await ref.read(speechModelServiceProvider.future);
    final catalog = ref.read(speechModelCatalogProvider);
    final settings = await ref.read(voiceSettingsProvider.future);
    for (final id in [settings.sttModel, SpeechModelCatalog.sileroVad.id]) {
      final model = catalog.byId(id);
      if (model == null || !await service.isInstalled(model)) return false;
    }
    return true;
  } on Object {
    return false;
  }
}
