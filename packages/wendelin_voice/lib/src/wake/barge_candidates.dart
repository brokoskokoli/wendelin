import '../io/barge_in_detector.dart';

/// Bookkeeping of the candidates of [WakeWordBargeInDetector]: the one that
/// waits for the end of its word (pending), the best one that came during a
/// check or the cooldown (deferred) and the one being checked (checked).
/// Positions are sample indices of the fed audio; `-1` means none.
final class BargeCandidates {
  /// Position at which the pending check may start.
  int pendingAt = -1;

  /// Kind of the pending candidate, `null`: none.
  BargeInKeyword? pendingKind;

  /// Best score of the pending candidate.
  double pendingScore = 0;

  /// End of the loud word of a pending candidate that was deferred (WP151).
  int pendingLoud = -1;

  /// Position of the strongest deferred candidate.
  int deferredAt = 0;

  /// Kind of the deferred candidate, `null`: none.
  BargeInKeyword? deferredKind;

  /// Score of the deferred candidate.
  double deferredScore = 0;

  /// End of the last loud block when the deferred candidate came (WP151).
  int deferredLoud = -1;

  /// Score of the candidate whose check runs.
  double checkedScore = 0;

  /// [pendingLoud] of the check that runs (`-1`: cut at the latest speech).
  int checkedLoud = -1;

  /// Forgets everything.
  void clear() {
    pendingAt = -1;
    pendingKind = deferredKind = null;
    pendingScore = deferredScore = checkedScore = 0;
    pendingLoud = deferredLoud = checkedLoud = -1;
  }

  /// A candidate [kind] with [score]; the check may start at [at] (kept if a
  /// pending one is already waiting).
  void addPending(BargeInKeyword kind, double score, int at) {
    pendingKind = kind;
    if (score > pendingScore) pendingScore = score;
    if (pendingAt < 0) pendingAt = at;
  }

  /// A candidate during a check or cooldown: the window follows the strongest
  /// one, a weaker later one must not push it back.
  void defer(BargeInKeyword kind, double score, int fed, int lastLoud) {
    if (deferredKind == null || score > deferredScore) {
      deferredAt = fed;
      deferredLoud = lastLoud;
    }
    deferredKind = kind;
    if (score > deferredScore) deferredScore = score;
  }

  /// The word of a deferred candidate goes on until [settle] samples after it.
  void follow(int fed, int lastLoud, int settle) {
    if (deferredKind != null && fed <= deferredAt + settle) {
      deferredLoud = lastLoud;
    }
  }

  /// Takes the deferred candidate after the cooldown: pending again if its
  /// word is still inside the clip ([clip] samples).
  void promoteAfterCooldown(int fed, int clip, int settle) {
    final kind = deferredKind;
    if (kind == null) return;
    final score = deferredScore;
    final loud = deferredLoud;
    deferredKind = null;
    deferredScore = 0;
    deferredLoud = -1;
    if (fed - deferredAt > clip) return;
    final after = deferredAt + settle;
    // A pending candidate (a stronger one, cut at the latest speech) keeps
    // its own cut; the older word end must not replace it.
    final waiting = pendingKind != null;
    addPending(kind, score, after > fed ? after : fed);
    // Keep the end of its word (as after a reject): the check cuts there.
    if (loud > 0 && !waiting) pendingLoud = loud;
  }

  /// Takes the pending candidate to check it; its score and word position
  /// move to [checkedScore] and [checkedLoud].
  BargeInKeyword takePending() {
    final kind = pendingKind!;
    pendingAt = -1;
    pendingKind = null;
    checkedScore = pendingScore;
    pendingScore = 0;
    checkedLoud = pendingLoud;
    pendingLoud = -1;
    return kind;
  }

  /// After a rejected check: a candidate that came meanwhile is pending again
  /// at the end of the cooldown ([blockedUntil]), a clearly stronger one
  /// ([margin]) after its own [settle]. It is not lost while its word is
  /// still in the ring ([ring] samples, WP151); returns `false` if it was
  /// and is dropped.
  bool rescheduleAfterReject({
    required int fed,
    required int blockedUntil,
    required int settle,
    required int ring,
    required double margin,
  }) {
    final kind = deferredKind;
    if (kind == null) return true;
    final score = deferredScore;
    final loud = deferredLoud;
    deferredKind = null;
    deferredScore = 0;
    deferredLoud = -1;
    var at = blockedUntil > fed ? blockedUntil : fed;
    if (score > checkedScore + margin) {
      final own = deferredAt + settle;
      at = own > fed ? own : fed;
    }
    if (loud <= 0 || loud <= fed - ring) return false;
    addPending(kind, score, at);
    pendingAt = at;
    pendingLoud = loud;
    return true;
  }
}
