import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'pcm.dart';

/// Raw output of one Whisper run.
@immutable
final class WhisperResult {
  /// Creates a result.
  const WhisperResult({required this.text, this.language = ''});

  /// Recognized text as returned by the model.
  final String text;

  /// Language code the model used or detected (`de`, `fr`, `en`, … or
  /// empty).
  final String language;
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
  });

  /// Model runner.
  final WhisperBackend backend;

  /// Catalog id (`whisper-base`, `whisper-small`).
  final String modelId;

  /// Supported languages.
  final Set<String> languages;

  /// RMS level below which audio counts as silence (≈ −54 dBFS).
  final double silenceLevel;

  @override
  SpeechToTextEngineInfo get info => SpeechToTextEngineInfo(
    name: 'Whisper (sherpa-onnx)',
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
    try {
      raw = await backend.transcribe(pcmToFloat(pcm), language: fixed);
    } on Object catch (e) {
      throw VoiceException(
        VoiceErrorKind.failed,
        'Die Spracherkennung ist fehlgeschlagen.',
        cause: e,
      );
    }
    final text = cleanWhisperText(raw.text);
    final detected = primaryLanguage(raw.language);
    final lang = fixed ?? (languages.contains(detected) ? detected : null);
    if (text.isEmpty) return Transcript(text: '', language: lang);
    return Transcript(
      text: text,
      language: lang,
      confidence: whisperConfidence(
        text,
        audio: samplesToDuration(pcm.length),
        languageSupported: fixed != null || languages.contains(detected),
      ),
    );
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
