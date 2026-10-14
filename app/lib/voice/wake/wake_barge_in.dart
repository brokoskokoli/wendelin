import 'dart:async';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice_log.dart';

/// Barge-in detector of the conversation mode (WP50, WP44 Nachtrag 2):
/// while the answer is spoken it listens for „Wendelin“ with the same
/// feature chain and the personal templates as the idle wake word, only
/// stricter ([extraMargin] on every threshold; the own voice from the
/// speaker is the main false trigger). Stage 2 does not run (Whisper is
/// busy speaking along the answer).
///
/// The engine is built at the first [start]: the templates are read then,
/// not when the overlay opens. Without a learned voice the detector stays
/// silent (barge-in by a tap on the microphone still works).
final class LazyWakeBargeInDetector implements BargeInDetector {
  /// Creates the detector on [audio] (the capture profile follows the
  /// pipeline state, see `CaptureProfileFollower`).
  LazyWakeBargeInDetector({
    required this.audio,
    required this.templates,
    required this.features,
    this.extraMargin = 0.05,
  });

  /// Microphone shared with the pipeline.
  final AudioInput audio;

  /// Templates of all learned voices.
  final Future<List<WakeTemplates>> Function() templates;

  /// A new feature chain.
  final WakeFeatureExtractor Function() features;

  /// Added to every template threshold.
  final double extraMargin;

  WakeWordBargeInDetector? _inner;
  bool _empty = false;
  bool _running = false;
  StreamSubscription<BargeInSignal>? _sub;
  final _signals = StreamController<BargeInSignal>.broadcast(sync: true);

  @override
  Stream<BargeInSignal> get signals => _signals.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    if (_inner == null && !_empty) {
      final sets = await templates();
      if (sets.isEmpty) {
        _empty = true;
        voiceLog('barge-in-off', {'reason': 'no-templates'});
      } else {
        final strict = [
          for (final t in sets)
            t.withThreshold((t.threshold + extraMargin).clamp(0.0, 0.99)),
        ];
        final inner = WakeWordBargeInDetector(
          audio: audio,
          engine: CandidateWakeEngine(
            features: features(),
            templates: strict.first,
            moreTemplates: strict.skip(1).toList(),
            modelThreshold: null,
          ),
        );
        _sub = inner.signals.listen(_signals.add);
        _inner = inner;
      }
    }
    // A stop during the loading wins.
    if (_running) await _inner?.start();
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _inner?.stop();
  }

  /// Ends the detector for good.
  Future<void> dispose() async {
    _running = false;
    await _sub?.cancel();
    await _inner?.dispose();
    await _signals.close();
  }
}
