import 'dart:async';
import 'dart:typed_data';

import '../wake/audio_ring_buffer.dart';
import 'audio_input.dart';
import 'voice_exception.dart';

/// An [AudioInput] that records continuously from an underlying [source]
/// into an [AudioRingBuffer] (default 5–6 s history, WP178).
///
/// Keeps the underlying recording running across interaction phases
/// (e.g. listening → speaking → follow-up) without constantly starting and
/// stopping the microphone. Audio captured during speaking can be inspected
/// for barge-in or discarded via [discard].
final class ContinuousAudioInput implements DetachableAudioInput {
  /// Creates a continuous input on [source].
  ContinuousAudioInput(
    this.source, {
    this.bufferCapacity = AudioRingBuffer.defaultCapacity,
  }) : ring = AudioRingBuffer(capacity: bufferCapacity);

  /// The underlying physical or fake microphone.
  final AudioInput source;

  /// Capacity of the internal ring buffer.
  final Duration bufferCapacity;

  /// Ring buffer holding the rolling audio history.
  final AudioRingBuffer ring;

  bool _sourceRunning = false;
  int _sourceStartCount = 0;
  int _sessionCount = 0;
  StreamSubscription<Int16List>? _sourceSub;
  StreamController<Int16List>? _controller;

  /// Whether the continuous recording from [source] is currently running.
  @override
  bool get isRunning => _controller != null && !_controller!.isClosed;

  /// Whether the underlying [source] is currently running.
  bool get isSourceRunning => _sourceRunning;

  /// Number of times the underlying [source] was started.
  int get startCount => _sourceStartCount;

  /// Number of consumer sessions started.
  int get sessionCount => _sessionCount;

  @override
  Stream<Int16List> start() {
    if (isRunning) {
      throw const VoiceException(
        VoiceErrorKind.busy,
        'ContinuousAudioInput stream runs already.',
      );
    }
    _ensureSourceRunning();
    _sessionCount++;
    _controller = StreamController<Int16List>(sync: true);
    return _controller!.stream;
  }

  void _ensureSourceRunning() {
    if (_sourceRunning) return;
    try {
      _sourceSub = source.start().listen(
        _onFrame,
        onError: _onError,
        onDone: _onDone,
      );
      _sourceRunning = true;
      _sourceStartCount++;
    } on Object catch (e) {
      _sourceRunning = false;
      throw e is VoiceException
          ? e
          : VoiceException(VoiceErrorKind.unavailable, '$e', cause: e);
    }
  }

  void _onFrame(Int16List frame) {
    ring.add(frame);
    final c = _controller;
    if (c != null && !c.isClosed) {
      c.add(frame);
    }
  }

  void _onError(Object error) {
    final c = _controller;
    if (c != null && !c.isClosed) {
      c.addError(
        error is VoiceException
            ? error
            : VoiceException(
                VoiceErrorKind.unavailable,
                '$error',
                cause: error,
              ),
      );
    }
  }

  void _onDone() {
    _sourceRunning = false;
    final c = _controller;
    if (c != null && !c.isClosed) {
      c.close();
    }
    _controller = null;
  }

  /// Ends the current consumer stream without stopping the underlying [source].
  /// The underlying recording continues rolling into [ring].
  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) {
      unawaited(c.close());
    }
  }

  /// Discards unneeded audio in [ring] (e.g. from speech output without barge-in).
  void discard() {
    ring.clear();
  }

  /// Fully stops the underlying [source] and frees resources.
  Future<void> close() async {
    await stop();
    if (_sourceRunning) {
      _sourceRunning = false;
      unawaited(_sourceSub?.cancel());
      _sourceSub = null;
      await source.stop();
    } else {
      unawaited(_sourceSub?.cancel());
      _sourceSub = null;
    }
    await _controller?.close();
    _controller = null;
    ring.clear();
  }

  @override
  Future<void> Function()? detach() => close;
}
