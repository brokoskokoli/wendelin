import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which stage a [VoiceMetric] measures.
enum VoiceMetricKind {
  /// Speech recognition of one utterance.
  stt,

  /// Speech output of one answer (offline voice).
  tts,
}

/// Latency, real-time factor and memory of one utterance (WP103, for the
/// device test). Only ids and numbers, never content.
final class VoiceMetric {
  /// Creates a measurement.
  const VoiceMetric({
    required this.kind,
    required this.model,
    required this.audio,
    required this.compute,
    this.rssBytes,
  });

  /// Stage.
  final VoiceMetricKind kind;

  /// Catalog id of the model (voice id for speech output).
  final String model;

  /// Length of the audio (recording or synthesised speech).
  final Duration audio;

  /// Compute time: from handing over the audio to the text (STT), from the
  /// text to the audio (TTS). This is the latency of the stage.
  final Duration compute;

  /// Resident memory of the process after the run; `null` = unknown.
  final int? rssBytes;

  /// Compute time per audio time (real-time factor, smaller is faster).
  double get rtf => audio == Duration.zero
      ? 0
      : compute.inMicroseconds / audio.inMicroseconds;
}

/// Resident memory of the process now; `null` where the platform has none.
int? currentRssBytes() {
  try {
    return ProcessInfo.currentRss;
  } on Object {
    return null;
  }
}

/// The last measurements of this engine, newest first.
class VoiceMetricsLog extends Notifier<List<VoiceMetric>> {
  /// How many measurements are kept.
  static const capacity = 30;

  @override
  List<VoiceMetric> build() => const [];

  /// Adds a measurement.
  void add(VoiceMetric metric) =>
      state = [metric, ...state].take(capacity).toList(growable: false);

  /// Clears the list.
  void clear() => state = const [];
}

/// Measurements per utterance for the metrics screen.
final voiceMetricsProvider =
    NotifierProvider<VoiceMetricsLog, List<VoiceMetric>>(VoiceMetricsLog.new);
