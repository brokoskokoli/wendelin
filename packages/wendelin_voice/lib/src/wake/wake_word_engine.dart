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
