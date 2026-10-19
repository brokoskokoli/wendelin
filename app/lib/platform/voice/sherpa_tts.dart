import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'isolate_exit.dart';
import 'pcm.dart';
import 'sherpa_runtime.dart';

/// Files of an unpacked Piper/VITS or Kokoro voice (sherpa-onnx export).
@immutable
final class PiperVoiceFiles {
  /// Creates the paths.
  const PiperVoiceFiles({
    required this.model,
    required this.tokens,
    required this.dataDir,
    this.voicesBin,
    this.dictDir,
    this.lexicon,
  });

  /// Finds the voice in [directory]: the archive's top folder with one
  /// `*.onnx`, `tokens.txt` and `espeak-ng-data/` (Kokoro: also
  /// `voices.bin`, and `dict/` and `lexicon-us-en.txt` if present).
  /// Returns `null` if something is missing.
  static PiperVoiceFiles? find(Directory directory) {
    if (!directory.existsSync()) return null;
    final dirs = [directory, ...directory.listSync().whereType<Directory>()];
    for (final d in dirs) {
      final onnx = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.onnx'))
          .toList();
      final tokens = File('${d.path}/tokens.txt');
      final data = Directory('${d.path}/espeak-ng-data');
      if (onnx.length == 1 && tokens.existsSync() && data.existsSync()) {
        return PiperVoiceFiles(
          model: onnx.single.path,
          tokens: tokens.path,
          dataDir: data.path,
          voicesBin: File('${d.path}/voices.bin').existsSync()
              ? '${d.path}/voices.bin'
              : null,
          dictDir: Directory('${d.path}/dict').existsSync()
              ? '${d.path}/dict'
              : null,
          lexicon: File('${d.path}/lexicon-us-en.txt').existsSync()
              ? '${d.path}/lexicon-us-en.txt'
              : null,
        );
      }
    }
    return null;
  }

  /// Voice `.onnx`.
  final String model;

  /// `tokens.txt`.
  final String tokens;

  /// `espeak-ng-data` directory.
  final String dataDir;

  /// Kokoro `voices.bin`; `null` = a Piper voice.
  final String? voicesBin;

  /// Kokoro `dict/` directory (Chinese segmentation), if present.
  final String? dictDir;

  /// Kokoro English lexicon, if present (used for English only).
  final String? lexicon;
}

/// Turns text into audio (in a background isolate on the device).
abstract interface class SpeechSynthesizer {
  /// Audio for [text] with voice [voiceId] at [speed] (1.0 = normal).
  Future<Wav> synthesize(String text, {required String voiceId, double speed});

  /// Frees all voices.
  Future<void> dispose();
}

/// Plays audio; [play] completes when playback ended or was stopped.
abstract interface class AudioPlayback {
  /// Plays [wav].
  Future<void> play(Wav wav);

  /// Stops the current playback.
  Future<void> stop();
}

/// An installed offline voice.
@immutable
final class SherpaVoice {
  /// Creates the voice.
  const SherpaVoice({
    required this.id,
    required this.language,
    required this.name,
    required this.files,
    this.speakers = const [],
  });

  /// Speakers of the voice for [language] (Kokoro); empty for Piper.
  final List<TtsSpeaker> speakers;

  /// Catalog id (e.g. `tts-de-thorsten`).
  final String id;

  /// Language (BCP 47 primary subtag).
  final String language;

  /// Display name.
  final String name;

  /// Model files.
  final PiperVoiceFiles files;
}

/// Offline speech output with sherpa-onnx (Piper/VITS voices, K7
/// fallback when no system TTS is installed).
///
/// [voices] returns the installed voices; without a voice id [speak] picks
/// the voice for the language (or the first one). Synthesis and playback
/// run one utterance after the other; [stop] ends the current one and
/// drops the waiting ones.
final class SherpaTextToSpeech implements TextToSpeech {
  /// Creates the engine. [installed] lists the voices on disk (re-read on
  /// every call, so a finished download is picked up).
  SherpaTextToSpeech({
    required this.installed,
    required this.synthesizer,
    required this.playback,
    this.preferred,
    this.preferredSpeakers,
    this.onTiming,
  });

  /// Called after every synthesis with the voice id, the length of the
  /// audio and the compute time (numbers only, for the metrics, WP103).
  final void Function(String voiceId, Duration audio, Duration compute)?
  onTiming;

  /// Chosen speaker id per language (Kokoro, WP103); the first speaker of
  /// the language is used when missing or unknown.
  final Map<String, String> Function()? preferredSpeakers;

  /// Chosen voice id per language (primary subtag, WP66); used when no
  /// installed voice matches the requested id. A voice that is not
  /// installed (any more) is skipped.
  final Map<String, String> Function()? preferred;

  /// Installed voices.
  final Future<List<SherpaVoice>> Function() installed;

  /// Text → audio.
  final SpeechSynthesizer synthesizer;

