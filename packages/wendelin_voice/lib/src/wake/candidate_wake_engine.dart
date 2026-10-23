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
    this.holdDuration = Duration.zero,
  });

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
  /// embeddings looked like the templates in digital silence **and** in a
  /// quiet room (raw cosine 0.82..0.89 over the threshold 0.75; since WP134
  /// the cosine is centered and the gap is wide, this stays as a safety net),
  /// so a silent stream after a warm start would otherwise be a candidate.
  /// It is no
  /// speech detector: the ratio to the noise floor is not used (a late
  /// decision of a real call must not be lost). `null`: no level check.
  final SpeechGate? silenceFloor;

  /// WP129: a classifier score at or above this value is a sure hit
  /// (`WakeWordHit.direct`, no stage 2). `null`: every hit goes to stage 2.
  final double? directThreshold;

  /// WP141: from the first window in the band (at or above [modelThreshold],
  /// below [directThreshold]) the classifier score is held until the stream
  /// position has advanced by this much (`endSample - first endSample >= W`,
  /// inclusive: the window exactly at +W still counts and decides). Falls
  /// below the peak or below the band, and null/NaN scores, do not end the
  /// hold. A score at or above [directThreshold] decides at once (direct).
  /// Otherwise the **peak** decides at the end of W; the hit time
  /// (`WakeWordHit.endSample`) is the peak window, so the stage 2 clip lies
  /// around the peak. Of equal scores the later window is the peak.
  /// [Duration.zero] (or no [directThreshold]): the first window decides.
  /// The same rule is replicated in `tool/train_wake_word/stage2_cut.py`
  /// (`app_events`), parity fixture `test/fixtures/wake_hold_parity.json`.
  final Duration holdDuration;

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
      final ev = _eventScore(w.modelScore, w.endSample);
      final score = ev.score;
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
      // The lock runs from the hit time (the peak), also for the next hit.
      if (d == null || ev.end - _lastHit < gap) continue;
      _lastHit = ev.end;
      hits.add(
        WakeWordHit(
          keywordId: keywordId,
          endSample: ev.end,
          holdMs: ev.holdSamples == null ? null : ev.holdSamples! ~/ 16,
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

  int? _holdStart;
  double _peak = 0;
  int _peakEnd = 0;

  /// The score the rules see: the raw one, or with [holdDuration] the peak of
  /// the event once it is decided (`score == null` while it is still held).
  _Scored _eventScore(double? rawScore, int end) {
    // Fail-closed: NaN is no score (never a peak, never a hit).
    final score = rawScore != null && rawScore.isNaN ? null : rawScore;
    final lower = modelThreshold, upper = directThreshold;
    final holdSamples = (holdDuration.inMicroseconds * 16000) ~/ 1000000;
    if (holdSamples <= 0 || lower == null || upper == null) {
      return _Scored(score, end, null);
    }
    final start = _holdStart;
    if (start == null) {
      if (score == null || score < lower || score >= upper) {
        return _Scored(score, end, 0);
      }
      _holdStart = end;
      _peak = score;
      _peakEnd = end;
      return _Scored(null, end, null);
    }
    if (score != null && score >= upper) {
      _holdStart = null;
      return _Scored(score, end, end - start);
    }
    if (score != null && score >= _peak) {
      _peak = score;
      _peakEnd = end;
    }
    if (end - start < holdSamples) return _Scored(null, end, null);
    _holdStart = null;
    return _Scored(_peak, _peakEnd, end - start);
  }

  List<WakeTemplates> _usable(List<WakeTemplates> sets) => [
    for (final t in sets)
      if (t.isCompatible(features.featureVersion, center: features.centerId)) t,
  ];

  ({double? similarity, double? threshold, double margin, double top}) _closest(
    Float32List embedding,
    List<WakeTemplates> sets,
  ) {
    double? sim, threshold;
    var margin = double.negativeInfinity, top = -1.0;
    for (final t in sets) {
      final s = bestSimilarity(
        embedding,
        t.embeddings,
        mean: features.embeddingMean,
      );
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
    _holdStart = null;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await features.close();
  }
}

/// Result of the hold rule for one window: [score] (null while held), the
/// hit time [end] (peak window when released) and the held span in samples.
final class _Scored {
  const _Scored(this.score, this.end, this.holdSamples);
  final double? score;
  final int end;
  final int? holdSamples;
}
