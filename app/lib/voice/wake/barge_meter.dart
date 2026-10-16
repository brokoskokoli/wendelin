import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice_log.dart';

/// Statistics of the barge-in listening of the last interval (WP72), logged
/// as `barge-diag` (numbers only, no content): how much audio arrived, how
/// loud it was, whether the detector kept up and how close the best window
/// came to the templates.
final class BargeMeter {
  /// Creates the meter; [threshold] / [stopThreshold] are the effective
  /// (strict) thresholds, logged as reference for `sim` / `stop`.
  BargeMeter({this.threshold, this.stopThreshold});

  /// Lowest effective „Wendelin“ threshold (`null`: no templates).
  final double? threshold;

  /// Lowest effective „Stopp“ threshold (`null`: not learned).
  final double? stopThreshold;

  int _seconds = 0;
  int _frames = 0, _samples = 0, _peak = 0, _processed = 0, _micros = 0;
  double _sumSq = 0, _sim = -1, _stop = -1;
  double _allSim = -1, _allStop = -1;
  int _allFrames = 0;
  // WP80: background of „Stopp“ and level of the stream.
  double _floor = -1, _gap = -1, _quiet = 0, _peakRms = 0;

  /// Starts a new listening session.
  void reset() {
    _seconds = _allFrames = 0;
    _allSim = _allStop = -1;
    _frames = _samples = _peak = _processed = _micros = 0;
    _sumSq = 0;
    _sim = _stop = -1;
    _floor = _gap = -1;
    _quiet = _peakRms = 0;
  }

  /// Called for every frame the microphone delivers.
  void onFrame(Int16List f) {
    _frames++;
    _allFrames++;
    _samples += f.length;
    for (final v in f) {
      _sumSq += v * v;
      final a = v < 0 ? -v : v;
      if (a > _peak) _peak = a;
    }
  }

  /// Called after the engine processed a frame of [samples] in [micros].
  void onProcessed(int samples, int micros) {
    _processed += samples;
    _micros += micros;
  }

  /// Called for every feature window.
  ///
  /// [floor]: sliding background similarity of „Stopp“ (silence or echo),
  /// [quiet] / [peak]: noise floor and recent peak level (RMS) of the stream.
  void onWindow(
    double main,
    double stop, {
    double? floor,
    double quiet = 0,
    double peak = 0,
  }) {
    if (floor != null) {
      _floor = floor;
      if (stop - floor > _gap) _gap = stop - floor;
    }
    _quiet = quiet;
    _peakRms = peak;
    if (main > _sim) _sim = main;
    if (stop > _stop) _stop = stop;
    if (main > _allSim) _allSim = main;
    if (stop > _allStop) _allStop = stop;
  }

  /// Writes one `barge-diag` line and starts a new interval.
  ///
  /// `frames=0` means the microphone delivers nothing (paused recording),
  /// `rms=0` with frames a silenced one; `lag` is the audio (ms) waiting for
  /// the detector, `proc` the computing time per second of audio (ms).
  void flush() {
    _seconds++;
    final rms = _samples == 0 ? 0 : math.sqrt(_sumSq / _samples).round();
    final backlog = _samples - _processed;
    voiceLog('barge-diag', {
      't': _seconds,
      'frames': _frames,
      'rms': rms,
      'peak': _peak,
      'lag': (backlog * 1000 ~/ AudioInput.sampleRate).clamp(0, 1 << 30),
      'proc': _processed == 0
          ? 0
          : _micros * AudioInput.sampleRate ~/ _processed ~/ 1000,
      'sim': _sim,
      'stop': _stop,
      'thr': threshold,
      'sthr': stopThreshold,
      // WP80: `sfloor` = background similarity of „Stopp“, `sgap` = largest
      // distance of `stop` above it, `quiet` = noise floor, `lvl` = peak level.
      'sfloor': _floor,
      'sgap': _gap,
      'quiet': _quiet.round(),
      'lvl': _peakRms.round(),
    });
    _gap = -1;
    _frames = _samples = _peak = _processed = _micros = 0;
    _sumSq = 0;
    _sim = _stop = -1;
  }

  /// Best similarities of the whole session so far (for `barge-hit`).
  Map<String, Object?> get maxima => {
    't': _seconds,
    'sim': _allSim,
    'stop': _allStop,
    'thr': threshold,
    'sthr': stopThreshold,
  };

  /// Writes the `barge-end` line (maxima of the whole listening session).
  void summary() => voiceLog('barge-end', {
    't': _seconds,
    'frames': _allFrames,
    'sim': _allSim,
    'stop': _allStop,
    'thr': threshold,
    'sthr': stopThreshold,
  });
}

/// [AudioInput] that reports every frame to [meter].
final class MeteredAudioInput implements AudioInput {
  /// Wraps [inner].
  MeteredAudioInput(this.inner, this.meter);

  /// The real microphone.
  final AudioInput inner;

  /// Receives the frames.
  final BargeMeter meter;

  @override
  bool get isRunning => inner.isRunning;

  @override
  Stream<Int16List> start() => inner.start().map((f) {
    meter.onFrame(f);
    return f;
  });

  @override
  Future<void> stop() => inner.stop();
}

/// [WakeWordEngine] that times [inner] per frame for [meter].
final class MeteredEngine implements WakeWordEngine {
  /// Wraps [inner].
  MeteredEngine(this.inner, this.meter);

  /// The real engine.
  final WakeWordEngine inner;

  /// Receives the timing.
  final BargeMeter meter;

  @override
  Future<void> open(List<KeywordSpec> keywords) => inner.open(keywords);

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final sw = Stopwatch()..start();
    final hits = await inner.accept(frame);
    meter.onProcessed(frame.length, sw.elapsedMicroseconds);
    return hits;
  }

  @override
  void reset() => inner.reset();

  @override
  Future<void> close() => inner.close();
}
