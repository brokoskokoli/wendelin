import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Why a voice was not assigned to a person.
enum SpeakerUnknownReason {
  /// Recognition is on, but nobody is enrolled.
  noProfiles,

  /// The audio was too short for a reliable embedding.
  tooShort,

  /// The best score was below the threshold of its person (a stranger).
  belowThreshold,

  /// Two persons scored nearly the same.
  ambiguous,

  /// The embedder failed (model missing, error); never blocks the request.
  failed,
}

/// Result of the speaker recognition: a person with the score, or unknown
/// (WP92a). The score is a cosine similarity; it is no proof of identity.
@immutable
final class SpeakerMatch {
  /// A recognized person.
  const SpeakerMatch.known({
    required String this.personId,
    required String this.name,
    required this.score,
    this.threshold,
    this.second,
    this.profileCount,
  }) : reason = null,
       failure = null;

  /// Not recognized, with the best [score] if one was computed.
  const SpeakerMatch.unknown(
    SpeakerUnknownReason this.reason, {
    this.score,
    this.threshold,
    this.second,
    this.profileCount,
    this.failure,
  }) : personId = null,
       name = null;

  /// Id of the person, `null` = unknown.
  final String? personId;

  /// Name of the person, `null` = unknown.
  final String? name;

  /// Cosine score of the best candidate (`null` if none was computed).
  final double? score;

  /// Threshold the best score was measured against (diagnostics only; `null`
  /// if none was applied).
  final double? threshold;

  /// Score of the second-best person (diagnostics only; `null` if none).
  final double? second;

  /// Number of enrolled persons (diagnostics only; `null` = not read).
  final int? profileCount;

  /// Type of the error behind `failed`, lower case, never its message
  /// (diagnostics only).
  final String? failure;

  /// Why unknown; `null` for a recognized person.
  final SpeakerUnknownReason? reason;

  /// Whether a person was recognized.
  bool get isKnown => personId != null;

  @override
  bool operator ==(Object other) =>
      other is SpeakerMatch &&
      other.personId == personId &&
      other.score == score &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(personId, score, reason);

  /// Never contains the name (it can reach logs).
  @override
  String toString() => isKnown
      ? 'SpeakerMatch(known, ${score?.toStringAsFixed(2)})'
      : 'SpeakerMatch(unknown, ${reason?.name})';
}

/// What the pipeline needs from the recognition (implemented by
/// `SpeakerIdentifier`, faked in tests).
abstract interface class SpeakerRecognizer {
  /// Who spoke [pcm] (mono 16 kHz). Never throws.
  Future<SpeakerMatch> identify(Int16List pcm);
}

/// The diagnostics line of one recognition (WP160): outcome and numbers, never
/// a name, an id or a transcript.
String speakerLogLine({
  required String result,
  required int audioMs,
  required int ms,
  String? reason,
  SpeakerMatch? match,
}) {
  String n(double? v) => v == null ? '-' : v.toStringAsFixed(2);
  final b = StringBuffer('speaker result=$result');
  if (reason != null) b.write(' reason=$reason');
  if (result != 'off') {
    b.write(
      ' best=${n(match?.score)} thr=${n(match?.threshold)} '
      'second=${n(match?.second)}',
    );
  }
  b.write(' audioMs=$audioMs ms=$ms');
  if (result != 'off') b.write(' profiles=${match?.profileCount ?? '-'}');
  if (match?.failure case final f?) b.write(' error=$f');
  return b.toString();
}
