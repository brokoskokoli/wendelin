import 'dart:io';

import 'package:meta/meta.dart';
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
  String fallbackLanguage = 'de',
}) async {
  if (model.engine == SttEngine.whisper) {
    return IsolateWhisperBackend.start(WhisperFiles.of(model, directory));
  }
  final files = resolveNemoFiles(
    model,
    directory,
    hintTerms: hintTerms,
    hotwordsScore: hotwordsScore,
    fallbackLanguage: fallbackLanguage,
  );
  if (files == null) {
    throw const VoiceException(
      VoiceErrorKind.modelMissing,
      'Das Spracherkennungsmodell ist nicht (vollständig) geladen.',
    );
  }
  return IsolateWhisperBackend.start(files);
}

/// The files of the NeMo [model] under [directory], with hotwords for
/// [hintTerms] if the model takes them and a name can be spelled (`null`
/// if a model file is missing). Without usable names an old hotwords file
/// is deleted. [fallbackLanguage] is the app language (Canary).
@visibleForTesting
NemoFiles? resolveNemoFiles(
  SpeechModel model,
  String directory, {
  List<String> hintTerms = const [],
  double hotwordsScore = defaultHotwordsScore,
  String fallbackLanguage = 'de',
}) {
  final files = NemoFiles.find(
    model,
    directory,
    fallbackLanguage: fallbackLanguage,
  );
  if (files == null) return null;
  final dir = Directory('$directory/hotwords');
  if (!model.supportsHotwords || hintTerms.isEmpty) {
    clearNemoHotwords(dir);
    return files;
  }
  final hotwords = writeNemoHotwords(
    tokens: files.tokens,
    terms: hintTerms,
    directory: dir,
    score: hotwordsScore,
  );
  return hotwords == null
      ? files
      : NemoFiles.find(
          model,
          directory,
          hotwords: hotwords,
          fallbackLanguage: fallbackLanguage,
        );
}

/// Engine name for `SpeechToTextEngineInfo` and logs.
String sttEngineName(SttEngine engine) => switch (engine) {
  SttEngine.whisper => 'Whisper (sherpa-onnx)',
  SttEngine.nemoTransducer => 'Parakeet (sherpa-onnx)',
  SttEngine.canary => 'Canary (sherpa-onnx)',
};
