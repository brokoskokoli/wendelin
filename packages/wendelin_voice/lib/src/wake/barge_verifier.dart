import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../io/barge_in_detector.dart';
import '../io/speech_to_text.dart';
import 'wake_verifier.dart';

/// Outcome of the check of a barge-in candidate by the big recognizer.
@immutable
final class BargeVerdict {
  /// Creates a verdict.
  const BargeVerdict(this.result, [this.keyword, this.reason]);

  /// The candidate was discarded, nothing recognized.
  static const no = BargeVerdict('no');

  /// Log value: `wake`, `no`, `echo` (the word was in the text being
  /// read aloud) or `skip` (the check failed).
  final String result;

  /// Why a check was skipped (`silent`, `timeout`, `error`); `null` otherwise.
  final String? reason;

  /// The recognized keyword; `null` = discard the candidate.
  final BargeInKeyword? keyword;

  @override
  String toString() => 'BargeVerdict($result)';
}

/// Stage 2 of the barge-in (WP113, K84): checks the audio of a candidate.
abstract interface class BargeVerifier {
  /// Decides on [pcm] (16 kHz mono, the last seconds incl. the candidate).
  /// [candidate] is what stage 1 suspected; the verdict names what the
  /// recognizer actually heard. Fail closed: a failure is not a keyword.
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  });
}

/// [BargeVerifier] on a [SpeechToText]: „Wendelin“ (as for the wake word).
/// A word that occurs in the text just being
/// read aloud ([spokenText]) is the own voice and does not count.
final class TranscriptBargeVerifier implements BargeVerifier {
  /// Creates the verifier.
  TranscriptBargeVerifier(
    this.stt, {
    this.language = 'de',
    this.spokenText = _noText,
    this.maxSamples = 40000,
  });

  static String _noText() => '';

  /// The recognizer.
  final SpeechToText stt;

  /// Language of the recognition.
  final String language;

  /// The text read aloud so far in this answer.
  final String Function() spokenText;

  /// Longest transcribed audio (default 2.5 s).
  final int maxSamples;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    final audio = pcm.length > maxSamples
        ? Int16List.sublistView(pcm, pcm.length - maxSamples)
        : pcm;
    // Read before the await: the ring of read sentences moves on meanwhile.
    final spoken = spokenText();
    final text = (await stt.transcribe(audio, language: language)).text;
    // The own voice: a keyword that is part of the read text does not count.
    final wake = matchesWakeWord(text) && !matchesWakeWord(spoken);
    if (wake) return const BargeVerdict('wake', BargeInKeyword.wake);
    final echo = matchesWakeWord(text) && matchesWakeWord(spoken);
    return echo ? const BargeVerdict('echo') : BargeVerdict.no;
  }
}
