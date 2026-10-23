import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Frames of 30 ms: [lead] ms of silence, [speech] ms of a tone at
/// [amplitude], [tail] ms of silence.
List<Int16List> recording({
  int lead = 450,
  int speech = 900,
  int tail = 700,
  int amplitude = 8000,
}) {
  Int16List tone(int ms) {
    final f = Int16List(16 * ms);
    for (var i = 0; i < f.length; i++) {
      f[i] = (i ~/ 20).isEven ? amplitude : -amplitude;
    }
    return f;
  }

  Int16List silence(int ms) => Int16List(16 * ms);
  return [silence(lead), tone(speech), silence(tail)];
}

/// Audio input that hands out one scripted recording per [start] and ends
/// the stream after it (like [WavAudioInput] up to the silence).
class SequenceAudio implements AudioInput {
  SequenceAudio(this.recordings);

  final List<List<Int16List>> recordings;
  int starts = 0, stops = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Stream<Int16List> start() {
    final frames = recordings[starts < recordings.length ? starts : 0];
    starts++;
    _running = true;
    return Stream.fromIterable(frames);
  }

  @override
  Future<void> stop() async {
    stops++;
    _running = false;
  }
}

/// Feature chain stand-in: a window per 80 ms whose embedding is fixed
/// ([vector]) or computed from the end sample.
FakeWakeFeatureExtractor fakeFeatures({
  Float32List Function(int endSample)? vector,
  String version = 'fake-1',
}) => FakeWakeFeatureExtractor(
  featureVersion: version,
  centerId: wakeCenterId,
  windowFor: (end, _) => WakeWindow(
    endSample: end,
    embedding:
        vector?.call(end) ??
        Float32List.fromList([1, 0.01 * (end % 7), 0.5, 0]),
  ),
);
