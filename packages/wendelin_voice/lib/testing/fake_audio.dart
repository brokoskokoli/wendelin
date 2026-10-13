import 'dart:async';
import 'dart:typed_data';

import '../src/io/audio_input.dart';
import '../src/io/voice_activity_detector.dart';
import '../src/io/voice_exception.dart';

/// Builds synthetic 16 kHz frames for tests: „speech“ is a loud square
/// wave, silence is zeros. [FakeVoiceActivityDetector] tells them apart by
/// amplitude.
abstract final class AudioFrames {
  /// Amplitude of speech frames.
  static const speechAmplitude = 8000;

  /// Default frame length (30 ms).
  static const defaultFrame = Duration(milliseconds: 30);

  /// One frame of silence.
  static Int16List silence([Duration length = defaultFrame]) =>
      Int16List(durationToSamples(length));

  /// One frame of „speech“.
  static Int16List speech([Duration length = defaultFrame]) {
    final f = Int16List(durationToSamples(length));
    for (var i = 0; i < f.length; i++) {
      f[i] = (i ~/ 20).isEven ? speechAmplitude : -speechAmplitude;
    }
    return f;
  }

  /// Frames for [pattern]: `S` = speech, `.` = silence, one character per
  /// [frame] (other characters are ignored, e.g. spaces for readability).
  static List<Int16List> pattern(
    String pattern, {
    Duration frame = defaultFrame,
  }) => [
    for (final c in pattern.split(''))
      if (c == 'S') speech(frame) else if (c == '.') silence(frame),
  ];
}

/// Scripted [AudioInput]: [start] plays [frames] (one per [frameInterval],
/// `Duration.zero` = one microtask hop each), then keeps the stream open
/// until [stop]. More frames can be pushed with [push].
///
/// Passes `audioInputContract`.
final class FakeAudioInput implements AudioInput {
  /// Creates a fake input.
  FakeAudioInput({
    List<Int16List> frames = const [],
    this.frameInterval = Duration.zero,
    this.startError,
    this.closeAfterFrames = false,
  }) : _script = List.of(frames);

  final List<Int16List> _script;

  /// Pause between scripted frames.
  final Duration frameInterval;

  /// Thrown by [start] (e.g. `VoiceException(permissionDenied)`).
  final Object? startError;

  /// Whether the stream ends by itself after the scripted frames (like a
  /// microphone that disappears).
  final bool closeAfterFrames;

  StreamController<Int16List>? _controller;
  Timer? _timer;

  /// Number of [start] calls.
  int startCount = 0;

  /// Number of [stop] calls that stopped a recording.
  int stopCount = 0;

  /// Frames delivered so far (all recordings).
  int deliveredFrames = 0;

  /// Replaces the frames for the next [start].
  void script(List<Int16List> frames) => _script
    ..clear()
    ..addAll(frames);

  @override
  bool get isRunning => _controller != null;

  @override
  Stream<Int16List> start() {
    if (startError != null) throw startError!;
    if (_controller != null) {
      throw StateError('FakeAudioInput läuft bereits');
    }
    startCount++;
    final frames = List.of(_script);
    final c = StreamController<Int16List>();
    _controller = c;
    var i = 0;
    void next() {
      if (_controller != c) return;
      if (i >= frames.length) {
        if (closeAfterFrames) {
          _controller = null;
          unawaited(c.close());
        }
        return;
      }
      deliveredFrames++;
      c.add(frames[i++]);
      _timer = Timer(frameInterval, next);
    }

    c.onListen = () => _timer = Timer(frameInterval, next);
    return c.stream;
  }

  /// Delivers [frame] to the running recording.
  void push(Int16List frame) {
    final c = _controller;
    if (c == null) throw StateError('FakeAudioInput läuft nicht');
    deliveredFrames++;
    c.add(frame);
  }

  /// Fails the running recording with [error].
  void fail(Object error) => _controller?.addError(error);

  @override
  Future<void> stop() async {
    final c = _controller;
    if (c == null) return;
    _controller = null;
    _timer?.cancel();
    stopCount++;
    await c.close();
  }
}

/// [AudioInput] that cannot record (no permission).
final class DeniedAudioInput implements AudioInput {
  @override
  bool get isRunning => false;

  @override
  Stream<Int16List> start() => throw const VoiceException(
    VoiceErrorKind.permissionDenied,
    'Kein Zugriff auf das Mikrofon.',
  );

  @override
  Future<void> stop() async {}
}

/// [VoiceActivityDetector] that classifies by amplitude: frames whose mean
/// absolute value reaches [loudness] are speech (0.9), others not (0.05).
///
/// Passes `voiceActivityDetectorContract`.
final class FakeVoiceActivityDetector implements VoiceActivityDetector {
  /// Creates a fake detector.
  FakeVoiceActivityDetector({this.threshold = 0.5, this.loudness = 1000});

  @override
  final double threshold;

  /// Mean absolute amplitude from which a frame is speech.
  final int loudness;

  /// Number of [reset] calls.
  int resets = 0;

  /// Number of frames analysed.
  int frames = 0;

  @override
  double speechProbability(Int16List frame) {
    frames++;
    if (frame.isEmpty) return 0;
    var sum = 0;
    for (final s in frame) {
      sum += s.abs();
    }
    return sum / frame.length >= loudness ? 0.9 : 0.05;
  }

  @override
  void reset() => resets++;
}
