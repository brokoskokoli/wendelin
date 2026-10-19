import 'dart:io';

import 'package:wendelin_voice/wendelin_voice.dart';

import 'nemo_sherpa.dart';
import 'whisper_sherpa.dart';
import 'whisper_stt.dart';

/// Starts the recognizer of [model] in a background isolate, with the
/// engine the catalog entry names ([SpeechModel.engine]); the choice of a
/// different model therefore only changes catalog entries (WP103).
///
/// [hintTerms] (names only) become hotwords for models that take them
/// ([SpeechModel.supportsHotwords]) and are ignored by the others. Throws
/// `VoiceException(modelMissing)` if a file is missing.
Future<WhisperBackend> startSttBackend(
  SpeechModel model,
  String directory, {
  List<String> hintTerms = const [],
  double hotwordsScore = defaultHotwordsScore,
}) async {
  if (model.engine == SttEngine.whisper) {
    return IsolateWhisperBackend.start(WhisperFiles.of(model, directory));
  }
  var files = NemoFiles.find(model, directory);
  if (files == null) {
    throw const VoiceException(
      VoiceErrorKind.modelMissing,
      'Das Spracherkennungsmodell ist nicht (vollständig) geladen.',
    );
  }
  if (model.supportsHotwords && hintTerms.isNotEmpty) {
    final hotwords = writeNemoHotwords(
      tokens: files.tokens,
      terms: hintTerms,
      directory: Directory('$directory/hotwords'),
      score: hotwordsScore,
    );
    files = NemoFiles.find(model, directory, hotwords: hotwords);
  }
  return IsolateWhisperBackend.start(files!);
}

/// Engine name for `SpeechToTextEngineInfo` and logs.
String sttEngineName(SttEngine engine) => switch (engine) {
  SttEngine.whisper => 'Whisper (sherpa-onnx)',
  SttEngine.nemoTransducer => 'Parakeet (sherpa-onnx)',
  SttEngine.canary => 'Canary (sherpa-onnx)',
};
