import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// Stage 2 of the barge-in on the big recognizer (WP113, K84): the model is
/// the one of the pipeline (shared, loaded on first use), the language is
/// read for every check (the app language can change).
final class LazyBargeVerifier implements BargeVerifier {
  /// Creates the verifier.
  LazyBargeVerifier({
    required this.stt,
    required this.language,
    required this.spokenText,
  });

  /// The recognizer (Whisper of the pipeline).
  final Future<SpeechToText> Function() stt;

  /// Language of the stop word right now.
  final String Function() language;

  /// Text read aloud so far (own voice filter).
  final String Function() spokenText;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async => TranscriptBargeVerifier(
    await stt(),
    language: language(),
    spokenText: spokenText,
  ).verify(pcm, candidate: candidate);
}
