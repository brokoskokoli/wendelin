import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/dev_archive.dart';
import '../../voice/dev_audio.dart';
import '../../voice/dev_log.dart';
import '../../voice/voice_log.dart';
import 'wake_detector.dart';
import 'wake_stage2_gap.dart';

/// Audio before the wake word end handed to the overlay: the word (up to
/// about a second) and room noise before it.
const wakePreRoll = Duration(milliseconds: 2500);

/// Manages cleaning after developer mode is toggled off (WP148, WP155).
final class WakeDevSweeper {
  int _devGen = 0;
  Future<void>? _sweep;

  /// Completes when the last cleaning after "off" is over (tests).
  Future<void> get sweepIdle => _sweep ?? Future<void>.value();

  /// Applied on engine startup.
  void onRun({required bool dev}) {
    devLogEnabled = dev;
    _devGen++;
    unawaited(cleanDevAudio());
  }

  /// Applied on developer mode channel calls.
  void onDevMode({
    required bool on,
    required bool clear,
    required bool archive,
  }) {
    devLogEnabled = on;
    _devGen++;
    if (!on && clear) {
      _sweep = _sweepAfterOff(deleteArchive: archive);
      unawaited(_sweep);
    }
  }

  /// After the developer mode went off: waits for the writes of this
  /// isolate, then deletes (unless the mode came back on meanwhile).
  Future<void> _sweepAfterOff({required bool deleteArchive}) async {
    final gen = _devGen;
    bool stale() => devLogEnabled || gen != _devGen;
    await devArchiveIdle;
    await devAudioIdle;
    if (stale()) return;
    await deleteDevAudio();
    if (deleteArchive && !stale()) await clearDevArchive();
  }
}

/// Logs every stage 1 candidate: score and rule, nothing else.
final class LoggingWakeEngine
    implements WakeWordEngine, ShadowScoringWakeEngine {
  LoggingWakeEngine(this.inner, this.detector, {required this.verify});

  final WakeWordEngine inner;
  final WakeDetector detector;

  /// Whether stage 2 runs (else a candidate below `acceptFrom` goes on
  /// `unchecked`).
  final bool verify;

  @override
  Future<void> open(List<KeywordSpec> keywords) => inner.open(keywords);

  // WP155: the window scores of the inner engine go to the listener.
  @override
  set scoreSink(void Function(int endSample, double score)? sink) {
    if (inner case final ScoringWakeEngine e) e.scoreSink = sink;
  }

  // WP171: both detectors' view of each window.
  @override
  set windowSink(void Function(WakeWindowScores window)? sink) {
    if (sink != null) return attachWindowSink(inner, sink);
    switch (inner) {
      case final ShadowScoringWakeEngine e:
        e.windowSink = null;
      case final ScoringWakeEngine e:
        e.scoreSink = null;
      default:
    }
  }

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final hits = await inner.accept(frame);
    for (final h in hits) {
      voiceLog('wake-cand', {
        'stage': 1,
        'detector': detector.name,
        'score': (h.score ?? h.confidence ?? 0).toStringAsFixed(3),
        'rule': h.reason,
        'direct': h.direct,
      });
      // WP141: how long stage 1 held the score and where the candidate goes
      // on; also for candidates stage 2 rejects later (`wake-verify`).
      voiceLog('wake-decision', {
        'hold_ms': h.holdMs ?? 0,
        'peak': (h.score ?? h.confidence ?? 0).toStringAsFixed(3),
        'path': h.direct ? 'direct' : (verify ? 'stage2' : 'unchecked'),
      });
    }
    return hits;
  }

  @override
  void reset() => inner.reset();

  @override
  Future<void> close() => inner.close();
}

/// Logs the verdict of stage 2 (`ok`, `no`, or `skip` if it could not
/// decide, which counts as not confirmed).
final class LoggingWakeVerifier implements WakeEndAwareVerifier, VerdictDetail {
  LoggingWakeVerifier(this.inner, {this.onGap});

  final WakeVerifier inner;

  /// Called after every candidate: the reason stage 2 could not decide, or
  /// `null` if it did.
  final void Function(WakeStage2Gap? gap)? onGap;

  @override
  String get kind => inner.kind;

  // WP155: the numbers of the inner verifier (B) for the wake archive.
  @override
  Map<String, Object?> get lastDetail =>
      inner is VerdictDetail ? (inner as VerdictDetail).lastDetail : const {};

  @override
  Future<bool> confirm(Int16List pcm) => confirmAt(pcm, -1);

  /// [endSample] is the end of the decision window in [pcm] (`-1`: unknown,
  /// then [inner.confirm] decides alone).
  @override
  Future<bool> confirmAt(Int16List pcm, int endSample) async {
    try {
      final i = inner;
      final ok = endSample >= 0 && i is WakeEndAwareVerifier
          ? await i.confirmAt(pcm, endSample)
          : await i.confirm(pcm);
      voiceLog('wake-verify', {'result': ok ? 'ok' : 'no'});
      onGap?.call(null);
      return ok;
    } on Object catch (e) {
      final missing =
          e is VoiceException && e.kind == VoiceErrorKind.modelMissing;
      voiceLog('wake-verify', {
        'result': 'skip',
        'error': missing ? 'model_missing' : errorCode(e),
      });
      onGap?.call(missing ? WakeStage2Gap.modelMissing : null);
      return false;
    }
  }
}
