import 'dart:async';

import '../io/barge_in_detector.dart';
import 'voice_events.dart';

/// Starts and stops the barge-in detector with the pipeline state, one
/// operation after the other: a stop never overtakes a start, a late start
/// is stopped again.
class BargeDetectorSync {
  BargeDetectorSync({
    required this.detector,
    required this.enabled,
    required this.state,
    required this.onError,
  });

  final BargeInDetector? Function() detector;
  final bool Function() enabled;
  final VoiceState Function() state;
  final void Function(Object error) onError;

  Future<void> _ops = Future.value();

  /// Completes when all queued start/stop operations are done.
  Future<void> get settled => _ops;

  void sync(VoiceState s) {
    final d = detector();
    if (d == null || !enabled()) return;
    if (s == VoiceState.speaking) {
      _ops = _ops.then((_) async {
        try {
          await d.start();
        } on Object catch (e) {
          onError(e);
        }
        final now = state();
        if (now != VoiceState.speaking && now != VoiceState.thinking) {
          await _stop(d);
        }
      });
    } else if (s != VoiceState.thinking) {
      _ops = _ops.then((_) => _stop(d));
    }
  }

  Future<void> _stop(BargeInDetector d) async {
    try {
      await d.stop();
    } on Object catch (_) {}
  }
}
