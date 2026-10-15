import 'dart:async';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice_log.dart';
import 'barge_meter.dart';

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
    this.stopTemplates = _none,
    this.extraMargin = 0.05,
    this.marginOverride,
    this.diagInterval = const Duration(seconds: 1),
  });

  /// Microphone shared with the pipeline.
  final AudioInput audio;

  /// Templates of all learned voices.
  final Future<List<WakeTemplates>> Function() templates;

  /// Templates of „Stopp“ for all learned voices (WP64b); without them only
  /// „Wendelin“ (and „Wendelin, stopp“) interrupts.
  final Future<List<WakeTemplates>> Function() stopTemplates;

  static Future<List<WakeTemplates>> _none() async => const [];

  /// A new feature chain.
  final WakeFeatureExtractor Function() features;

  /// Added to every template threshold.
  final double extraMargin;

  /// Developer setting (WP72, `debug.bargeMargin`): replaces [extraMargin]
  /// when it returns a value. Read once, when the engine is built.
  final Future<double?> Function()? marginOverride;

  /// Interval of the `barge-diag` lines while listening.
  final Duration diagInterval;

  BargeMeter? _meter;
  Timer? _diag;

  WakeWordBargeInDetector? _inner;
  bool _empty = false;
  bool _running = false;
  bool _disposeWhenIdle = false;
  bool _disposed = false;
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
      final stops = await stopTemplates();
      if (sets.isEmpty) {
        _empty = true;
        voiceLog('barge-in-off', {'reason': 'no-templates'});
      } else {
        voiceLog('barge-stop-word', {'learned': stops.isNotEmpty});
        final margin = await marginOverride?.call() ?? extraMargin;
        List<WakeTemplates> strictly(List<WakeTemplates> l) => [
          for (final t in l)
            t.withThreshold((t.threshold + margin).clamp(0.0, 0.99)),
        ];
        final strict = strictly(sets);
        final strictStops = strictly(stops);
        double? lowest(List<WakeTemplates> l) => l.isEmpty
            ? null
            : l.map((t) => t.threshold).reduce((a, b) => a < b ? a : b);
        final meter = _meter = BargeMeter(
          threshold: lowest(strict),
          stopThreshold: lowest(strictStops),
        );
        voiceLog('barge-config', {
          'margin': margin,
          'thr': meter.threshold,
          'sthr': meter.stopThreshold,
        });
        final inner = WakeWordBargeInDetector(
          audio: MeteredAudioInput(audio, meter),
          engine: MeteredEngine(
            CandidateWakeEngine(
              features: features(),
              templates: strict.first,
              moreTemplates: strict.skip(1).toList(),
              stopTemplates: strictStops,
              modelThreshold: null,
              onWindow: (main, stop, _) => meter.onWindow(main, stop),
            ),
            meter,
          ),
        );
        _sub = inner.signals.listen((signal) {
          voiceLog('barge-hit', {'kind': signal.code});
          _signals.add(signal);
        });
        _inner = inner;
      }
    }
    // A stop during the loading wins.
    if (_running) {
      _meter?.reset();
      await _inner?.start();
      voiceLog('barge-listen', {'on': _inner != null});
      if (_inner != null && _running) {
        _diag?.cancel();
        _diag = Timer.periodic(diagInterval, (_) => _meter?.flush());
      }
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _diag?.cancel();
    _diag = null;
    await _inner?.stop();
    if (_inner != null) _meter?.summary();
    voiceLog('barge-listen', {'on': false});
    if (_disposeWhenIdle) await dispose();
  }

  /// Ends the detector as soon as it is idle: a running listening session
  /// (the spoken answer) is not cut off by a rebuild of the provider
  /// (WP64b, new or deleted „Stopp“ takes effect at the next start).
  Future<void> disposeWhenIdle() async {
    if (_running) {
      _disposeWhenIdle = true;
      return;
    }
    await dispose();
  }

  /// Ends the detector for good.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _diag?.cancel();
    await _sub?.cancel();
    await _inner?.dispose();
    await _signals.close();
  }
}
