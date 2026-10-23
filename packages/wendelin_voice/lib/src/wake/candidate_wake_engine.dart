import 'dart:typed_data';

import 'keyword_spec.dart';
import 'speech_gate.dart';
import 'wake_feature_extractor.dart';
import 'wake_math.dart';
import 'wake_templates.dart';
import 'wake_word_engine.dart';

/// Stage 1 of the two-stage detection (WP44 Nachtrag 2): a candidate arises
/// when the classifier is above a **low** threshold or a window is similar
/// to a personal template. Stage 2 (transcription) confirms.
final class CandidateWakeEngine implements WarmableWakeEngine {
  /// Creates the engine. [templates] may be `null` (classifier only);
  /// templates of another [WakeFeatureExtractor.featureVersion] are ignored.
  /// [modelThreshold] `null` disables the classifier rule. [refractory]
  /// suppresses further candidates after one.
  CandidateWakeEngine({
    required this.features,
    this.templates,
    this.moreTemplates = const [],
    this.modelThreshold = 0.5,
    this.refractory = const Duration(milliseconds: 1500),
    this.keywordId = 'wake',
    this.onWindow,
    this.silenceFloor,
    this.directThreshold,
    this.holdWindows = 0,
    this.dropsToEnd = 1,
  }) : assert(dropsToEnd >= 1, 'dropsToEnd muss >= 1 sein');

  /// The feature chain.
  final WakeFeatureExtractor features;

  /// Personal templates.
  final WakeTemplates? templates;

  /// Templates of further speakers (WP50: all learned voices); each set
  /// keeps its own threshold.
  final List<WakeTemplates> moreTemplates;

  /// Low classifier threshold (rule a).
  final double? modelThreshold;

  /// Pause after a candidate.
  final Duration refractory;

  /// Id of the reported keyword.
  final String keywordId;

  /// WP129 (WP126 Folgepunkt b): no main-word hit unless the recent audio
  /// held at least a minimum level (absolute, see
  /// `WakeClassifierRules.silenceFloorRms`), whichever rule fired. Template
  /// embeddings look like the templates in digital silence **and** in a
  /// quiet room (similarity 0.82..0.89 over the threshold 0.75), so a silent
  /// stream after a warm start would otherwise be a candidate. It is no
  /// speech detector: the ratio to the noise floor is not used (a late
  /// decision of a real call must not be lost). `null`: no level check.
  final SpeechGate? silenceFloor;

  /// WP129: a classifier score at or above this value is a sure hit
  /// (`WakeWordHit.direct`, no stage 2). `null`: every hit goes to stage 2.
  final double? directThreshold;

  /// WP129: from the first window in the band (at or above [modelThreshold],
  /// below [directThreshold]) the classifier score is held for up to this many
  /// windows and the event is decided with its **peak**: when the score falls
  /// below the peak, or at the limit. A score at or above [directThreshold]
  /// decides at once. `0` (or no [directThreshold]): the first window decides.
  /// [holdWindows] counts all windows from the first one in the band, also the
  /// ones that fell.
  final int holdWindows;

  /// WP129: the hold ends after this many **consecutive** windows below the
  /// peak (a null/NaN score counts as below); a window at or above the peak
  /// resets the count. `1`: the first fall ends it. A single dip between two
  /// high windows (0.9917, 0.9892, 0.998) is no end with `2`.
  final int dropsToEnd;

  /// Diagnostics (WP72): called for every window with the best similarity to
  /// the main templates (`-1` without templates) and the classifier score.
  final void Function(double main, double? model)? onWindow;

  bool _open = false;
  int _lastHit = -1 << 40;

