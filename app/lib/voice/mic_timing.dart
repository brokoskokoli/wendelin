import 'voice_log.dart';

/// Times of one voice start for the `mic-ready` log (B11, WP194): tap →
/// microphone opened, → first block (from there the UI shows „Ich höre
/// zu“) and → models ready. Numbers only.
final class MicTiming {
  Stopwatch? _watch;
  Duration? _opened;
  Duration? _firstFrame;
  Duration? _loaded;
  String _model = '';

  /// Whether the first block is still missing.
  bool get awaitingFirstFrame => _watch != null && _firstFrame == null;

  /// Whether the first block arrived.
  bool get hasFirstFrame => _firstFrame != null;

  /// A new start begins; [watch] is already running.
  void begin(Stopwatch watch) {
    _watch = watch;
    _opened = _firstFrame = _loaded = null;
  }

  /// The microphone was opened.
  void opened() => _opened = _watch?.elapsed;

  /// The first block arrived (once per start).
  void firstFrame() => _firstFrame = _watch?.elapsed;

  /// The models are loaded ([model]: the engine).
  void loaded(String model) {
    _loaded = _watch?.elapsed;
    _model = model;
  }

  /// Logs `mic-ready` once both the first block and the models are there.
  void logIfReady(Object? trigger) {
    final first = _firstFrame;
    final loaded = _loaded;
    if (first == null || loaded == null) return;
    _watch = null;
    voiceLog('mic-ready', {
      if (_opened != null) 'open': _opened,
      'after': first,
      'load': loaded,
      'model': _model,
      'trigger': trigger,
    });
  }
}
