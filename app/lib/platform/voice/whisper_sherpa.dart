import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'isolate_exit.dart';
import 'sherpa_runtime.dart';
import 'whisper_share.dart';
import 'whisper_stt.dart';

/// Paths of a downloaded Whisper model (sherpa-onnx export).
@immutable
final class WhisperFiles {
  /// Creates the paths.
  const WhisperFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.sizes = const {},
  });

  /// The files of catalog model [model] in [directory] (`*-encoder*`,
  /// `*-decoder*`, `*tokens.txt`).
  factory WhisperFiles.of(SpeechModel model, String directory) {
    String pick(bool Function(String) test) => [
      for (final f in model.files)
        if (test(f.name)) '$directory/${f.name}',
    ].single;
    return WhisperFiles(
      encoder: pick((n) => n.contains('-encoder')),
      decoder: pick((n) => n.contains('-decoder')),
      tokens: pick((n) => n.endsWith('tokens.txt')),
      sizes: {for (final f in model.files) '$directory/${f.name}': f.sizeBytes},
    );
  }

  /// Expected size per path (from the catalog); checked before loading.
  final Map<String, int> sizes;

  /// Encoder `.onnx`.
  final String encoder;

  /// Decoder `.onnx`.
  final String decoder;

  /// `tokens.txt`.
  final String tokens;
}

/// Whisper on the current isolate (blocking FFI calls). Used inside
/// [IsolateWhisperBackend] and by the measurement tool.
final class SherpaWhisperEngine {
  /// Loads the model (takes a few hundred milliseconds).
  SherpaWhisperEngine(this.files, {int? threads})
    : threads = threads ?? math.min(4, Platform.numberOfProcessors) {
    ensureSherpaBindings();
    _recognizer = so.OfflineRecognizer(_config(''));
  }

  /// Model files.
  final WhisperFiles files;

  /// CPU threads for onnxruntime.
  final int threads;

  late final so.OfflineRecognizer _recognizer;
  String _language = '';

  so.OfflineRecognizerConfig _config(String language) =>
      so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          whisper: so.OfflineWhisperModelConfig(
            encoder: files.encoder,
            decoder: files.decoder,
            language: language,
            task: 'transcribe',
          ),
          tokens: files.tokens,
          numThreads: threads,
          debug: false,
        ),
      );

  /// Transcribes [samples]; [language] `null` = detect.
  WhisperResult transcribe(Float32List samples, {String? language}) {
    final lang = language ?? '';
    if (lang != _language) {
      _recognizer.setConfig(_config(lang));
      _language = lang;
    }
    final stream = _recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      _recognizer.decode(stream);
      final r = _recognizer.getResult(stream);
      return WhisperResult(text: r.text, language: r.lang);
    } finally {
      stream.free();
    }
  }

  /// Frees the native recognizer.
  void dispose() => _recognizer.free();
}

/// [WhisperBackend] in a long-lived background isolate, so a transcription
/// (0.3–3 s on a phone) never blocks the UI. Requests are handled one after
/// the other.
final class IsolateWhisperBackend implements WhisperBackend {
  IsolateWhisperBackend._(this._isolate, this._requests, this._replies);

  /// Spawns the isolate and loads [files] there. Throws
  /// `VoiceException(modelMissing)` if a file is missing and
  /// `VoiceException(failed)` if the model does not load.
  static Future<IsolateWhisperBackend> start(
    WhisperFiles files, {
    int? threads,
  }) async {
    for (final p in [files.encoder, files.decoder, files.tokens]) {
      final f = File(p);
      final size = files.sizes[p];
      // A truncated model would end the process inside sherpa-onnx.
      if (!f.existsSync() || (size != null && f.lengthSync() != size)) {
        throw const VoiceException(
          VoiceErrorKind.modelMissing,
          'Das Whisper-Modell ist nicht (vollständig) geladen.',
        );
      }
    }
    final replies = ReceivePort();
    final worker = await WorkerIsolate.spawn(_main, (
      replies.sendPort,
      files.encoder,
      files.decoder,
      files.tokens,
      threads,
      sherpaLibraryDir,
    ), debugName: 'whisper');
    final events = StreamIterator(replies);
    await events.moveNext();
    final first = events.current;
    if (first is! SendPort) {
      replies.close();
      worker.kill();
      throw VoiceException(
        VoiceErrorKind.failed,
        'Das Whisper-Modell ließ sich nicht laden.',
        cause: first,
      );
    }
    return IsolateWhisperBackend._(worker, first, events);
  }

  final WorkerIsolate _isolate;

  /// How long [dispose] waits for the isolate to free the model and exit
  /// before it is killed.
  static Duration exitGrace = const Duration(seconds: 5);
  final SendPort _requests;
  final StreamIterator<Object?> _replies;
  Future<void> _queue = Future.value();
  bool _closed = false;

  @override
  Future<WhisperResult> transcribe(Float32List samples, {String? language}) {
    if (_closed) throw StateError('Whisper ist bereits beendet.');
    final result = _queue.then((_) async {
      _requests.send((
        TransferableTypedData.fromList([samples.buffer.asUint8List()]),
        language,
      ));
      await _replies.moveNext();
      final reply = _replies.current;
      if (reply is (String, String)) {
        return WhisperResult(text: reply.$1, language: reply.$2);
      }
      throw StateError('Whisper-Isolat: $reply');
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Inbox of the Whisper isolate; it also answers [RemoteWhisperBackend]
  /// requests of other engines (`publishSharedWhisper`, ADR 0008).
  SendPort get sharePort => _requests;

  /// The background isolate (for tests: did it exit by itself?).
  @visibleForTesting
  WorkerIsolate get worker => _isolate;

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _queue;
    _requests.send(null);
    await _replies.cancel();
    // The isolate frees the model and exits; kill only after the grace.
    await _isolate.awaitExit(grace: exitGrace);
  }

  static void _main((SendPort, String, String, String, int?, String?) args) {
    final (out, encoder, decoder, tokens, threads, libraryDir) = args;
    sherpaLibraryDir = libraryDir;
    final SherpaWhisperEngine engine;
    try {
      engine = SherpaWhisperEngine(
        WhisperFiles(encoder: encoder, decoder: decoder, tokens: tokens),
        threads: threads,
      );
    } on Object catch (e) {
      out.send('$e');
      return;
    }
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((message) {
      if (message is (TransferableTypedData, String?)) {
        try {
          final bytes = message.$1.materialize();
          final r = engine.transcribe(
            bytes.asFloat32List(),
            language: message.$2,
          );
          out.send((r.text, r.language));
        } on Object catch (e) {
          out.send('$e');
        }
      } else if (isSharedWhisperRequest(message)) {
        answerSharedWhisper(
          message! as List<Object?>,
          (samples, language) => engine.transcribe(samples, language: language),
        );
      } else if (message == null) {
        engine.dispose();
        inbox.close();
        Isolate.exit();
      }
    });
  }
}
