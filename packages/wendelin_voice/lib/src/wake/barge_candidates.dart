import '../io/barge_in_detector.dart';

/// Bookkeeping of the candidates of [WakeWordBargeInDetector]: the one that
/// waits for the end of its word (pending), the best one that came during a
/// check or the cooldown (deferred) and the one being checked (checked).
/// Positions are sample indices of the fed audio; `-1` means none.
final class BargeCandidates {
  /// Position at which the pending check may start.
  int pendingAt = -1;

  /// The pending candidate: kind, score and the end of its own word belong
  /// together (WP151), so the cut of a check can never come from another
  /// candidate. `null`: none waits.
  PendingCandidate? pending;

  /// Kind of the pending candidate, `null`: none.
  BargeInKeyword? get pendingKind => pending?.kind;

  /// Best score of the pending candidate.
  double get pendingScore => pending?.score ?? 0;

  /// End of the loud word of the pending candidate (`-1`: cut at the latest
  /// speech).
  int get pendingLoud => pending?.loud ?? -1;

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
    pending = null;
    deferredKind = null;
    deferredScore = checkedScore = 0;
    deferredLoud = checkedLoud = -1;
  }

  /// A candidate [kind] with [score]; the check may start at [at] (kept if a
  /// pending one is already waiting). [loud] is the end of its word (`-1`:
  /// the latest speech). The pending candidate is the strongest one: only a
  /// stronger one takes over its score and cut, a weaker one keeps both.
  void addPending(BargeInKeyword kind, double score, int at, {int loud = -1}) {
    final old = pending;
    final takeOver = old == null || score > old.score;
    pending = PendingCandidate(
      kind,
      takeOver ? score : old.score,
      takeOver ? loud : old.loud,
    );
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
    // A stronger pending candidate keeps its own cut (see [addPending]).
    addPending(
      kind,
      score,
      after > fed ? after : fed,
      loud: loud > 0 ? loud : -1,
    );
  }

  /// Takes the pending candidate to check it; its score and word position
  /// move to [checkedScore] and [checkedLoud].
  BargeInKeyword takePending() {
    final p = pending!;
    pendingAt = -1;
    pending = null;
    checkedScore = p.score;
    checkedLoud = p.loud;
    return p.kind;
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
    addPending(kind, score, at, loud: loud);
    pendingAt = at;
    return true;
  }
}

/// A waiting candidate: [kind], best [score] and [loud], the end of its word
/// (`-1`: cut at the latest speech).
final class PendingCandidate {
  /// Creates a pending candidate.
  const PendingCandidate(this.kind, this.score, this.loud);

  /// Kind of the keyword.
  final BargeInKeyword kind;

  /// Best score.
  final double score;

  /// End of the word, `-1`: latest speech.
  final int loud;
}