  /// Audio output.
  final AudioPlayback playback;

  final _states = StreamController<TtsState>.broadcast(sync: true);
  TtsState _state = TtsState.idle;
  Future<void> _queue = Future.value();
  int _generation = 0;

  @override
  TtsState get state => _state;

  @override
  Stream<TtsState> get states => _states.stream;

  void _set(TtsState s) {
    if (_state == s) return;
    _state = s;
    _states.add(s);
  }

  @override
  Future<bool> get isAvailable async => (await installed()).isNotEmpty;

  @override
  Future<List<TtsVoice>> voices() async => [
    for (final v in await installed())
      TtsVoice(id: v.id, language: v.language, name: v.name),
  ];

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    if (rate <= 0) throw ArgumentError.value(rate, 'rate', 'muss > 0 sein');
    if (text.trim().isEmpty) return Future.value();
    final generation = _generation;
    final run = _queue.then((_) async {
      if (generation != _generation) return;
      final chosen = _pick(
        await installed(),
        voice,
        language,
        preferred?.call() ?? const {},
      );
      if (chosen == null) {
        throw const VoiceException(
          VoiceErrorKind.modelMissing,
          'Es ist keine Offline-Stimme geladen.',
        );
      }
      _set(TtsState.speaking);
      try {
        final speaker = _speaker(chosen, preferredSpeakers?.call());
        final voiceId = speaker == null
            ? chosen.id
            : '${chosen.id}/${speaker.id}';
        final watch = Stopwatch()..start();
        final wav = await synthesizer.synthesize(
          text,
          voiceId: voiceId,
          speed: rate,
        );
        onTiming?.call(voiceId, wav.duration, watch.elapsed);
        if (generation != _generation) return;
        await playback.play(wav);
      } finally {
        _set(TtsState.idle);
      }
    });
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static TtsSpeaker? _speaker(SherpaVoice v, Map<String, String>? chosen) {
    if (v.speakers.isEmpty) return null;
    for (final s in v.speakers) {
      if (s.id == chosen?[v.language]) return s;
    }
    return v.speakers.first;
  }

  static SherpaVoice? _pick(
    List<SherpaVoice> voices,
    String? id,
    String? language,
    Map<String, String> preferred,
  ) {
    if (voices.isEmpty) return null;
    final lang = language?.split(RegExp('[-_]')).first.toLowerCase();
    if (id != null) {
      // A multi-language voice is listed once per language.
      for (final v in voices) {
        if (v.id == id && (lang == null || v.language == lang)) return v;
      }
      for (final v in voices) {
        if (v.id == id) return v;
      }
    }
    if (lang != null) {
      final inLanguage = [
        for (final v in voices)
          if (v.language == lang) v,
      ];
      final effective = effectiveSherpaVoice(
        chosen: preferred[lang],
        available: [for (final v in inLanguage) v.id],
      );
      for (final v in inLanguage) {
        if (v.id == effective) return v;
      }
    }
    return voices.first;
  }

  @override
  Future<void> stop() async {
    _generation++;
    if (_state == TtsState.idle) return;
    try {
      await playback.stop();
    } on Object {
      // Nothing playing any more.
    }
  }
}

/// [SpeechSynthesizer] with sherpa-onnx in a background isolate; a voice
/// is loaded on first use and kept until another voice is needed (only
/// the last one stays resident, B14).
final class IsolateSherpaSynthesizer implements SpeechSynthesizer {
  /// Creates the synthesizer; [voices] maps voice ids to their files.
  IsolateSherpaSynthesizer(this.voices);

  /// Voice files by model id (resolved on every call). A voice id for the
  /// synthesizer is the model id, for a multi-speaker model
  /// `<model id>/<speaker id>`.
  final Future<Map<String, PiperVoiceFiles>> Function() voices;

  Future<(WorkerIsolate, SendPort, StreamIterator<Object?>)>? _worker;
  Future<void> _queue = Future.value();

  /// How long [dispose] waits for the isolate to free the voices and exit
  /// before it is killed.
  Duration exitGrace = const Duration(seconds: 5);

  Future<(WorkerIsolate, SendPort, StreamIterator<Object?>)> _start() async {
    voiceLog('model-load', {'kind': 'tts-sherpa'});
    final replies = ReceivePort();
    final worker = await WorkerIsolate.spawn(_main, (
      replies.sendPort,
      sherpaLibraryDir,
    ), debugName: 'sherpa-tts');
    final events = StreamIterator<Object?>(replies);
    await events.moveNext();
    return (worker, events.current! as SendPort, events);
  }

  static (String, String?) _split(String voiceId) {
    final i = voiceId.indexOf('/');
    return i < 0
        ? (voiceId, null)
        : (voiceId.substring(0, i), voiceId.substring(i + 1));
  }