  /// Largest classifier score and template similarity seen so far
  /// (diagnostics, e.g. for calibration screens).
  double maxModelScore = 0, maxSimilarity = -1;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {
    if (_open) throw StateError('Engine bereits offen');
    if (!keywords.any((k) => k.id == keywordId)) {
      throw ArgumentError('Schlüsselwort $keywordId fehlt');
    }
    await features.open();
    _open = true;
  }

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    if (!_open) throw StateError('Engine nicht offen');
    final usable = _usable(
      templates == null ? moreTemplates : [templates!, ...moreTemplates],
    );
    final hits = <WakeWordHit>[];
    silenceFloor?.feed(frame);
    for (final w in await features.accept(frame)) {
      if (w.modelScore != null && w.modelScore! > maxModelScore) {
        maxModelScore = w.modelScore!;
      }
      // The speaker whose similarity is closest above the own threshold
      // decides (no speaker: only the classifier rule).
      final score = _eventScore(w.modelScore);
      final main = _closest(w.embedding, usable);
      if (main.top > maxSimilarity) maxSimilarity = main.top;
      var d = decideCandidate(
        modelScore: score,
        templateSimilarity: main.similarity,
        modelThreshold: modelThreshold,
        templateThreshold: main.threshold,
      );
      if (d != null && silenceFloor != null && !silenceFloor!.active) d = null;
      onWindow?.call(main.top, w.modelScore);
      final gap = (refractory.inMicroseconds * 16000) ~/ 1000000;
      if (d == null || w.endSample - _lastHit < gap) continue;
      _lastHit = w.endSample;
      hits.add(
        WakeWordHit(
          keywordId: keywordId,
          endSample: w.endSample,
          confidence: d.confidence,
          reason: d.reason.name,
          score: score,
          direct:
              d.reason != CandidateReason.template &&
              directThreshold != null &&
              (score ?? 0) >= directThreshold!,
        ),
      );
    }
    return hits;
  }

  double? _peak;
  int _heldCount = 0;
  int _drops = 0;

  /// The score the rules see: the raw one, or with [holdWindows] the peak of
  /// the event once it is decided (`null` while the event is still held).
  double? _eventScore(double? rawScore) {
    // Fail-closed: NaN is no score (never a peak, never a hit).
    final score = rawScore != null && rawScore.isNaN ? null : rawScore;
    final lower = modelThreshold, upper = directThreshold;
    if (holdWindows <= 0 || lower == null || upper == null) return score;
    final peak = _peak;
    if (peak == null) {
      if (score == null || score < lower || score >= upper) return score;
      _peak = score;
      _heldCount = 1;
      _drops = 0;
      return _heldCount >= holdWindows ? _release() : null;
    }
    if (score != null && score >= upper) {
      _peak = null;
      return score;
    }
    _heldCount++;
    if (score != null && score >= peak) {
      _peak = score;
      _drops = 0;
    } else {
      _drops++;
    }
    return _drops >= dropsToEnd || _heldCount >= holdWindows
        ? _release()
        : null;
  }

  double _release() {
    final peak = _peak!;
    _peak = null;
    return peak;
  }

  List<WakeTemplates> _usable(List<WakeTemplates> sets) => [
    for (final t in sets)
      if (t.isCompatible(features.featureVersion)) t,
  ];

  ({double? similarity, double? threshold, double margin, double top}) _closest(
    Float32List embedding,
    List<WakeTemplates> sets,
  ) {
    double? sim, threshold;
    var margin = double.negativeInfinity, top = -1.0;
    for (final t in sets) {
      final s = bestSimilarity(embedding, t.embeddings);
      if (s > top) top = s;
      if (s - t.threshold > margin) {
        margin = s - t.threshold;
        sim = s;
        threshold = t.threshold;
      }
    }
    return (similarity: sim, threshold: threshold, margin: margin, top: top);
  }

  @override
  Future<void> warmUp(Int16List frame) async {
    if (!_open) throw StateError('Engine nicht offen');
    // Windows are dropped: the earlier audio only fills the chain.
    await features.accept(frame);
  }

  @override
  void reset() {
    features.reset();
    silenceFloor?.reset();
    _lastHit = -1 << 40;
    _peak = null;
    _heldCount = 0;
    _drops = 0;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await features.close();
  }
}
