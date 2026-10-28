import 'dev_clips.dart';

/// Lowest stage 1 classifier score of a near miss (WP155). Below the verify
/// limit 0.98 of the band; the collection starts where the classifier's
/// output stops being background noise. No rate of the v8 classifier at 0.5
/// was measured before WP155; reference points: v7 at 0.5 about 58..68
/// candidates per hour in speech (station spike), templates at 0.85 2.8 per
/// hour, speech alone at the template limit 0.40 88 per hour. The first
/// guess is therefore tens per hour in speech and near 0 in a quiet room;
/// the minimum spacing of `WakeShadowRun` bounds it to 720 per hour at worst
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
