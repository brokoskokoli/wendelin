import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'pcm.dart';
import 'sherpa_runtime.dart';

/// Silero VAD via sherpa-onnx as [VoiceActivityDetector].
///
/// The sherpa-onnx C API exposes no per-window probability, only whether a
/// speech segment is open (`isDetected`). [speechProbability] is therefore
/// binary: 1.0 while Silero hears speech (its own probability ≥
/// [threshold]), else 0.0. Minimum speech duration and end silence are left
/// to the `Endpointer`: Silero's own minimum speech is one window (32 ms)
/// and its minimum silence [releaseSeconds], so a closing segment adds only
/// that much to `EndpointConfig.endSilence`.
///
/// Runs on the calling isolate (one Silero window takes well under a
/// millisecond); [dispose] frees the native detector.
final class SileroVoiceActivityDetector implements VoiceActivityDetector {
  /// Loads `silero_vad.onnx` from [modelPath]; [threshold] is Silero's
  /// speech probability threshold (0.1–0.9, default 0.5).
  SileroVoiceActivityDetector({
    required String modelPath,
    this.threshold = 0.5,
    this.releaseSeconds = 0.1,
  }) : assert(threshold > 0 && threshold < 1, 'threshold in (0, 1)') {
    ensureSherpaBindings();
    _vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
          model: modelPath,
          threshold: threshold,
          minSilenceDuration: releaseSeconds,
          // One window: onset immediately, the Endpointer filters noise.
          minSpeechDuration: 0.03,
          windowSize: windowSamples,
          maxSpeechDuration: 60,
        ),
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
  }

  /// Samples per Silero window at 16 kHz.
  static const windowSamples = 512;

  @override
  final double threshold;

  /// Silence (seconds) after which Silero closes a segment.
  final double releaseSeconds;

  late final so.VoiceActivityDetector _vad;
  bool _freed = false;

  @override
  double speechProbability(Int16List frame) {
    if (frame.isEmpty) return 0;
    _vad.acceptWaveform(pcmToFloat(frame));
    final detected = _vad.isDetected();
    // Finished segments are not needed (the pipeline keeps its own audio).
    while (!_vad.isEmpty()) {
      _vad.pop();
    }
    return detected ? 1 : 0;
  }

  @override
  void reset() {
    if (!_freed) _vad.reset();
  }

  /// Frees the native detector; the instance is unusable afterwards.
  void dispose() {
    if (_freed) return;
    _freed = true;
    _vad.free();
  }
}
