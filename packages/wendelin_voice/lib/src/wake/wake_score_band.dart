import 'package:meta/meta.dart';

/// The two limits of the classifier score for one mode (the engine applies them
/// as `modelThreshold`/`directThreshold`). A score below
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
