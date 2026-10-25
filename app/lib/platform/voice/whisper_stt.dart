import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'pcm.dart';

/// Raw output of one Whisper run.
@immutable
final class WhisperResult {
  /// Creates a result.
  const WhisperResult({
    required this.text,
    this.language = '',
    this.meanLogProb,
    this.diag = const SttRunDiag(),
  });

  /// Recognized text as returned by the model.
  final String text;

  /// Language code the model used or detected (`de`, `fr`, `en`, … or
  /// empty).
  final String language;

  /// Mean log probability of the output tokens (`ys_log_probs` of
  /// sherpa-onnx), `null` if the model does not report it. Only logged
  /// (`stt-lang lp=`), never used to block (WP140).
  final double? meanLogProb;

  /// Numbers and codes about the run for the log (WP146), see [SttRunDiag].
  final SttRunDiag diag;

  /// The same result, with [diag] replaced.
  WhisperResult withDiag(SttRunDiag diag) => WhisperResult(
    text: text,
    language: language,
    meanLogProb: meanLogProb,
    diag: diag,
  );
}

/// What the log line of a transcription says about the run beside the text
/// (WP146). Numbers and codes only: how many hint terms were configured and
/// found, never which.
@immutable
final class SttRunDiag {
  /// Creates the diagnostics; unknown values stay `null`.
  const SttRunDiag({
    this.minLogProb,
    this.decoding,
    this.hotwords,
    this.hotwordsScore,
    this.hotwordHits,
    this.owner,
    this.instance,
  });

  /// Smallest log probability of one output token (a single wrong token
  /// shows here, the mean hides it).
  final double? minLogProb;

  /// `greedy` or `beam` (`modified_beam_search`).
  final String? decoding;

  /// Number of hotwords the model was loaded with.
  final int? hotwords;

  /// Hotword bonus the model was loaded with.
  final double? hotwordsScore;

  /// Number of hotwords found in the raw text (a count, never the term).
  final int? hotwordHits;

  /// Engine (`app`, `overlay`, `recognizer`, `wake`) whose isolate ran the
  /// model.
  final String? owner;

  /// `own` (the caller's model) or `shared` (another engine's model).
  final String? instance;

  /// The same with [instance] set.
  SttRunDiag withInstance(String instance) => SttRunDiag(
    minLogProb: minLogProb,
    decoding: decoding,
    hotwords: hotwords,
    hotwordsScore: hotwordsScore,
    hotwordHits: hotwordHits,
    owner: owner,
    instance: instance,
  );

  /// The same with [owner] set.
  SttRunDiag withOwner(String owner) => SttRunDiag(
    minLogProb: minLogProb,
    decoding: decoding,
    hotwords: hotwords,
    hotwordsScore: hotwordsScore,
    hotwordHits: hotwordHits,
    owner: owner,
    instance: instance,
  );

  /// Message form for the isolate boundary.
  List<Object?> toList() => [
    minLogProb,
    decoding,
    hotwords,
    hotwordsScore,
    hotwordHits,
    owner,
  ];

  /// Reads [toList]; anything else gives the empty value.
  static SttRunDiag fromList(Object? v) => switch (v) {
    [
      final double? min,
      final String? dec,
      final int? hw,
      final double? score,
      final int? hits,
      final String? owner,
    ] =>
      SttRunDiag(
        minLogProb: min,
        decoding: dec,
        hotwords: hw,
        hotwordsScore: score,
        hotwordHits: hits,
        owner: owner,
      ),
    _ => const SttRunDiag(),
  };
}

/// Mean of the `ys_log_probs` in the result JSON of sherpa-onnx, `null`
/// when the field is missing, empty, not numeric or the JSON is invalid.
double? meanLogProbOf(String? json) => logProbsOf(json)?.mean;

/// Mean and smallest `ys_log_probs` of the result JSON (`null` as for
/// [meanLogProbOf]).
({double mean, double min})? logProbsOf(String? json) {
  if (json == null) return null;
  try {
    final probs = (jsonDecode(json) as Map<String, Object?>)['ys_log_probs'];
    if (probs is! List || probs.isEmpty) return null;
    var sum = 0.0;
    var min = double.infinity;
    for (final p in probs) {
      if (p is! num) return null;
      sum += p;
      if (p < min) min = p.toDouble();
    }
    return (mean: sum / probs.length, min: min);
  } on Object {
    return null;
  }
}

