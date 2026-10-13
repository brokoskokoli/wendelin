import 'dart:typed_data';

/// Voice activity detection per audio frame (Silero VAD via sherpa-onnx in
/// the app).
///
/// Contract (`voiceActivityDetectorContract`):
/// - [speechProbability] returns a value in `[0, 1]` for any non-empty
///   16 kHz frame; a frame of digital silence (all zeros) is below
///   [threshold].
/// - [reset] forgets the internal state (between recordings); it never
///   throws.
abstract interface class VoiceActivityDetector {
  /// Probability from which a frame counts as speech.
  double get threshold;

  /// Speech probability of [frame] (stateful: depends on earlier frames).
  double speechProbability(Int16List frame);

  /// Clears the internal state.
  void reset();
}

/// Convenience on [VoiceActivityDetector].
extension VoiceActivityDetectorX on VoiceActivityDetector {
  /// Whether [frame] counts as speech.
  bool isSpeech(Int16List frame) => speechProbability(frame) >= threshold;
}
