import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// Identifies the feature models (openWakeWord v0.5.1: mel spectrogram and
/// speech embedding) and this chunking; stored with personal templates
/// (`WakeTemplates.featureVersion`). Change it whenever the numbers change.
const wakeFeatureVersion = 'oww-0.5.1-mel-emb-1';

/// The two ONNX models of the chain behind a seam (the real runner is
/// `OnnxWakeModels`; tests count calls with a fake).
abstract interface class WakeModelRunner {
  /// Mel spectrogram of [samples] (int16 values as floats): `n / 160 - 3`
  /// frames of 32 values, flattened.
  Float32List mel(Float32List samples);

  /// Embedding (96 values) of 76 mel frames (76 × 32, already scaled).
  Float32List embed(Float32List frames);

  /// Frees the models.
  void close();
}

/// openWakeWord feature chain (streaming): 80 ms chunks of 1 280 samples
/// give 8 mel frames each (with 480 samples of context, scaled `x / 10 + 2`),
/// every chunk one embedding of the last 76 frames, and 16 embeddings form
/// one window (1 536 values, one new window per chunk). Pure logic over a
/// [WakeModelRunner].
final class WakeFeatureChain {
  /// Creates the chain.
  WakeFeatureChain(this.runner);

  /// Samples per step (80 ms).
  static const chunk = 1280;

  /// Mel frames one embedding sees.
  static const melFrames = 76;

  /// Values per mel frame.
  static const melBins = 32;

  /// Values per embedding.
  static const embeddingSize = 96;

  /// Embeddings per window.
  static const windowEmbeddings = 16;

  static const _context = 480;

  /// The models.
  final WakeModelRunner runner;

  final _pending = <int>[];
  var _ctx = Float32List(_context);
  final _mel = <Float32List>[];
  final _emb = <Float32List>[];
  var _consumed = 0;

  /// Feeds [frame]; returns the windows that became available.
  List<WakeWindow> accept(Int16List frame) {
    _pending.addAll(frame);
    final out = <WakeWindow>[];
    var offset = 0;
    while (_pending.length - offset >= chunk) {
      final input = Float32List(_context + chunk)..setAll(0, _ctx);
      for (var i = 0; i < chunk; i++) {
        input[_context + i] = _pending[offset + i].toDouble();
      }
      offset += chunk;
      _consumed += chunk;
      _ctx = Float32List.sublistView(input, chunk);
      final w = _step(input);
      if (w != null) out.add(w);
    }
    if (offset > 0) _pending.removeRange(0, offset);
    return out;
  }

  WakeWindow? _step(Float32List input) {
    final raw = runner.mel(input);
    for (var f = 0; f + melBins <= raw.length; f += melBins) {
      final frame = Float32List(melBins);
      for (var i = 0; i < melBins; i++) {
        frame[i] = raw[f + i] / 10 + 2;
      }
      _mel.add(frame);
    }
    if (_mel.length > melFrames) {
      _mel.removeRange(0, _mel.length - melFrames);
    }
    if (_mel.length < melFrames) return null;
    final flat = Float32List(melFrames * melBins);
    for (var i = 0; i < melFrames; i++) {
      flat.setAll(i * melBins, _mel[i]);
    }
    _emb.add(runner.embed(flat));
    if (_emb.length > windowEmbeddings) _emb.removeAt(0);
    if (_emb.length < windowEmbeddings) return null;
    final window = Float32List(windowEmbeddings * embeddingSize);
    for (var i = 0; i < windowEmbeddings; i++) {
      window.setAll(i * embeddingSize, _emb[i]);
    }
    return WakeWindow(endSample: _consumed, embedding: window);
  }

  /// Starts a new stream.
  void reset() {
    _pending.clear();
    _ctx = Float32List(_context);
    _mel.clear();
    _emb.clear();
    _consumed = 0;
  }
}

/// [WakeFeatureExtractor] on a [WakeFeatureChain]; [load] opens the models
/// (the app: ONNX Runtime, tests: a fake).
final class ChainWakeFeatureExtractor implements WakeFeatureExtractor {
  /// Creates the extractor; [load] runs in [open].
  ChainWakeFeatureExtractor(this.load);

  /// Opens the models.
  final Future<WakeModelRunner> Function() load;

  WakeFeatureChain? _chain;
  Future<WakeModelRunner>? _loading;
  var _epoch = 0;

  @override
  String get featureVersion => wakeFeatureVersion;

  @override
  Future<void> open() async {
    if (_chain != null) return;
    final epoch = _epoch;
    final loading = _loading ??= load();
    final WakeModelRunner runner;
    try {
      runner = await loading;
    } on Object {
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
    // Closed while loading (close() released the runner) or another open
    // call finished first: nothing more to do.
    if (epoch != _epoch || _chain != null) return;
    _loading = null;
    _chain = WakeFeatureChain(runner);
  }

  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    final chain = _chain;
    if (chain == null) throw StateError('Merkmalskette nicht offen');
    return chain.accept(frame);
  }

  @override
  void reset() => _chain?.reset();

  @override
  Future<void> close() async {
    _epoch++;
    final loading = _loading;
    _loading = null;
    _chain?.runner.close();
    _chain = null;
    if (loading != null) {
      try {
        (await loading).close();
      } on Object {
        // Loading failed: nothing to release.
      }
    }
  }
}
