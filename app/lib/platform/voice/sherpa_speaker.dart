import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'isolate_exit.dart';
import 'pcm.dart';
import 'sherpa_runtime.dart';

/// [SpeakerEmbedder] on sherpa-onnx `SpeakerEmbeddingExtractor` (WP92a).
///
/// The model (CAM++, ~28 MB on disk) loads lazily on the first [embed] in a
/// background isolate and is freed by [release], like the recognizer
/// (`mayReleaseModels`). Audio only passes through memory; nothing is
/// written to disk.
final class SherpaSpeakerEmbedder implements SpeakerEmbedder {
  /// Creates the embedder for the model [model] in [directory].
  SherpaSpeakerEmbedder({
    required this.model,
    required this.directory,
    @visibleForTesting
    Future<SpeakerSession> Function(String modelPath)? sessionFactory,
  }) : _factory = sessionFactory ?? _Session.start;

  final Future<SpeakerSession> Function(String modelPath) _factory;

  /// Hangs tolerated since the last [release]: the first one restarts the
  /// isolate, the second one disables the embedder until [release].
  static const maxHangs = 2;

  /// Catalog entry (`SpeechModelCatalog.speakerCamPlus`).
  final SpeechModel model;

  /// Directory of the installed model.
  final String directory;

  /// How long the isolate may take for one embedding before it counts as
  /// hanging and is killed.
  static Duration replyTimeout = const Duration(seconds: 10);

  /// How long [release] waits for the isolate to exit before killing it.
  static Duration exitGrace = const Duration(seconds: 5);

  Future<SpeakerSession>? _session;
  int _hangs = 0;

  /// Whether the model is currently loaded.
  bool get isLoaded => _session != null;

  @override
  Future<Float32List> embed(Int16List pcm) async {
    if (_hangs >= maxHangs) {
      throw const VoiceException(
        VoiceErrorKind.failed,
        'Die Sprechererkennung hängt und ist bis zum Freigeben deaktiviert.',
      );
    }
    final pending = _session ??= _start();
    final session = await pending;
    try {
      return await session.embed(pcm);
    } on TimeoutException {
      // `Isolate.kill` does not end a hanging native call: the isolate (and
      // its model) stays until process exit. So restart at most once, then
      // stay failed until [release].
      _hangs++;
      if (identical(_session, pending)) _session = null;
      rethrow;
    }
  }

  Future<SpeakerSession> _start() async {
    try {
      final file = model.files.single;
      final f = File('$directory/${file.name}');
      // A truncated model would end the process inside sherpa-onnx.
      if (!f.existsSync() || f.lengthSync() != file.sizeBytes) {
        throw const VoiceException(
          VoiceErrorKind.modelMissing,
          'Das Sprechermodell ist nicht (vollständig) geladen.',
        );
      }
      return await _factory(f.path);
    } on Object {
      _session = null; // the next call tries again
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    final pending = _session;
    _session = null;
    _hangs = 0;
    if (pending == null) return;
    try {
      await (await pending).dispose();
    } on Object {
      // never loaded: nothing to free
    }
  }
}

/// One loaded model in its own isolate (injectable for tests).
abstract interface class SpeakerSession {
  /// Embeds [pcm]; throws [TimeoutException] when the isolate hangs.
  Future<Float32List> embed(Int16List pcm);

  /// Frees the model.
  Future<void> dispose();
}

final class _Session implements SpeakerSession {
  _Session._(this._worker, this._requests, this._replies);

  static Future<_Session> start(String modelPath) async {
    final replies = ReceivePort();
    final worker = await WorkerIsolate.spawn(_main, (
      replies.sendPort,
      modelPath,
      sherpaLibraryDir,
    ), debugName: 'speaker');
    final events = StreamIterator(replies);
    await events.moveNext();
    final first = events.current;
    if (first is! SendPort) {
      replies.close();
      worker.kill();
      throw VoiceException(
        VoiceErrorKind.failed,
        'Das Sprechermodell ließ sich nicht laden.',
        cause: first,
      );
    }
    return _Session._(worker, first, events);
  }

  final WorkerIsolate _worker;
  final SendPort _requests;
  final StreamIterator<Object?> _replies;
  Future<void> _queue = Future.value();

  @override
  Future<Float32List> embed(Int16List pcm) {
    final samples = pcmToFloat(pcm);
    final result = _queue.then((_) async {
      _requests.send(
        TransferableTypedData.fromList([samples.buffer.asUint8List()]),
      );
      try {
        await _replies.moveNext().timeout(SherpaSpeakerEmbedder.replyTimeout);
      } on TimeoutException {
        // A late reply would answer the wrong request: drop the session.
        _worker.kill();
        unawaited(_replies.cancel());
        rethrow;
      }
      final reply = _replies.current;
      if (reply is TransferableTypedData) {
        return reply.materialize().asFloat32List();
      }
      throw StateError('Sprecher-Isolat: $reply');
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> dispose() async {
    await _queue;
    _requests.send(null);
    await _replies.cancel();
    await _worker.awaitExit(grace: SherpaSpeakerEmbedder.exitGrace);
  }

  static void _main((SendPort, String, String?) args) {
    final (out, modelPath, libraryDir) = args;
    sherpaLibraryDir = libraryDir;
    final so.SpeakerEmbeddingExtractor extractor;
    try {
      ensureSherpaBindings();
      extractor = so.SpeakerEmbeddingExtractor(
        config: so.SpeakerEmbeddingExtractorConfig(
          model: modelPath,
          numThreads: 2,
          debug: false,
        ),
      );
    } on Object catch (e) {
      out.send('$e');
      return;
    }
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((message) {
      if (message is TransferableTypedData) {
        so.OnlineStream? stream;
        try {
          stream = extractor.createStream()
            ..acceptWaveform(
              samples: message.materialize().asFloat32List(),
              sampleRate: speakerSampleRate,
            )
            ..inputFinished();
          if (!extractor.isReady(stream)) {
            out.send('zu wenig Audio');
          } else {
            final e = extractor.compute(stream);
            out.send(TransferableTypedData.fromList([e.buffer.asUint8List()]));
          }
        } on Object catch (e) {
          out.send('$e');
        } finally {
          stream?.free();
        }
      } else if (message == null) {
        extractor.free();
        inbox.close();
        Isolate.exit();
      }
    });
  }
}
