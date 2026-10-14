import 'dart:async';
import 'dart:typed_data';

import '../io/audio_input.dart';
import '../io/barge_in_detector.dart';
import 'keyword_spec.dart';
import 'wake_word_engine.dart';

/// [BargeInDetector] on a [WakeWordEngine]: while the answer is spoken it
/// listens on [audio] for the keywords `wake` and `stop` (concept K23 c).
///
/// The engine should run with a stricter threshold than the idle listener.
/// [stop] cancels the stream and calls `audio.stop()` **before** it returns,
/// (the engine stays open for the next [start]; [dispose] closes it)
/// so the owner can switch the capture profile back to speech recognition
/// (`VOICE_RECOGNITION`) before the follow-up window opens (WP51 „Offen“).
final class WakeWordBargeInDetector implements BargeInDetector {
  /// Creates the detector.
  WakeWordBargeInDetector({
    required this.audio,
    required this.engine,
    this.keywords = const [KeywordSpec.wendelin],
  });

  /// Microphone (capture profile for speech output, set by the app).
  final AudioInput audio;

  /// Keyword engine.
  final WakeWordEngine engine;

  /// Keywords to open the engine with.
  final List<KeywordSpec> keywords;

  final _signals = StreamController<BargeInSignal>.broadcast(sync: true);
  // Cancelled in stop/_release.
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _sub;
  bool _running = false;
  bool _engineOpen = false;
  int _generation = 0;
  Future<void> _chain = Future.value();
  Future<void> _lifecycle = Future.value();

  @override
  Stream<BargeInSignal> get signals => _signals.stream;

  @override
  bool get isRunning => _running;

  // start and stop run one after the other, in call order.
  Future<void> _serial(Future<void> Function() job) {
    final next = _lifecycle.then((_) => job());
    _lifecycle = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> start() => _serial(() async {
    if (_running) return;
    if (!_engineOpen) {
      await engine.open(keywords);
      _engineOpen = true;
    }
    engine.reset();
    final gen = ++_generation;
    _chain = Future.value();
    _sub = audio.start().listen(
      (f) => _chain = _chain.then((_) => _onFrame(f, gen)),
      onError: (Object _) => unawaited(stop()),
    );
    _running = true;
  });

  Future<void> _onFrame(Int16List frame, int gen) async {
    if (gen != _generation) return;
    final hits = await engine.accept(frame);
    if (gen != _generation) return;
    for (final h in hits) {
      final keyword = switch (h.keywordId) {
        'stop' => BargeInKeyword.stop,
        'wake' => BargeInKeyword.wake,
        _ => null,
      };
      if (keyword != null) _signals.add(BargeInSignal.keyword(keyword));
    }
  }

  @override
  Future<void> stop() => _serial(() async {
    if (!_running) return;
    _running = false;
    _generation++;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    await audio.stop();
  });

  /// Stops and closes the engine for good.
  Future<void> dispose() async {
    await stop();
    await _serial(() async {
      if (!_engineOpen) return;
      _engineOpen = false;
      await engine.close();
    });
  }
}
