import 'package:wendelin_core/wendelin_core.dart';

import 'attestation_types.dart';

/// Maps stage results onto the traffic light (concept: Fehlerverhalten,
/// `M4.md`):
/// - any `fail` is red;
/// - `unavailable` (network) is yellow while retries remain; the session
///   attestation is yellow (nothing is sent, the next request retries), a
///   receipt is retried up to [maxReceiptAttempts] times and then red;
/// - `warn` and `info` do not change the status (final green with a hint).
final class AttestationPolicy {
  /// Creates the policy.
  const AttestationPolicy({this.maxReceiptAttempts = 3});

  /// Receipt fetch attempts before an unavailable receipt counts as invalid.
  final int maxReceiptAttempts;

  /// Status of the session attestation.
  AttestationStatus sessionStatus(Iterable<StageResult> stages) =>
      _status(stages, retriesLeft: true);

  /// Status after receipt [attempt] (1-based).
  AttestationStatus receiptStatus(
    Iterable<StageResult> stages, {
    required int attempt,
  }) => _status(stages, retriesLeft: attempt < maxReceiptAttempts);

  AttestationStatus _status(
    Iterable<StageResult> stages, {
    required bool retriesLeft,
  }) {
    var unavailable = false;
    for (final s in stages) {
      if (s.outcome == StageOutcome.fail) return AttestationStatus.red;
      if (s.outcome == StageOutcome.unavailable) unavailable = true;
    }
    if (!unavailable) return AttestationStatus.green;
    return retriesLeft ? AttestationStatus.yellow : AttestationStatus.red;
  }

  /// The hints of [stages] (`warn` details) for the user.
  List<String> notes(Iterable<StageResult> stages) => [
    for (final s in stages)
      if (s.outcome == StageOutcome.warn && s.detail != null) s.detail!,
  ];
}
