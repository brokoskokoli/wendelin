import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'disk_space.dart';
import 'file_model_store.dart';
import 'tar_bz2.dart';

export 'package:wendelin_voice/wendelin_voice.dart'
    show InsufficientSpaceException, SpeechModelService, megabytes;

/// Installs catalog models into a [FileModelStore]: checks the free space,
/// downloads with [ModelDownloader] (resume, SHA-256, cancel) and unpacks
/// `.tar.bz2` voices safely ([extractTarBz2]); the archive is deleted only
/// after unpacking succeeded.
final class ModelInstaller implements SpeechModelService {
  /// Creates the installer.
  ModelInstaller({
    required this.store,
    required this.downloader,
    this.disk = const StatvfsDiskSpace(),
  });

  /// Target storage.
  final FileModelStore store;

  /// Downloader on [store].
  final ModelDownloader downloader;

  /// Free-space probe.
  final DiskSpace disk;

  /// Directory a downloaded archive [file] of [model] is unpacked into.
  Directory unpackedDir(SpeechModel model, ModelFile file) {
    final base = file.name.replaceFirst(RegExp(r'\.tar\.bz2$'), '');
    return Directory('${store.modelDir(model.id).path}/$base');
  }

  @override
  Directory directoryOf(SpeechModel model) => store.modelDir(model.id);

  Future<bool> _fileInstalled(SpeechModel model, ModelFile f) async =>
      f.archive == ModelArchive.tarBz2
      ? unpackedDir(model, f).exists()
      : _finalComplete(model, f);

  /// Whether the final file exists with exactly its catalog size (a
  /// truncated model would crash sherpa-onnx when loaded).
  Future<bool> _finalComplete(SpeechModel model, ModelFile f) async {
    final file = File(store.pathOf(model.id, f.name));
    return await file.exists() && await file.length() == f.sizeBytes;
  }

  /// Whether every file of [model] is installed: plain files with their
  /// catalog size, archives unpacked.
  @override
  Future<bool> isInstalled(SpeechModel model) async {
    for (final f in model.files) {
      if (!await _fileInstalled(model, f)) return false;
    }
    return true;
  }

  /// Whether a partial download of [model] exists (resumed by [install]).
  @override
  Future<bool> hasPartial(SpeechModel model) => store.hasPartial(model);

  /// Bytes still to download for [model].
  Future<int> remainingBytes(SpeechModel model) async {
    var n = 0;
    for (final f in model.files) {
      if (await _fileInstalled(model, f)) continue;
      if (await _finalComplete(model, f)) continue; // only unpacking
      n += f.sizeBytes - await store.partialLength(model.id, f.name);
    }
    return n;
  }

  /// Downloads and unpacks the missing files of [model].
  ///
  /// Throws [InsufficientSpaceException] before downloading,
  /// `ModelDownloadException` from the downloader and [ArchiveRejected]
  /// when an archive is unsafe or broken (the archive is then deleted, so
  /// the next attempt downloads it again). [onUnpacking] is called before
  /// an archive is unpacked.
  @override
  Future<void> install(
    SpeechModel model, {
    void Function(DownloadProgress progress)? onProgress,
    void Function()? onUnpacking,
    CancelToken? cancel,
  }) async {
    final missing = [
      for (final f in model.files)
        if (!await _fileInstalled(model, f)) f,
    ];
    if (missing.isEmpty) return;
    for (final f in missing) {
      // A final file of the wrong size is downloaded again.
      if (await store.exists(model.id, f.name) &&
          !await _finalComplete(model, f)) {
        await store.deleteFile(model.id, f.name);
      }
    }
    final archive = missing.any((f) => f.archive == ModelArchive.tarBz2);
    final need = requiredSpace(await remainingBytes(model), archive: archive);
    await store.root.create(recursive: true);
    final free = await disk.freeBytes(store.root.path);
    if (free != null && free < need) {
      throw InsufficientSpaceException(requiredBytes: need, freeBytes: free);
    }
    final pending = SpeechModel(
      id: model.id,
      kind: model.kind,
      displayName: model.displayName,
      languages: model.languages,
      files: missing,
      license: model.license,
      source: model.source,
    );
    await downloader.download(pending, onProgress: onProgress, cancel: cancel);
    for (final f in missing) {
      if (f.archive != ModelArchive.tarBz2) continue;
      cancel?.throwIfCancelled();
      onUnpacking?.call();
      await _unpack(model, f);
    }
  }

  /// Unpacks the downloaded archive [f] of [model]: space check, log
  /// lines (sizes and reason, no paths), archive removed afterwards.
  Future<void> _unpack(SpeechModel model, ModelFile f) async {
    final file = File(store.pathOf(model.id, f.name));
    final archiveBytes = await file.length();
    final limit = unpackLimit(archiveBytes);
    // The download check may be long ago (resumed install): the room for
    // the unpacked files is checked again, with a clear message.
    final free = await disk.freeBytes(store.root.path);
    voiceLog('model-unpack', {
      'model': model.id,
      'archive_bytes': archiveBytes,
      'limit_bytes': limit,
      'free_bytes': free,
    });
    if (free != null && free < limit) {
      voiceLog('model-unpack-failed', {
        'model': model.id,
        'reason': 'no-space',
        'archive_bytes': archiveBytes,
        'free_bytes': free,
        'need_bytes': limit,
      });
      throw InsufficientSpaceException(requiredBytes: limit, freeBytes: free);
    }
    final watch = Stopwatch()..start();
    try {
      final bytes = await extractTarBz2(file, unpackedDir(model, f));
      voiceLog('model-unpacked', {
        'model': model.id,
        'bytes': bytes,
        'ms': watch.elapsed,
      });
    } on ArchiveRejected catch (e) {
      voiceLog('model-unpack-failed', {
        'model': model.id,
        'reason': e.reason,
        'archive_bytes': archiveBytes,
        'limit_bytes': limit,
      });
      // A file system error (storage full) says nothing against the archive:
      // keep it, a retry unpacks again without a new download.
      if (e.reason != 'io') await store.deleteFile(model.id, f.name);
      rethrow;
    } on Object catch (e) {
      voiceLog('model-unpack-failed', {
        'model': model.id,
        'reason': errorCode(e),
        'archive_bytes': archiveBytes,
      });
      rethrow;
    }
    await store.deleteFile(model.id, f.name);
  }

  /// Removes [model] from the device.
  @override
  Future<void> delete(SpeechModel model) => store.deleteModel(model.id);
}