  /// The background isolate; `null` before the first synthesis.
  @visibleForTesting
  Future<WorkerIsolate>? get worker => _worker?.then((w) => w.$1);

  @override
  Future<Wav> synthesize(
    String text, {
    required String voiceId,
    double speed = 1.0,
  }) {
    final result = _queue.then((_) async {
      final (modelId, speakerId) = _split(voiceId);
      final files = (await voices())[modelId];
      if (files == null) {
        throw VoiceException(
          VoiceErrorKind.modelMissing,
          'Die Stimme $voiceId ist nicht geladen.',
        );
      }
      final (_, port, replies) = await (_worker ??= _start());
      final speaker = speakerId == null
          ? null
          : SpeechModelCatalog.standard
                .byId(modelId)
                ?.speakers
                .where((s) => s.id == speakerId)
                .firstOrNull;
      port.send((
        voiceId,
        files.model,
        files.tokens,
        files.dataDir,
        text,
        speed,
        files.voicesBin,
        files.dictDir,
        files.lexicon,
        speaker?.espeakLang,
        speaker?.sid ?? 0,
      ));
      await replies.moveNext();
      final reply = replies.current;
      if (reply is (TransferableTypedData, int)) {
        final samples = reply.$1.materialize().asFloat32List();
        return Wav(floatToPcm(samples), sampleRate: reply.$2);
      }
      throw VoiceException(
        VoiceErrorKind.failed,
        'Die Offline-Stimme ist fehlgeschlagen.',
        cause: reply,
      );
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> dispose() async {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    await _queue;
    final (isolate, port, replies) = await worker;
    port.send(null);
    await replies.cancel();
    // The isolate frees the voices and exits; kill only after the grace.
    await isolate.awaitExit(grace: exitGrace);
    voiceLog('model-free', {'kind': 'tts-sherpa'});
  }

  static void _main((SendPort, String?) args) {
    final (out, libraryDir) = args;
    sherpaLibraryDir = libraryDir;
    final inbox = ReceivePort();
    // Only the voice used last stays loaded (B14): a language change frees
    // the previous one first.
    String? loadedId;
    so.OfflineTts? loaded;
    out.send(inbox.sendPort);
    inbox.listen((message) {
      if (message
          is (
            String,
            String,
            String,
            String,
            String,
            double,
            String?,
            String?,
            String?,
            String?,
            int,
          )) {
        final (
          id,
          model,
          tokens,
          dataDir,
          text,
          speed,
          voicesBin,
          dictDir,
          lexicon,
          lang,
          sid,
        ) = message;
        try {
          ensureSherpaBindings();
          // Kokoro binds the phonemizer language at load time: one load per
          // language (the speaker id is a per-call argument).
          final loadKey = voicesBin == null ? id : '$id@$lang';
          if (loadedId != loadKey) {
            loaded?.free();
            loaded = null;
            loadedId = null;
          }
          final tts = loaded ??= so.OfflineTts(
            sherpaTtsConfig(
              model: model,
              tokens: tokens,
              dataDir: dataDir,
              voicesBin: voicesBin,
              dictDir: dictDir,
              lexicon: lexicon,
              lang: lang,
            ),
          );
          loadedId = loadKey;
          final audio = tts.generate(text: text, sid: sid, speed: speed);
          out.send((
            TransferableTypedData.fromList([
              audio.samples.buffer.asUint8List(),
            ]),
            audio.sampleRate,
          ));
        } on Object catch (e) {
          out.send('$e');
        }
      } else {
        loaded?.free();
        inbox.close();
        Isolate.exit();
      }
    });
  }
}

/// Config of a Piper (VITS) voice, or of a Kokoro voice when [voicesBin] is
/// given ([lang] = phonemizer language, [lexicon] only for English). The noise parameters stay at the sherpa
/// defaults on purpose (WP74: measured, they change the pause noise by
/// at most 1.5 dB; the noise comes from the int8 models).
@visibleForTesting
so.OfflineTtsConfig sherpaTtsConfig({
  required String model,
  required String tokens,
  required String dataDir,
  String? voicesBin,
  String? dictDir,
  String? lexicon,
  String? lang,
}) => so.OfflineTtsConfig(
  model: so.OfflineTtsModelConfig(
    vits: voicesBin != null
        ? const so.OfflineTtsVitsModelConfig()
        : so.OfflineTtsVitsModelConfig(
            model: model,
            tokens: tokens,
            dataDir: dataDir,
          ),
    kokoro: voicesBin == null
        ? const so.OfflineTtsKokoroModelConfig()
        : so.OfflineTtsKokoroModelConfig(
            model: model,
            voices: voicesBin,
            tokens: tokens,
            dataDir: dataDir,
            dictDir: dictDir ?? '',
            lexicon: lang != null && lang.startsWith('en')
                ? (lexicon ?? '')
                : '',
            lang: lang ?? '',
          ),
    numThreads: 2,
    debug: false,
  ),
);
