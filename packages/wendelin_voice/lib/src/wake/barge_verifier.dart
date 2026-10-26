import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../io/barge_in_detector.dart';
import '../io/speech_to_text.dart';
import 'barge_clip.dart';
import 'wake_verifier.dart';
import 'wake_verifier_b.dart';

/// Outcome of the check of a barge-in candidate by the big recognizer.
@immutable
final class BargeVerdict {
  /// Creates a verdict.
  const BargeVerdict(
    this.result, [
    this.keyword,
    this.reason,
    this.verifier,
    this.score,
  ]);

  /// The candidate was discarded, nothing recognized.
  static const no = BargeVerdict('no');

  /// Log value: `wake`, `no`, `echo` (the word was in the text being
  /// read aloud) or `skip` (the check failed).
  final String result;

  /// Why a check was skipped (`silent`, `timeout`, `error`); `null` otherwise.
  final String? reason;

  /// Who decided (log, WP151): `b` (templates) or `transcript`; `null` for a
  /// check that did not run.
  final String? verifier;

  /// Score of verifier B (`null` for the others).
  final double? score;

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
    if (wake) {
      return const BargeVerdict(
        'wake',
        BargeInKeyword.wake,
        null,
        'transcript',
      );
    }
    final echo = matchesWakeWord(text) && matchesWakeWord(spoken);
    return echo
        ? const BargeVerdict('echo', null, null, 'transcript')
        : const BargeVerdict('no', null, null, 'transcript');
  }
}

/// [BargeVerifier] on verifier B (WP151): compares the clip with the
/// enrolled „Hey Wendelin“ sequences instead of reading it. Parakeet often
/// reads the short call at conversation volume as another word (device log
/// 2026-10-26: 9 of 26 calls), B hits 24 of 26 and 0 of 519 TTS clips
/// (offline). B has no text, so it cannot filter the own voice; that is fine
/// while the answer does not contain the wake word (own voice vs. enrolled
/// voice). If the text read aloud contains it, TTS saying „Wendelin“ scored
/// up to 0.665 against the threshold 0.6815 offline, so the [fallback]
/// (transcript with the echo filter, K84) decides. The same happens without
/// usable sequences or on an error of B, never both for one clip.
final class VerifierBBargeVerifier implements BargeVerifier {
  /// Creates the verifier.
  VerifierBBargeVerifier({
    required this.scorer,
    required this.fallback,
    this.spokenText = _noText,
    this.minLevel = 150,
  });

  static String _noText() => '';

  /// The text read aloud so far in this answer (for the echo filter).
  final String Function() spokenText;

  /// Scores clips against the enrolled sequences.
  final VerifierBScorer scorer;

  /// Decides when B cannot (no sequences, error).
  final BargeVerifier fallback;

  /// Level of a loud block (finds the end of the word in the clip).
  final num minLevel;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    // The answer says the wake word: only the text can tell echo from call.
    if (matchesWakeWord(spokenText())) {
      return fallback.verify(pcm, candidate: candidate);
    }
    final end = speechEnd(pcm, minLevel);
    final s = end == 0 ? null : await scorer.score(pcm, end);
    if (s == null) return fallback.verify(pcm, candidate: candidate);
    return s >= scorer.threshold
        ? BargeVerdict('wake', BargeInKeyword.wake, null, 'b', s)
        : BargeVerdict('no', null, null, 'b', s);
  }
}
