import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// [AudioInput] that can open the microphone before the pipeline is ready
/// (B11): [prime] starts [inner] right away and keeps the frames, the next
/// [start] first replays them and then continues live. So the beginning of
/// an utterance is not lost while Whisper and the VAD still load.
///
/// The buffer holds at most [maxBuffered] of audio (the longest utterance);
/// older frames are dropped. Without [prime], [start] is [inner.start].
final class PrimedAudioInput implements AudioInput {
  /// Wraps [inner].
  PrimedAudioInput(
    this.inner, {
    this.maxBuffered = const Duration(seconds: 30),
    this.onFirstFrame,
  });

  /// The real microphone.
  final AudioInput inner;

  /// Longest buffered audio.
  final Duration maxBuffered;

  /// Called with the first frame of every recording (primed or not).
  final void Function()? onFirstFrame;

  final _buffer = Queue<Int16List>();
  int _bufferedSamples = 0;
  // Cancelled in _drop() and stop().
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _primed;
  StreamController<Int16List>? _out;
  Object? _error;
  bool _done = false;
  bool _first = false;
  // Callbacks of an earlier (stopped) recording are ignored.
  int _gen = 0;

  /// Whether the microphone was opened early and nobody took the frames
  /// yet.
  bool get isPrimed => _primed != null && _out == null;

  /// Whether the early recording already failed or ended (e.g. no
  /// permission yet) and nobody took it.
  bool get failed => _out == null && (_error != null || _done);

  /// Buffered audio (for tests and the log).
  Duration get buffered =>
      samplesToDuration(_buffer.fold<int>(0, (sum, f) => sum + f.length));

  @override
  bool get isRunning => _primed != null || inner.isRunning;

  /// Opens the microphone now and buffers the frames until [start]. No
  /// effect while it already runs.
  void prime() {
    if (isRunning) return;
    _buffer.clear();
    _bufferedSamples = 0;
    _error = null;
    _done = false;
    _first = false;
    final Stream<Int16List> frames;
    try {
      frames = inner.start();
    } on Object catch (e) {
      // Reported to the pipeline on start (like a failing microphone).
      _error = e;
      _done = true;
      return;
    }
    final gen = ++_gen;
    _primed = frames.listen(
      (frame) {
        if (gen == _gen) _onFrame(frame);
      },
      onError: (Object e) {
        if (gen != _gen) return;
        final out = _out;
        if (out != null) {
          out.addError(e);
        } else {
          _error ??= e;
        }
      },
      onDone: () {
        if (gen != _gen) return;
        _done = true;
        final out = _out;
        if (out != null) unawaited(out.close());
      },
    );
  }

  void _onFrame(Int16List frame) {
    if (!_first) {
      _first = true;
      onFirstFrame?.call();
    }
    final out = _out;
    if (out != null) {
      out.add(frame);
      return;
    }
    _buffer.add(frame);
    _bufferedSamples += frame.length;
    final max = durationToSamples(maxBuffered);
    while (_bufferedSamples > max && _buffer.isNotEmpty) {
      _bufferedSamples -= _buffer.removeFirst().length;
    }
  }

  @override
  Stream<Int16List> start() {
    final primed = _primed;
    if (primed == null && !_done) {
      _first = false;
      return inner.start().map((frame) {
        if (!_first) {
          _first = true;
          onFirstFrame?.call();
        }
        return frame;
      });
    }
    if (_out != null) throw StateError('Die Aufnahme läuft bereits.');
    final out = StreamController<Int16List>();
    _out = out;
    out.onListen = () {
      while (_buffer.isNotEmpty) {
        out.add(_buffer.removeFirst());
      }
      _bufferedSamples = 0;
      final error = _error;
      _error = null;
      if (error != null) out.addError(error);
      if (_done) {
        _done = false;
        _primed = null;
        unawaited(out.close());
      }
    };
    return out.stream;
  }

  @override
  Future<void> stop() async {
    final primed = _primed;
    final out = _out;
    _gen++;
    _primed = null;
    _out = null;
    _buffer.clear();
    _bufferedSamples = 0;
    _error = null;
    _done = false;
    // Stop first, then cancel (as in VoicePipeline._listenAfter): the
    // microphone ends its stream for a live listener, while `cancel` and
    // `close` of a cancelled stream return a shared root-zone future.
    if (inner.isRunning) await inner.stop();
    if (primed != null) unawaited(primed.cancel());
    if (out != null && !out.isClosed) unawaited(out.close());
  }
}