/// Duration of one Whisper run (for the log and measurements, WP19).
@immutable
final class WhisperTiming {
  /// Creates a timing.
  const WhisperTiming({
    required this.modelId,
    required this.audio,
    required this.compute,
    this.language,
  });

  /// Catalog id of the model.
  final String modelId;

  /// Length of the recording.
  final Duration audio;

  /// Time from handing over the audio to the text.
  final Duration compute;

  /// Fixed language (`null` = detected).
  final String? language;

  /// Compute time per audio time (real-time factor).
  double get rtf => audio == Duration.zero
      ? 0
      : compute.inMicroseconds / audio.inMicroseconds;

  /// Log line without any content: model, language, durations
  /// (`tool/whisper_timing.sh` reads it from logcat).
  @override
  String toString() =>
      'Whisper-Zeit $modelId ${language ?? 'auto'}: '
      'Audio ${audio.inMilliseconds} ms, '
      'Rechenzeit ${compute.inMilliseconds} ms, '
      'RTF ${rtf.toStringAsFixed(2)}';
}

/// Runs Whisper on float samples (16 kHz). On the device it lives in a
/// background isolate ([IsolateWhisperBackend]); tests use fakes.
abstract interface class WhisperBackend {
  /// Transcribes [samples]; [language] `null` = detect.
  Future<WhisperResult> transcribe(Float32List samples, {String? language});

  /// Frees the model.
  Future<void> dispose();
}

/// Whisper (sherpa-onnx) as [SpeechToText] (concept: STT stage).
///
/// - Languages are limited to [languages] (de/fr/en); a fixed language
///   outside of it throws `VoiceException(unsupportedLanguage)`.
/// - Empty audio and audio below [silenceLevel] (RMS, full scale = 1)
///   return an empty text without running the model: Whisper invents text
///   for silence („[Music]“, „Untertitel der Amara.org-Community“).
/// - The text is cleaned with [cleanWhisperText]; the confidence comes from
///   [whisperConfidence] (heuristic, sherpa-onnx reports no token
///   probabilities for Whisper).
final class WhisperSpeechToText implements SpeechToText {
  /// Creates the engine for catalog model [modelId].
  WhisperSpeechToText({
    required this.backend,
    required this.modelId,
    this.languages = const {'de', 'fr', 'en'},
    this.silenceLevel = 0.002,
    this.onTiming,
    this.engineName = 'Whisper (sherpa-onnx)',
  });

  /// Model runner.
  final WhisperBackend backend;

  /// Catalog id (`whisper-base`, `whisper-small`).
  final String modelId;

  /// Supported languages.
  final Set<String> languages;

  /// RMS level below which audio counts as silence (≈ −54 dBFS).
  final double silenceLevel;

  /// Engine name in [info] (`sttEngineName` of the model's engine).
  final String engineName;

  /// Called after every model run with its durations (never the text).
  final void Function(WhisperTiming timing)? onTiming;

  /// Durations of the last model run (`null` before the first one).
  WhisperTiming? get lastTiming => _lastTiming;
  WhisperTiming? _lastTiming;

  @override
  SpeechToTextEngineInfo get info => SpeechToTextEngineInfo(
    name: engineName,
    languages: languages,
    model: modelId,
  );

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    final fixed = language == null ? null : primaryLanguage(language);
    if (fixed != null && !languages.contains(fixed)) {
      throw VoiceException(
        VoiceErrorKind.unsupportedLanguage,
        'Die Sprache „$language“ erkennt Whisper hier nicht '
        '(nur ${languages.join(', ')}).',
      );
    }
    if (pcm.isEmpty || rmsLevel(pcm) < silenceLevel) {
      return Transcript(text: '', language: fixed);
    }
    final WhisperResult raw;
    final watch = Stopwatch()..start();
    try {
      raw = await backend.transcribe(pcmToFloat(pcm), language: fixed);
    } on Object catch (e) {
      throw VoiceException(
        VoiceErrorKind.failed,
        'Die Spracherkennung ist fehlgeschlagen.',
        cause: e,
      );
    }
    final timing = _lastTiming = WhisperTiming(
      modelId: modelId,
      audio: samplesToDuration(pcm.length),
      compute: watch.elapsed,
      language: fixed,
    );
    onTiming?.call(timing);
    final text = cleanWhisperText(raw.text);
    final d = raw.diag;
    final detected = primaryLanguage(raw.language);
    final lang = fixed ?? (languages.contains(detected) ? detected : null);
    final confidence = text.isEmpty
        ? null
        : whisperConfidence(
            text,
            audio: samplesToDuration(pcm.length),
            // An empty language (engines without detection, e.g. Parakeet)
            // is no evidence against the language: only a detected foreign
            // language counts as unsupported.
            languageSupported:
                fixed != null ||
                detected.isEmpty ||
                languages.contains(detected),
          );
    // Which language was used, never what was said.
    voiceLog('stt-lang', {
      'model': modelId,
      'src': fixed != null ? 'fixed' : 'detected',
      'lang': lang,
      'detected': detected.isEmpty ? null : detected,
      'conf': confidence,
      'lp': raw.meanLogProb,
      // WP146: which instance and settings produced the text (numbers and
      // codes only).
      'min': d.minLogProb,
      'audio': timing.audio,
      'ms': timing.compute,
      'inst': d.instance ?? 'own',
      'owner': d.owner,
      'dec': d.decoding,
      'hw': d.hotwords,
      'hws': d.hotwordsScore,
      'hits': d.hotwordHits,
    });
    if (text.isEmpty) return Transcript(text: '', language: lang);
    return Transcript(text: text, language: lang, confidence: confidence);
  }
}

