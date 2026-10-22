import 'package:meta/meta.dart';

/// What stage 1 makes of a classifier score (WP129, rule of WP133).
enum WakeScoreVerdict {
  /// Below the band: no candidate.
  reject,

  /// Inside the band: stage 2 (transcript) decides.
  verify,

  /// At or above the upper limit: a sure hit, stage 2 is skipped.
  accept,
}

/// The two limits of the classifier score for one mode. A score below
/// [verifyFrom] is discarded, from [verifyFrom] up to (excluding) [acceptFrom]
/// stage 2 checks it, from [acceptFrom] on it is accepted directly. Both
/// limits are inclusive at their lower edge.
@immutable
final class WakeScoreBand {
  /// Creates a band; [verifyFrom] must not exceed [acceptFrom].
  const WakeScoreBand({required this.verifyFrom, required this.acceptFrom})
    : assert(verifyFrom <= acceptFrom, 'untere Grenze über der oberen');

  /// Lower limit: below it the score is discarded.
  final double verifyFrom;

  /// Upper limit: from it on stage 2 is skipped.
  final double acceptFrom;

  /// Verdict for [score]; a `NaN` score is rejected (fail closed).
  WakeScoreVerdict verdict(double score) {
    if (score >= acceptFrom) return WakeScoreVerdict.accept;
    if (score >= verifyFrom) return WakeScoreVerdict.verify;
    return WakeScoreVerdict.reject;
  }

  @override
  bool operator ==(Object other) =>
      other is WakeScoreBand &&
      other.verifyFrom == verifyFrom &&
      other.acceptFrom == acceptFrom;

  @override
  int get hashCode => Object.hash(verifyFrom, acceptFrom);

  @override
  String toString() => 'WakeScoreBand($verifyFrom..$acceptFrom)';
}
