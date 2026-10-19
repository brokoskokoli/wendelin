import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'sherpa_runtime.dart';
import 'whisper_sherpa.dart';
import 'whisper_stt.dart';

/// Hotwords for a NeMo transducer: the file with the names and the
/// `bpe_vocab` sherpa-onnx needs to encode them (WP103).
@immutable
final class NemoHotwords {
  /// Creates the paths.
  const NemoHotwords({
    required this.file,
    required this.bpeVocab,
    this.score = defaultHotwordsScore,
  });

  /// Hotwords file (one name per line).
  final String file;

  /// `bpe_vocab` derived from `tokens.txt`.
  final String bpeVocab;

  /// Boost of a hotword in `modified_beam_search`.
  final double score;
}

/// Writes the hotwords files for [terms] into [directory] (created) and
/// returns them, or `null` if no name can be spelled by the vocabulary of
/// [tokens] (then the model runs without hotwords).
///
/// The files carry the user's names: they stay in the app's own model
/// directory and are rewritten on every vocabulary change.
NemoHotwords? writeNemoHotwords({
  required String tokens,
  required Iterable<String> terms,
  required Directory directory,
  double score = defaultHotwordsScore,
}) {
  final tokensText = File(tokens).readAsStringSync();
  final content = buildHotwordsFile(terms, BpeEncoder.fromTokens(tokensText));
  if (content.isEmpty) return null;
  directory.createSync(recursive: true);
  final file = File('${directory.path}/hotwords.txt')
    ..writeAsStringSync(content);
  final vocab = File('${directory.path}/bpe.vocab')
    ..writeAsStringSync(buildBpeVocab(tokensText));
  return NemoHotwords(file: file.path, bpeVocab: vocab.path, score: score);
}

/// Paths of an unpacked NeMo model (sherpa-onnx export): Parakeet
/// transducer or Canary.
@immutable
final class NemoFiles implements SttSpec {
  /// Creates the paths.
  const NemoFiles({
    required this.engine,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.joiner = '',
    this.hotwords,
    this.fallbackLanguage = 'de',
  });

  /// The files of [model] under [directory] (the archive unpacks to a
  /// folder named like the archive), or `null` if a file is missing.
  static NemoFiles? find(
    SpeechModel model,
    String directory, {
    NemoHotwords? hotwords,
  }) {
    if (model.engine == SttEngine.whisper) return null;
    final base = model.files.first.name.replaceFirst(
      RegExp(r'\.tar\.bz2$'),
      '',
    );
    final dir = Directory('$directory/$base');
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().map((f) => f.path).toList();
    String? pick(bool Function(String name) test) {
      for (final f in files) {
        if (test(f.split('/').last)) return f;
      }
      return null;
    }

    bool onnx(String name, String part) =>
        name.contains(part) && name.endsWith('.onnx');
    final encoder = pick((n) => onnx(n, 'encoder'));
    final decoder = pick((n) => onnx(n, 'decoder'));
    final joiner = pick((n) => onnx(n, 'joiner'));
    final tokens = pick((n) => n == 'tokens.txt');
    final transducer = model.engine == SttEngine.nemoTransducer;
    if (encoder == null ||
        decoder == null ||
        tokens == null ||
        (transducer && joiner == null)) {
      return null;
    }
    return NemoFiles(
      engine: model.engine,
      encoder: encoder,
      decoder: decoder,
      joiner: joiner ?? '',
      tokens: tokens,
      hotwords: transducer ? hotwords : null,
    );
  }

  /// [SttEngine.nemoTransducer] or [SttEngine.canary].
  final SttEngine engine;

  /// Encoder `.onnx`.
  final String encoder;

  /// Decoder `.onnx`.
  final String decoder;

  /// Joiner `.onnx` (transducer only).
  final String joiner;

  /// `tokens.txt`.
  final String tokens;

  /// Hotwords (transducer only); `null` = none.
  final NemoHotwords? hotwords;

  /// Canary needs a language; this is used when none is fixed (the
  /// models cannot detect it).
  final String fallbackLanguage;

  @override
  List<String> get paths => [
    encoder,
    decoder,
    if (engine == SttEngine.nemoTransducer) joiner,
    tokens,
    if (hotwords != null) ...[hotwords!.file, hotwords!.bpeVocab],
  ];

  @override
  Map<String, int> get sizes => const {};

  @override
  BlockingStt open(int? threads) => SherpaNemoEngine(this, threads: threads);
}

/// Languages Canary 180M flash knows.
const canaryLanguages = {'en', 'es', 'de', 'fr'};

/// NeMo recognizer on the current isolate (blocking FFI calls).
final class SherpaNemoEngine implements BlockingStt {
  /// Loads the model.
  SherpaNemoEngine(this.files, {int? threads})
    : threads = threads ?? math.min(4, Platform.numberOfProcessors) {
    ensureSherpaBindings();
    _language = files.fallbackLanguage;
    _recognizer = so.OfflineRecognizer(config(_language));
  }

  /// Model files.
  final NemoFiles files;

  /// CPU threads for onnxruntime.
  final int threads;

  late final so.OfflineRecognizer _recognizer;
  late String _language;

  /// The sherpa-onnx configuration for [language].
  /// The sherpa-onnx configuration for [language].
  so.OfflineRecognizerConfig config(String language) =>
      nemoRecognizerConfig(files, language: language, threads: threads);

  @override
  WhisperResult transcribe(Float32List samples, {String? language}) {
    var lang = language ?? files.fallbackLanguage;
    if (files.engine == SttEngine.canary) {
      if (!canaryLanguages.contains(lang)) lang = files.fallbackLanguage;
      if (lang != _language) {
        _recognizer.setConfig(config(lang));
        _language = lang;
      }
    }
    final stream = _recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      _recognizer.decode(stream);
      final r = _recognizer.getResult(stream);
      return WhisperResult(
        text: r.text,
        language: files.engine == SttEngine.canary ? lang : r.lang,
      );
    } finally {
      stream.free();
    }
  }

  @override
  void dispose() => _recognizer.free();
}

/// The sherpa-onnx configuration for [files]; [language] is the source and
/// target language of Canary (ignored by the transducer).
so.OfflineRecognizerConfig nemoRecognizerConfig(
  NemoFiles files, {
  required String language,
  required int threads,
}) {
  final hotwords = files.hotwords;
  if (files.engine == SttEngine.canary) {
    return so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        canary: so.OfflineCanaryModelConfig(
          encoder: files.encoder,
          decoder: files.decoder,
          srcLang: language,
          tgtLang: language,
        ),
        tokens: files.tokens,
        numThreads: threads,
        debug: false,
      ),
    );
  }
  return so.OfflineRecognizerConfig(
    model: so.OfflineModelConfig(
      transducer: so.OfflineTransducerModelConfig(
        encoder: files.encoder,
        decoder: files.decoder,
        joiner: files.joiner,
      ),
      tokens: files.tokens,
      numThreads: threads,
      modelType: 'nemo_transducer',
      // `bpe` without `bpeVocab` ends the process inside sherpa-onnx.
      modelingUnit: hotwords == null ? '' : 'bpe',
      bpeVocab: hotwords?.bpeVocab ?? '',
      debug: false,
    ),
    decodingMethod: hotwords == null ? 'greedy_search' : 'modified_beam_search',
    hotwordsFile: hotwords?.file ?? '',
    hotwordsScore: hotwords?.score ?? defaultHotwordsScore,
  );
}
