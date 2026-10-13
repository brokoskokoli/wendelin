import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'model_store.dart';
import 'speech_model.dart';

/// Why a model download failed.
enum DownloadErrorKind {
  /// The server answered with an unexpected status.
  http,

  /// Network error while connecting or receiving.
  network,

  /// The file has the wrong size.
  size,

  /// The SHA-256 does not match the catalog (file discarded).
  checksum,

  /// Writing to the `ModelStore` failed.
  storage,

  /// Aborted via `CancelToken` (the partial file is kept for resuming).
  cancelled,

  /// The same model is already being downloaded.
  busy,
}

/// Error of [ModelDownloader.download].
final class ModelDownloadException implements Exception {
  /// Creates the exception.
  const ModelDownloadException(
    this.kind,
    this.message, {
    this.file,
    this.cause,
  });

  /// Kind of failure.
  final DownloadErrorKind kind;

  /// German message for the user.
  final String message;

  /// Affected file.
  final String? file;

  /// Underlying error.
  final Object? cause;

  @override
  String toString() => 'ModelDownloadException(${kind.name}, $file, $message)';
}

/// Progress of a model download.
@immutable
final class DownloadProgress {
  /// Creates a progress value.
  const DownloadProgress({
    required this.modelId,
    required this.file,
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// Model being downloaded.
  final String modelId;

  /// File currently being downloaded.
  final String file;

  /// Bytes present for the whole model (including resumed and finished
  /// files).
  final int receivedBytes;

  /// Total size of the model.
  final int totalBytes;

  /// Progress 0.0–1.0.
  double get fraction => totalBytes == 0 ? 1 : receivedBytes / totalBytes;

  @override
  String toString() => 'DownloadProgress($modelId, $receivedBytes/$totalBytes)';
}

/// Downloads catalog models into a [ModelStore]: with progress, resume via
/// HTTP `Range`, SHA-256 check, atomic commit and cancellation.
///
/// Per file: an existing final file is skipped; an existing partial file is
/// continued (`Range: bytes=<n>-`; a `200` answer restarts from zero, a
/// `416` discards the partial file and retries once). After the body the
/// size and SHA-256 are checked; only a matching file is committed, a
/// mismatch deletes the partial file. Cancelling keeps the partial file so
/// that the next call resumes.
final class ModelDownloader {
  /// Creates a downloader.
  ModelDownloader({required this.client, required this.store});

  /// HTTP client (the app passes one without GMS dependencies).
  final http.Client client;

  /// Target storage.
  final ModelStore store;

  /// Whether all files of [model] are present.
  Future<bool> isInstalled(SpeechModel model) async {
    for (final f in model.files) {
      if (!await store.exists(model.id, f.name)) return false;
    }
    return true;
  }

  /// Downloads all missing files of [model].
  ///
  /// Throws [ModelDownloadException]; [onProgress] is called after every
  /// received chunk.
  ///
  /// Only one download per model runs at a time (a second call fails with
  /// [DownloadErrorKind.busy]); file names must be plain names
  /// (`ArgumentError` otherwise), so a catalog entry can never write
  /// outside the model directory.
  Future<void> download(
    SpeechModel model, {
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancel,
  }) async {
    for (final f in model.files) {
      if (!_safeName.hasMatch(f.name) || f.name.startsWith('.')) {
        throw ArgumentError.value(f.name, 'name', 'kein einfacher Dateiname');
      }
    }
    if (!_active.add(model.id)) {
      throw ModelDownloadException(
        DownloadErrorKind.busy,
        '${model.displayName} wird bereits heruntergeladen.',
      );
    }
    try {
      await _download(model, onProgress, cancel ?? CancelToken());
    } finally {
      _active.remove(model.id);
    }
  }

  static final _safeName = RegExp(r'^[A-Za-z0-9._-]+$');
  final _active = <String>{};

  Future<void> _download(
    SpeechModel model,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken token,
  ) async {
    var done = 0; // bytes of finished files
    for (final f in model.files) {
      _checkCancel(token, f);
      if (await _guard(f, () => store.exists(model.id, f.name))) {
        done += f.sizeBytes;
        onProgress?.call(_progress(model, f, done));
        continue;
      }
      await _downloadFile(
        model,
        f,
        token,
        (received) => onProgress?.call(_progress(model, f, done + received)),
      );
      done += f.sizeBytes;
    }
  }

  Future<void> _downloadFile(
    SpeechModel model,
    ModelFile f,
    CancelToken token,
    void Function(int received) progress, {
    bool retried = false,
  }) async {
    final id = model.id;
    var offset = await _guard(f, () => store.partialLength(id, f.name));
    if (offset > f.sizeBytes) {
      await _guard(f, () => store.deletePartial(id, f.name));
      offset = 0;
    }
    if (offset == f.sizeBytes) {
      // Complete but not committed (e.g. app killed before the rename).
      if (await _hashOfPartial(id, f) == f.sha256) {
        await _guard(f, () => store.commit(id, f.name));
        progress(offset);
        return;
      }
      await _guard(f, () => store.deletePartial(id, f.name));
      offset = 0;
    }

    final request = http.AbortableRequest(
      'GET',
      Uri.parse(f.url),
      abortTrigger: token.whenCancelled,
    );
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } on http.RequestAbortedException {
      throw _cancelled(f);
    } on Object catch (e) {
      if (token.isCancelled) throw _cancelled(f);
      throw ModelDownloadException(
        DownloadErrorKind.network,
        'Download von ${f.name} fehlgeschlagen (Netzwerk).',
        file: f.name,
        cause: e,
      );
    }

    switch (response.statusCode) {
      case 206 when offset > 0 && !_rangeMatches(response, offset):
        // The server resumes somewhere else: start over from zero (the
        // retry sends no Range header, so this cannot repeat).
        await _drain(response);
        await _guard(f, () => store.deletePartial(id, f.name));
        return _downloadFile(model, f, token, progress, retried: true);
      case 206 when offset > 0:
        break;
      case 200:
        if (offset > 0) {
          await _guard(f, () => store.truncate(id, f.name));
          offset = 0;
        }
      case 416 when offset > 0 && !retried:
        await _drain(response);
        await _guard(f, () => store.deletePartial(id, f.name));
        return _downloadFile(model, f, token, progress, retried: true);
      default:
        await _drain(response);
        throw _httpError(f, response.statusCode);
    }

    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    if (offset > 0) {
      await _guard(f, () async {
        await for (final chunk in store.readPartial(id, f.name)) {
          hash.add(chunk);
        }
      });
    }
    var received = offset;
    progress(received);
    try {
      await for (final chunk in _untilCancelled(response.stream, token, f)) {
        received += chunk.length;
        if (received > f.sizeBytes) break;
        hash.add(chunk);
        await _guard(f, () => store.append(id, f.name, chunk));
        progress(received);
        _checkCancel(token, f);
      }
    } on ModelDownloadException {
      rethrow;
    } on Object catch (e) {
      if (token.isCancelled || e is http.RequestAbortedException) {
        throw _cancelled(f);
      }
      throw ModelDownloadException(
        DownloadErrorKind.network,
        'Download von ${f.name} abgebrochen (Netzwerk).',
        file: f.name,
        cause: e,
      );
    }

    if (received > f.sizeBytes) {
      // The server sends more than the catalog says: wrong file.
      await _guard(f, () => store.deletePartial(id, f.name));
      throw _sizeError(f, received);
    }
    if (received != f.sizeBytes) {
      // Too short: keep the partial file, the next call resumes.
      throw _sizeError(f, received);
    }
    hash.close();
    if (digest.value.toString() != f.sha256) {
      await _guard(f, () => store.deletePartial(id, f.name));
      throw ModelDownloadException(
        DownloadErrorKind.checksum,
        'Prüfsumme von ${f.name} stimmt nicht; die Datei wurde verworfen.',
        file: f.name,
      );
    }
    await _guard(f, () => store.commit(id, f.name));
  }

  /// [source], ending with a cancellation error as soon as [token] is
  /// cancelled – also while waiting for the next chunk.
  static Stream<List<int>> _untilCancelled(
    Stream<List<int>> source,
    CancelToken token,
    ModelFile f,
  ) {
    late final StreamController<List<int>> out;
    StreamSubscription<List<int>>? sub;
    out = StreamController<List<int>>(
      onListen: () {
        sub = source.listen(out.add, onError: out.addError, onDone: out.close);
        unawaited(
          token.whenCancelled.then((_) {
            if (out.isClosed) return;
            unawaited(sub?.cancel());
            out
              ..addError(_cancelled(f))
              ..close();
          }),
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      // Do not wait for the source to acknowledge: a stalled connection
      // may never do so.
      onCancel: () => unawaited(sub?.cancel()),
    );
    return out.stream;
  }

  Future<String> _hashOfPartial(String id, ModelFile f) => _guard(
    f,
    () async =>
        (await sha256.bind(store.readPartial(id, f.name)).first).toString(),
  );

  DownloadProgress _progress(SpeechModel m, ModelFile f, int received) =>
      DownloadProgress(
        modelId: m.id,
        file: f.name,
        receivedBytes: received,
        totalBytes: m.sizeBytes,
      );

  /// Whether a `206` answer starts at [offset] (`Content-Range` begins
  /// with `bytes OFFSET-`); a missing header is accepted.
  static bool _rangeMatches(http.StreamedResponse r, int offset) {
    final range = r.headers['content-range'];
    if (range == null) return true;
    return RegExp(r'^bytes\s+(\d+)-').firstMatch(range.trim())?.group(1) ==
        '$offset';
  }

  static ModelDownloadException _httpError(ModelFile f, int status) =>
      ModelDownloadException(
        DownloadErrorKind.http,
        'Download von ${f.name} fehlgeschlagen (HTTP $status).',
        file: f.name,
      );

  static Future<void> _drain(http.StreamedResponse r) =>
      r.stream.drain<void>().catchError((Object _) {});

  static void _checkCancel(CancelToken token, ModelFile f) {
    if (token.isCancelled) throw _cancelled(f);
  }

  static ModelDownloadException _cancelled(ModelFile f) =>
      ModelDownloadException(
        DownloadErrorKind.cancelled,
        'Download abgebrochen.',
        file: f.name,
      );

  static ModelDownloadException _sizeError(ModelFile f, int received) =>
      ModelDownloadException(
        DownloadErrorKind.size,
        'Download von ${f.name} unvollständig ($received von '
        '${f.sizeBytes} Bytes).',
        file: f.name,
      );

  static ModelDownloadException _storageError(ModelFile f, Object e) =>
      ModelDownloadException(
        DownloadErrorKind.storage,
        '${f.name} konnte nicht gespeichert werden.',
        file: f.name,
        cause: e,
      );

  static Future<T> _guard<T>(ModelFile f, Future<T> Function() op) async {
    try {
      return await op();
    } on ModelDownloadException {
      rethrow;
    } on Object catch (e) {
      throw _storageError(f, e);
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
