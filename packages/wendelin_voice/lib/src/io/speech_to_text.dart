import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Result of a transcription.
@immutable
final class Transcript {
  /// Creates a transcript.
  const Transcript({required this.text, this.language, this.confidence});

  /// Recognized text (trimmed; empty if nothing was recognized).
  final String text;

  /// Detected or forced language as BCP 47 tag (`de`, `fr`, `en`).
  final String? language;

  /// Confidence 0.0–1.0, if the engine reports one.
  final double? confidence;

  @override
  bool operator ==(Object other) =>
      other is Transcript &&
      other.text == text &&
      other.language == language &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(text, language, confidence);

  @override
  String toString() => 'Transcript("$text", $language, $confidence)';
}

/// Description of an STT engine for settings and logs.
@immutable
final class SpeechToTextEngineInfo {
  /// Creates the info.
  const SpeechToTextEngineInfo({
    required this.name,
    required this.languages,
    this.model,
  });

  /// Engine name (e.g. `Whisper (sherpa-onnx)`, `System`).
  final String name;

  /// Supported languages as BCP 47 tags.
  final Set<String> languages;

  /// Model id from the `SpeechModelCatalog`, if any.
  final String? model;

  @override
  String toString() => 'SpeechToTextEngineInfo($name, $model, $languages)';
}

/// Speech recognition of a finished recording (concept: stage 4).
///
/// Contract (`speechToTextContract`):
/// - [transcribe] takes 16 kHz mono PCM; [language] `null` = detect
///   automatically, otherwise one of [SpeechToTextEngineInfo.languages].
/// - An unsupported [language] throws `VoiceException` with kind
///   `unsupportedLanguage`; empty audio or silence yields an empty, trimmed
///   text instead of an error.
/// - `Transcript.confidence` is `null` or within `[0, 1]`;
///   `Transcript.language` is `null` or a supported language.
abstract interface class SpeechToText {
  /// Engine description.
  SpeechToTextEngineInfo get info;

  /// Transcribes [pcm].
  Future<Transcript> transcribe(Int16List pcm, {String? language});
}
