import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'keyword_spec.dart';

/// A keyword hit of a [WakeWordEngine] (stage 1: a candidate).
@immutable
final class WakeWordHit {
  /// Creates a hit.
  const WakeWordHit({
    required this.keywordId,
    required this.endSample,
    this.confidence,
    this.reason,
    this.score,
    this.direct = false,
    this.holdMs,
  });

  /// Id of the [KeywordSpec] (`wake`, `stop`).
  final String keywordId;

  /// Position in the stream (samples since the last `reset`) at which the
  /// engine decided.
  final int endSample;

  /// 0..1 if the engine provides one.
  final double? confidence;

  /// Diagnostics: which rule fired (`model`, `template`, `both`), no content.
  final String? reason;

  /// WP129: classifier score of the window (`null` without classifier).
  final double? score;

  /// WP129: a sure hit (classifier at or above the accept limit): the
  /// listener skips stage 2.
  final bool direct;

  /// WP141: how long the engine held the score before deciding, in ms
  /// (decision window minus first window in the band; `0` for an immediate
  /// decision, `null` without hold). [endSample] is the peak window.
  final int? holdMs;

  @override
  String toString() => 'WakeWordHit($keywordId, @$endSample, $confidence)';
}

/// Keyword detection on a PCM stream (port). The app implements it with the
/// shared onnxruntime (WP50); [CandidateWakeEngine] is the pure-Dart
/// decision part on top of a [WakeFeatureExtractor].
///
/// Contract (`wakeWordEngineContract`): [accept] before [open] or after
/// [close] throws `StateError`; [open] twice throws `StateError`; [reset]
/// forgets the stream (positions restart at 0); [close] is idempotent.
abstract interface class WakeWordEngine {
  /// Opens the engine for [keywords].
  Future<void> open(List<KeywordSpec> keywords);

  /// Feeds one 16 kHz mono frame and returns the hits it completed.
  Future<List<WakeWordHit>> accept(Int16List frame);

  /// Starts a new stream.
  void reset();

  /// Releases the engine. Idempotent.
  Future<void> close();
}

/// WP123: an engine that can be primed with earlier audio (the feature chain
/// needs ~2 s before the first window; a barge-in that starts cold would
/// miss the first words of the answer).
abstract interface class WarmableWakeEngine implements WakeWordEngine {
  /// Feeds [frame] into the feature chain only: no window is rated, no hit
  /// or decision state changes. Call after [reset], before the live frames.
  Future<void> warmUp(Int16List frame);
}

/// WP155: an engine that reports the classifier score of every window (the
/// developer mode collects near misses from it). Reporting changes no
/// decision.
abstract interface class ScoringWakeEngine implements WakeWordEngine {
  /// Called with the window end (stream position) and its raw classifier
  /// score; `null` switches reporting off. Must not throw into the engine.
  set scoreSink(void Function(int endSample, double score)? sink);
}

/// WP171: what the engine knows about one window, for the developer mode.
/// [model] is the raw classifier score, [margin] the template similarity
/// minus the threshold of the set with the largest margin ([similarity] and
/// [threshold] are that set's values); each is `null` when its recognizer
/// did not rate the window (no classifier, no templates). [primaryModel] says
/// which recognizer decides; the other one is the shadow.
typedef WakeWindowScores = ({
  int endSample,
  double? model,
  double? similarity,
  double? threshold,
  double? margin,
  bool primaryModel,
});

/// WP171: an engine that rates every window with **both** stage 1
/// recognizers (templates and trained model) on one feature chain and
/// reports it. Only the set one decides; the other one (the shadow) never
/// triggers. Reporting changes no decision and is computed only while a
/// sink is set.
abstract interface class ShadowScoringWakeEngine implements ScoringWakeEngine {
  /// Called per window; `null` switches reporting off. Must not throw into
  /// the engine.
  set windowSink(void Function(WakeWindowScores window)? sink);
}