/// Primary subtag of a BCP 47 tag in lower case (`de-AT` → `de`).
String primaryLanguage(String tag) =>
    tag.trim().split(RegExp('[-_]')).first.toLowerCase();

final _annotation = RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*|[♪♫]');
final _space = RegExp(r'\s+');

/// Subtitle credits and outro phrases Whisper is known to invent for noise
/// (the training data contained subtitles). They are never commands.
final _hallucinations = [
  RegExp(r'amara\.org', caseSensitive: false),
  RegExp(
    r'^untertitel(ung)?\b.*\b(zdf|ard|funk|im auftrag)\b',
    caseSensitive: false,
  ),
  RegExp(
    r"^sous-titr(age|es)\b.*(radio-canada|réalisés par|st' ?501)",
    caseSensitive: false,
  ),
  RegExp(r'^(thanks|thank you) for watching[.!]?$', caseSensitive: false),
  RegExp(r'^vielen dank fürs zuschauen[.!]?$', caseSensitive: false),
  RegExp(r'^merci d.avoir regardé[.!]?$', caseSensitive: false),
];

/// Whisper text without sound annotations (`[Music]`, `(Lachen)`, `*Musik*`,
/// `♪`) and known subtitle hallucinations; whitespace collapsed and trimmed.
String cleanWhisperText(String raw) {
  final text = raw.replaceAll(_annotation, ' ').replaceAll(_space, ' ').trim();
  if (_hallucinations.any((h) => h.hasMatch(text))) return '';
  // Only punctuation left (e.g. „...“).
  if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) return '';
  return text;
}

/// Heuristic confidence (0–1) of a Whisper transcript.
///
/// Starts at 0.9 and lowers it for signs of a bad recognition:
/// - text rate below 1.5 characters per second in a recording of at least
///   3 s (missed speech) or above 30 (invented text),
/// - repetition loops (the same word four times in a row or a word
///   trigram three times),
/// - a detected language outside the supported ones.
double whisperConfidence(
  String text, {
  required Duration audio,
  bool languageSupported = true,
}) {
  var c = 0.9;
  final seconds = audio.inMilliseconds / 1000;
  if (seconds >= 1) {
    final cps = text.length / seconds;
    // Recordings carry ~1.1 s of pre-roll and end silence, so a short
    // answer („Ja“) is only suspicious in a long recording.
    if (seconds >= 3 && cps < 1.5) c *= 0.6;
    if (cps > 30) c *= 0.5;
  }
  if (_repeats(text)) c *= 0.4;
  if (!languageSupported) c *= 0.5;
  return c.clamp(0, 1).toDouble();
}

bool _repeats(String text) {
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  var run = 1;
  for (var i = 1; i < words.length; i++) {
    run = words[i] == words[i - 1] ? run + 1 : 1;
    if (run >= 4) return true;
  }
  final counts = <String, int>{};
  for (var i = 0; i + 2 < words.length; i++) {
    final key = '${words[i]} ${words[i + 1]} ${words[i + 2]}';
    final n = (counts[key] ?? 0) + 1;
    if (n >= 3) return true;
    counts[key] = n;
  }
  return false;
}
