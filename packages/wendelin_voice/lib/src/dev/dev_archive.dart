import 'dev_clips.dart';

/// Lowest stage 1 classifier score of a near miss (WP155). Below the verify
/// limit 0.98 of the band; the collection starts where the classifier's
/// output stops being background noise. No rate of the v8 classifier at 0.5
/// was measured before WP155; reference points: v7 at 0.5 about 58..68
/// candidates per hour in speech (station spike), templates at 0.85 2.8 per
/// hour, speech alone at the template limit 0.40 88 per hour. The first
/// guess is therefore tens per hour in speech and near 0 in a quiet room;
/// the cap [NearMissTracker.minSpacing] bounds it to 720 per hour at worst
/// and the real rate is read from the archive (`index.jsonl`).
const devNearMissFrom = 0.5;

/// What the archive hands to the app (WP155): one finished case.
final class DevArchiveEntry {
  /// Creates an entry.
  const DevArchiveEntry({
    required this.at,
    required this.source,
    required this.outcome,
    required this.meta,
    this.cand,
    this.verify,
  });

  /// Moment of the case.
  final DateTime at;

  /// `idle` or `barge`.
  final String source;

  /// `accepted`, `rejected`, `dropped` or `near-miss`.
  final String outcome;

  /// Numbers and codes of the case (scores, thresholds, verifier, text).
  final Map<String, Object?> meta;

  /// Audio around the candidate; `null` if none could be collected.
  final DevClip? cand;

  /// Audio the check heard, if there was one.
  final DevClip? verify;
}

/// The archive side of [DevClips] (WP155): where finished cases go and the
/// static facts every case carries.
final class DevArchive {
  /// Creates the hook.
  const DevArchive({
    required this.write,
    this.context = _none,
    this.takeStt = _none,
  });

  /// Takes a finished case (must not block, errors are swallowed).
  final void Function(DevArchiveEntry entry) write;

  /// Facts every case of a [source] carries (app version, thresholds, mode).
  final Map<String, Object?> Function(String source) context;

  /// The transcript of the check that just ran (`text`, `lp`, `model`) and
  /// forgets it; empty if there was none. Called before a check (to clear)
  /// and after it.
  final Map<String, Object?> Function() takeStt;

  static Map<String, Object?> _none([String _ = '']) => const {};
}

/// One case on its way to the archive (WP155): the clip fills in later
/// ([DevAround] collects the audio after the candidate), the outcome when
/// the check is over; the entry goes out once, when both are there.
final class DevArchiveCase {
  /// Starts a case of [source].
  DevArchiveCase(this._archive, {required this.source, DateTime? at})
    : at = at ?? DateTime.now();

  final DevArchive _archive;

  /// `idle` or `barge`.
  final String source;

  /// Moment of the candidate.
  final DateTime at;

  /// Fields of the case; set before [finish].
  final Map<String, Object?> meta = {};

  DevClip? _cand, _verify;
  bool _clipDone = false;
  String? _outcome;
  bool _sent = false;

  /// Whether [finish] was called.
  bool get finished => _outcome != null;

  /// Gives the audio around the candidate.
  void clip(DevClip c) {
    _cand = c;
    _clipDone = true;
    _tryWrite();
  }

  /// No clip comes (collectors are full, the mode went off, the stream
  /// ended): the entry goes without audio.
  void giveUpClip() {
    _clipDone = true;
    _tryWrite();
  }

  /// Audio the check heard.
  void verifyClip(DevClip c) => _verify = c;

  /// Ends the case with [outcome]; the first call wins.
  void finish(String outcome, [Map<String, Object?> extra = const {}]) {
    if (_outcome != null) return;
    _outcome = outcome;
    meta.addAll(extra);
    _tryWrite();
  }

  void _tryWrite() {
    if (_sent || _outcome == null || !_clipDone) return;
    _sent = true;
    try {
      _archive.write(
        DevArchiveEntry(
          at: at,
          source: source,
          outcome: _outcome!,
          meta: {..._archive.context(source), ...meta},
          cand: _cand,
          verify: _verify,
        ),
      );
    } on Object {
      // Never into the voice path.
    }
  }
}

/// A near miss: the peak of an utterance the classifier rated between
/// [devNearMissFrom] and the verify limit.
final class NearMiss {
  /// Creates a near miss.
  const NearMiss({required this.peakEnd, required this.peak, required this.ms});

  /// Stream position of the peak window.
  final int peakEnd;

  /// The peak score.
  final double peak;

  /// Time the score stayed at or above the floor, in ms.
  final int ms;
}

/// Turns the stream of window scores into **one** near miss per utterance
/// (WP155). A run starts with a score at or above [from] and ends when
/// [gap] samples pass without one; a score at or above [above] (a real
/// candidate, or the rise and fall around it) voids the whole run. The
/// peak window is the hit. After a near miss the next one is accepted only
/// [minSpacing] later (TV noise must not fill the archive).
final class NearMissTracker {
  /// Creates the tracker.
  NearMissTracker({
    this.from = devNearMissFrom,
    required this.above,
    this.gap = 16000,
    this.minSpacing = 80000,
  });

  /// Floor of a near miss.
  final double from;

  /// Verify limit: at or above it the window is a candidate.
  final double above;

  /// Samples without a score at or above [from] that end a run (1 s).
  final int gap;

  /// Samples between two near misses (5 s).
  final int minSpacing;

  bool _open = false;
  bool _void = false;
  int _start = 0, _lastAbove = 0, _peakEnd = 0, _lastSent = -1 << 40;
  double _peak = 0;

  /// Forgets the run (new stream).
  void reset() {
    _open = false;
    _void = false;
    _lastSent = -1 << 40;
  }

  /// A window ending at [end] with [score]; returns the near miss of a run
  /// that just ended, else `null`. NaN counts as no score.
  NearMiss? onScore(int end, double score) {
    NearMiss? done;
    if (_open && end - _lastAbove >= gap) done = _close();
    if (score.isNaN || score < from) return done;
    if (!_open) {
      _open = true;
      _void = false;
      _start = end;
      _peak = score;
      _peakEnd = end;
    } else if (score >= _peak) {
      _peak = score;
      _peakEnd = end;
    }
    _lastAbove = end;
    if (score >= above) _void = true;
    return done;
  }

  NearMiss? _close() {
    _open = false;
    if (_void || _peakEnd - _lastSent < minSpacing) return null;
    _lastSent = _peakEnd;
    return NearMiss(
      peakEnd: _peakEnd,
      peak: _peak,
      ms: (_lastAbove - _start) ~/ 16,
    );
  }
}
