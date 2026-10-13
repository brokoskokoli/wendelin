import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import 'pcm.dart';

/// [AudioInput] that plays a 16 kHz mono WAV instead of the microphone:
/// first the recording, then silence until [stop] (the endpointing needs
/// the silence after the speech, like a real microphone).
///
/// Only for device tests and measurements in debug builds (WP19): the
/// overlay reads it through `deviceTestOverrides` (`lib/debug/`), device
/// tests override `audioInputProvider` with it. Release builds never use it.
final class WavAudioInput implements AudioInput {
  /// Plays [samples] (16 kHz mono PCM16) in frames of [frame], paced in
  /// real time divided by [speed].
  WavAudioInput(
    Int16List samples, {
    Duration frame = const Duration(milliseconds: 20),
    double speed = 1,
    Duration leadingSilence = const Duration(milliseconds: 300),
    DateTime Function() now = DateTime.now,
  }) : this.sequence(
         [samples],
         frame: frame,
         speed: speed,
         leadingSilence: leadingSilence,
         now: now,
       );

  /// Plays [recordings] one per [start] (the n-th recording for the n-th
  /// start, the last one again after that): e.g. a command and then the
  /// spoken „Nein“ to the confirmation (WP30, B7).
  WavAudioInput.sequence(
    this.recordings, {
    this.frame = const Duration(milliseconds: 20),
    this.speed = 1,
    this.leadingSilence = const Duration(milliseconds: 300),
    this.now = DateTime.now,
  }) : assert(speed > 0, 'speed > 0'),
       assert(recordings.isNotEmpty, 'at least one recording');

  /// Reads the WAV file at [path] (16 kHz mono PCM16).
  factory WavAudioInput.file(String path, {double speed = 1}) {
    final wav = Wav.read(path);
    if (wav.sampleRate != AudioInput.sampleRate) {
      throw FormatException(
        '$path: ${wav.sampleRate} Hz, erwartet ${AudioInput.sampleRate} Hz',
      );
    }
    return WavAudioInput(wav.samples, speed: speed);
  }

  /// Reads the WAV files at [paths] (16 kHz mono PCM16), one per recording
  /// ([WavAudioInput.sequence]).
  factory WavAudioInput.files(List<String> paths, {double speed = 1}) =>
      WavAudioInput.sequence([
        for (final path in paths) WavAudioInput.file(path).samples,
      ], speed: speed);

  /// The recordings, one per [start].
  final List<Int16List> recordings;

  /// The first recording.
  Int16List get samples => recordings.first;

  /// Length of one frame.
  final Duration frame;

  /// Playback speed (1 = real time).
  final double speed;

  /// Silence before the recording (as after pressing the microphone).
  final Duration leadingSilence;

  /// Time source for [endOfRecording].
  final DateTime Function() now;

  /// How often [start] was called (tests: one recording per request).
  int get starts => _starts;
  int _starts = 0;

  /// When the last sample of the recording was delivered (end of speech).
  DateTime? get endOfRecording => _endOfRecording;
  DateTime? _endOfRecording;

  // Closed in stop().
  // ignore: close_sinks
  StreamController<Int16List>? _out;
  Timer? _timer;

  @override
  bool get isRunning => _out != null;

  @override
  Stream<Int16List> start() {
    if (_out != null) throw StateError('Aufnahme läuft schon');
    final samples = recordings[_starts.clamp(0, recordings.length - 1)];
    _starts++;
    _endOfRecording = null;
    // Closed in stop().
    // ignore: close_sinks
    final out = _out = StreamController<Int16List>();
    final perFrame = durationToSamples(frame);
    final lead = durationToSamples(leadingSilence);
    var position = -lead;
    final interval = Duration(
      microseconds: (frame.inMicroseconds / speed).round(),
    );
    _timer = Timer.periodic(interval, (_) {
      if (out.isClosed) return;
      final chunk = Int16List(perFrame);
      for (var i = 0; i < perFrame; i++) {
        final at = position + i;
        if (at >= 0 && at < samples.length) chunk[i] = samples[at];
      }
      position += perFrame;
      if (position >= samples.length && _endOfRecording == null) {
        _endOfRecording = now();
      }
      out.add(chunk);
    });
    return out.stream;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final out = _out;
    _out = null;
    // Not awaited: without a listener the stream would never report done.
    unawaited(out?.close());
  }
}
