import 'dart:async';

import 'dart:typed_data';

import '../src/io/audio_input.dart';
import '../src/io/barge_in_detector.dart';

/// [BargeInDetector] fired by hand. Passes `bargeInDetectorContract`.
///
/// With a [startDelay] the start completes late and a [stop] while it is
/// pending is lost (worst case): the caller has to serialize them.
///
/// With [audio] it holds the shared microphone while it runs, like the real
/// detector (`WakeWordBargeInDetector`): [start] opens it, [stop] releases
/// it after [stopDelay]. Whoever records meanwhile gets the "already
/// running" error of the device.
///
/// With [tail] it is a [BargeTailSource] (WP146): [beginTail] keeps it
/// recording and [endTail] hands over [tail] (with [tailIdle]).
final class FakeBargeInDetector
    implements BargeInDetector, SpokenTextSink, BargeTailSource {
  /// Creates a fake detector.
  FakeBargeInDetector({
    this.startDelay = Duration.zero,
    this.audio,
    this.stopDelay = Duration.zero,
    this.hangOnStop = false,
    List<Int16List>? tail,
    this.tailIdle = Duration.zero,
  }) : tail = tail == null ? null : _join(tail);

  static Int16List _join(List<Int16List> frames) {
    final out = <int>[for (final f in frames) ...f];
    return Int16List.fromList(out);
  }

  /// What [endTail] returns (`null`: [beginTail] is refused).
  final Int16List? tail;

  /// Time since the last tail frame.
  final Duration tailIdle;

  bool _tailing = false;

  /// Whether it records on for the follow-up microphone.
  bool get isTailing => _tailing;

  /// Number of [beginTail] / [endTail] calls that did something.
  int tailBegun = 0, tailEnded = 0;

  @override
  bool beginTail() {
    if (!_running || tail == null || _tailing) return false;
    _tailing = true;
    tailBegun++;
    return true;
  }

  @override
  BargeTail? endTail() {
    if (!_tailing) return null;
    _tailing = false;
    tailEnded++;
    _running = false;
    stopCount++;
    return (pcm: tail!, idle: tailIdle);
  }

  /// Shared microphone held while running (`null`: not used).
  final AudioInput? audio;

  /// [stop] never completes (a hanging device).
  final bool hangOnStop;

  /// How long [stop] takes to release [audio].
  final Duration stopDelay;

  // Cancelled in stop().
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _mic;

  /// How long [start] takes.
  final Duration startDelay;

  final _controller = StreamController<BargeInSignal>.broadcast(sync: true);
  bool _running = false;

  /// Sentences the pipeline reported as being read aloud (WP113).
  final spoken = <String>[];

  @override
  void spoke(String sentence) => spoken.add(sentence);

  /// Number of effective [start] calls.
  int startCount = 0;

  /// Number of effective [stop] calls.
  int stopCount = 0;

  /// Thrown by [start] when set.
  Object? startError;

  @override
  Stream<BargeInSignal> get signals => _controller.stream;

  /// Whether somebody listens to [signals].
  bool get hasListeners => _controller.hasListener;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    final error = startError;
    if (error != null) throw error;
    if (_running) return;
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    if (_running) return;
    _running = true;
    startCount++;
    _mic = audio?.start().listen((_) {});
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _tailing = false;
    stopCount++;
    if (hangOnStop) await Completer<void>().future;
    final mic = audio;
    if (mic == null) return;
    if (stopDelay > Duration.zero) await Future<void>.delayed(stopDelay);
    final sub = _mic;
    _mic = null;
    // Stop first: `close` of a cancelled stream never completes in
    // fakeAsync.
    await mic.stop();
    unawaited(sub?.cancel());
  }

  /// Emits [signal] (only while running, like a real detector).
  void emit(BargeInSignal signal) {
    if (_running) _controller.add(signal);
  }
}
