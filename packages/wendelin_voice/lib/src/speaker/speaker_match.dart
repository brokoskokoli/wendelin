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
  }) : reason = null;

  /// Not recognized, with the best [score] if one was computed.
  const SpeakerMatch.unknown(SpeakerUnknownReason this.reason, {this.score})
    : personId = null,
      name = null;

  /// Id of the person, `null` = unknown.
  final String? personId;

  /// Name of the person, `null` = unknown.
  final String? name;

  /// Cosine score of the best candidate (`null` if none was computed).
  final double? score;

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
