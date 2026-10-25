import 'dart:typed_data';

/// Microphone input: 16 kHz, mono, signed 16-bit PCM in frames.
///
/// Contract (`audioInputContract`):
/// - [start] returns a single-subscription stream of non-empty frames; it
///   throws `VoiceException` (`busy`, or a `StateError` in simple fakes)
///   while already running and `VoiceException` (e.g. `permissionDenied`)
///   when recording is impossible.
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

/// An [AudioInput] whose running recording can go on in the background while
/// the next one starts (WP146): the barge-in recording keeps listening
/// until the follow-up recording delivers its first frame.
abstract interface class DetachableAudioInput implements AudioInput {
  /// Lets the running recording continue: [isRunning] is false afterwards
  /// and [start] opens a second, new recording. The frames of the detached
  /// one still arrive on the stream returned by the earlier [start]. Returns
  /// the function that ends it (idempotent), or `null` if nothing runs or a
  /// recording is detached already (then the caller stops as usual).
  Future<void> Function()? detach();
}

/// Duration of [samples] samples at [AudioInput.sampleRate].
Duration samplesToDuration(int samples) =>
    Duration(microseconds: samples * 1000000 ~/ AudioInput.sampleRate);

/// Number of samples in [duration] at [AudioInput.sampleRate].
int durationToSamples(Duration duration) =>
    duration.inMicroseconds * AudioInput.sampleRate ~/ 1000000;
