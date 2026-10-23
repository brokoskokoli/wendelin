import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_log.dart';

/// Whether [model] is installed. Throws [VoiceErrorKind.modelBroken] if it
/// is unpacked but lacks the files to load it (WP136); the app, the
/// overlay and the recognizer service share this check.
Future<bool> isModelInstalled(
  SpeechModelService service,
  SpeechModel model,
) async {
  if (await service.isInstalled(model)) return true;
  if (!await service.isDamaged(model)) return false;
  // Reason without paths: the unpacked folder lacks the model files.
  voiceLog('model-broken', {'model': model.id, 'reason': 'files-missing'});
  throw const VoiceException(
    VoiceErrorKind.modelBroken,
    'model files missing (UI text: voiceErrorModelBroken)',
  );
}
