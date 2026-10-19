import 'package:meta/meta.dart';

/// What a speech model is used for.
enum SpeechModelKind {
  /// Whisper speech recognition.
  stt,

  /// Silero voice activity detection.
  vad,

  /// sherpa-onnx (Piper/VITS) voice.
  tts,

  /// Wake word feature models (openWakeWord mel + embedding).
  wake,
}

/// Which sherpa-onnx recognizer runs a [SpeechModelKind.stt] model (WP103):
/// a different choice of model only changes catalog entries.
enum SttEngine {
  /// Whisper encoder/decoder (`*-encoder*`, `*-decoder*`, `*tokens.txt`).
  whisper,

  /// NeMo transducer (Parakeet; `encoder`, `decoder`, `joiner`, `tokens`).
  /// The only engine that takes hotwords.
  nemoTransducer,

  /// NeMo Canary encoder/decoder with a source language (`srcLang`).
  canary,
}

/// Which sherpa-onnx synthesizer runs a [SpeechModelKind.tts] model.
enum TtsSynth {
  /// Piper/VITS voice (one voice per model).
  piper,

  /// Kokoro (many speakers in one model, chosen with a speaker id).
  kokoro,
}

/// One speaker of a multi-speaker voice model (Kokoro, WP103).
@immutable
final class TtsSpeaker {
  /// Creates a speaker.
  const TtsSpeaker({
    required this.id,
    required this.language,
    required this.name,
    required this.sid,
    required this.espeakLang,
    this.gender,
  });

  /// Stable id inside the model (e.g. `af_heart`).
  final String id;

  /// Language (BCP 47 primary subtag) the speaker speaks.
  final String language;

  /// Display name (German).
  final String name;

  /// Speaker number in the model's `voices.bin`.
  final int sid;

  /// Language code for the phonemizer (`en-us`, `en-gb`, `fr`).
  final String espeakLang;

  /// Gender, if known.
  final VoiceGender? gender;
}

/// Gender of a voice (for the choice of offline voices, WP66).
enum VoiceGender {
  /// Female voice.
  female,

  /// Male voice.
  male,
}

/// How a downloaded file must be unpacked by the platform.
enum ModelArchive {
  /// Used as is.
  none,

  /// `.tar.bz2` archive; the platform unpacks it after the download.
  tarBz2,
}

/// One downloadable file of a model.
@immutable
final class ModelFile {
  /// Creates a file entry.
  const ModelFile({
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    this.archive = ModelArchive.none,
  });

  /// File name inside the model directory (no path separators).
  final String name;

  /// Download URL (pinned to a revision where the host allows it).
  final String url;

  /// Exact size in bytes.
  final int sizeBytes;

  /// Expected SHA-256 as lower-case hex.
  final String sha256;

  /// Whether the file is an archive to unpack.
  final ModelArchive archive;

  @override
  String toString() => 'ModelFile($name, $sizeBytes B)';
}

/// A downloadable speech model (never shipped in the APK).
@immutable
final class SpeechModel {
  /// Creates a model entry.
  const SpeechModel({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.languages,
    required this.files,
    required this.license,
    required this.source,
    this.note,
    this.attribution,
    this.gender,
    this.engine = SttEngine.whisper,
    this.ramBytes,
    this.synth = TtsSynth.piper,
    this.speakers = const [],
    this.hint,
  });

  /// Stable id, also the directory name in the `ModelStore`.
  final String id;

  /// Use.
  final SpeechModelKind kind;

  /// Name for the settings (German).
  final String displayName;

  /// Languages (BCP 47); empty = language independent (VAD).
  final Set<String> languages;

  /// Files to download.
  final List<ModelFile> files;

  /// License of the model.
  final String license;

  /// Where URL, size and checksum come from.
  final String source;

  /// Caveats (e.g. checksum taken from host metadata, not re-hashed).
  final String? note;

  /// Mandatory attribution (license requirement) that the app must show
  /// on its license page when the model is offered; `null` = none needed.
  final String? attribution;

  /// Gender of a [SpeechModelKind.tts] voice; `null` for other models.
  final VoiceGender? gender;

  /// Recognizer engine of a [SpeechModelKind.stt] model.
  final SttEngine engine;

  /// Approximate peak RAM while loaded (for the choice in the settings);
  /// `null` = not stated. Measured on a Mac in WP102, the phone is higher.
  final int? ramBytes;

  /// Synthesizer of a [SpeechModelKind.tts] model.
  final TtsSynth synth;

  /// Speakers of a multi-speaker model ([TtsSynth.kokoro]); empty for
  /// single-voice models. The first one per language is the default.
  final List<TtsSpeaker> speakers;

  /// Short hint for the choice in the settings (German, e.g. „schnell,
  /// eigene Begriffe“); `null` = none.
  final String? hint;

  /// The speakers of [language] (primary subtag).
  List<TtsSpeaker> speakersFor(String language) => [
    for (final s in speakers)
      if (s.language == language) s,
  ];

  /// Whether the engine takes hotwords (own terms as a hint, WP103).
  bool get supportsHotwords => engine == SttEngine.nemoTransducer;

  /// Total download size.
  int get sizeBytes => files.fold(0, (n, f) => n + f.sizeBytes);

  @override
  String toString() => 'SpeechModel($id, ${kind.name}, $sizeBytes B)';
}
