import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What was detected while the answer is spoken.
enum BargeInKind {
  /// A keyword: [BargeInKeyword] tells which.
  keyword,

  /// Free speech of the user (experimental).
  speech,
}

/// The keywords that interrupt the speech output (concept K23 c).
enum BargeInKeyword {
  /// „Wendelin“: a new utterance follows.
  wake,
}

/// One detection, e.g. the user said „Wendelin“.
@immutable
final class BargeInSignal {
  /// A keyword detection. [preRoll] is the audio just before and
  /// including the keyword, if the detector has it.
  const BargeInSignal.keyword(BargeInKeyword this.keyword, {this.preRoll})
    : kind = BargeInKind.keyword;

  /// Free speech detected. [preRoll] is the audio from its start, if known.
  const BargeInSignal.speech({this.preRoll})
    : kind = BargeInKind.speech,
      keyword = null;

  /// Kind of the signal.
  final BargeInKind kind;

  /// The keyword (`null` for [BargeInKind.speech]).
  final BargeInKeyword? keyword;

  /// Optional 16 kHz mono PCM that precedes the detection.
  final Int16List? preRoll;

  /// Diagnostics code without any content (`keyword-wake`,
  /// `speech`).
  String get code => keyword == null ? kind.name : 'keyword-${keyword!.name}';

  @override
  String toString() => 'BargeInSignal($code)';
}

/// Detects the user interrupting the speech output (port, K23 c).
///
/// The app implements it (wake word model from WP58, echo cancellation and
/// the audio source are its business); the pipeline only starts it while the
/// answer is spoken and reacts to [signals].
abstract interface class BargeInDetector {
  /// Broadcast stream of detections. Only delivers while [start]ed.
  Stream<BargeInSignal> get signals;

  /// Whether the detector is listening.
  bool get isRunning;

  /// Starts listening (the answer is being spoken). Idempotent.
  Future<void> start();

  /// Stops listening and releases the microphone. Idempotent.
  Future<void> stop();
}

/// A [BargeInDetector] that wants the text being read aloud (WP113): the
/// pipeline reports every sentence that starts playing, so the detector can
/// tell the own voice from the user.
abstract interface class SpokenTextSink {
  /// [sentence] started playing.
  void spoke(String sentence);
}
