import 'dart:typed_data';

/// Sample rate the speaker embedder expects.
const speakerSampleRate = 16000;

/// Turns speech into a speaker embedding (WP92a). The implementation (the
/// app: sherpa-onnx `SpeakerEmbeddingExtractor`) loads its model lazily and
/// frees it on [release]; the core never sees a model file.
///
/// Contract: [embed] returns a vector of the same length for every call
/// (the model's dimension, e.g. 192); it does not normalize. Audio is only
/// processed, never stored.
abstract interface class SpeakerEmbedder {
  /// Embedding of mono 16 kHz [pcm]. Throws if the model is not available;
  /// the caller treats that as „unknown“.
  Future<Float32List> embed(Int16List pcm);

  /// Frees the model (loaded again by the next [embed]).
  Future<void> release();
}
