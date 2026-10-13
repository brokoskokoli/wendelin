import 'dart:typed_data';

/// Microphone input: 16 kHz, mono, signed 16-bit PCM in frames.
///
/// Contract (`audioInputContract`):
/// - [start] returns a single-subscription stream of non-empty frames; it
///   throws `StateError` while already running and `VoiceException`
///   (e.g. `permissionDenied`) when recording is impossible.
/// - [stop] ends recording and closes the stream returned by [start]; it is
///   a no-op when not running. After [stop], [start] may be called again.
/// - Frame length is arbitrary (implementations typically use 10–32 ms);
///   consumers derive durations from the sample count and [sampleRate].
abstract interface class AudioInput {
  /// Sample rate of all frames.
  static const sampleRate = 16000;

  /// Whether recording is running.
  bool get isRunning;

  /// Starts recording; the stream delivers frames until [stop].
  Stream<Int16List> start();

  /// Stops recording and closes the frame stream.
  Future<void> stop();
}

/// Duration of [samples] samples at [AudioInput.sampleRate].
Duration samplesToDuration(int samples) =>
    Duration(microseconds: samples * 1000000 ~/ AudioInput.sampleRate);

/// Number of samples in [duration] at [AudioInput.sampleRate].
int durationToSamples(Duration duration) =>
    duration.inMicroseconds * AudioInput.sampleRate ~/ 1000000;
