import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'disk_space.dart';
import 'file_model_store.dart';
import 'tar_bz2.dart';

/// Not enough free space for a download (shown instead of starting it).
final class InsufficientSpaceException implements Exception {
  /// Creates the error.
  const InsufficientSpaceException({
    required this.requiredBytes,
    required this.freeBytes,
  });

  /// Bytes needed (download, unpacking and buffer).
  final int requiredBytes;

  /// Bytes free.
  final int freeBytes;

  /// German message.
  String get message =>
      'Zu wenig Speicherplatz: ${megabytes(requiredBytes)} nötig, '
      '${megabytes(freeBytes)} frei.';

  @override
  String toString() => 'InsufficientSpaceException($message)';
}

/// [bytes] as „123 MB“ (decimal megabytes, rounded).
String megabytes(int bytes) => '${(bytes / 1000000).round()} MB';

/// What the download UI needs from the model storage (fake in widget
/// tests).
abstract interface class SpeechModelService {
  /// Whether every file of [model] is installed.
  Future<bool> isInstalled(SpeechModel model);

  /// Whether a partial download of [model] exists.
  Future<bool> hasPartial(SpeechModel model);

  /// Downloads and unpacks [model] (see [ModelInstaller.install]).
  Future<void> install(
    SpeechModel model, {
    void Function(DownloadProgress progress)? onProgress,
    void Function()? onUnpacking,
    CancelToken? cancel,
  });

  /// Removes [model].
  Future<void> delete(SpeechModel model);

  /// Directory of the installed [model] (unpacked voices inside).
  Directory directoryOf(SpeechModel model);
}

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
      : store.exists(model.id, f.name);

  /// Whether every file of [model] is installed (archives unpacked).
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
      if (await store.exists(model.id, f.name)) continue; // only unpacking
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
      final file = File(store.pathOf(model.id, f.name));
      try {
        await extractTarBz2(file, unpackedDir(model, f));
      } on ArchiveRejected {
        await store.deleteFile(model.id, f.name);
        rethrow;
      }
      await store.deleteFile(model.id, f.name);
    }
  }

  /// Removes [model] from the device.
  @override
  Future<void> delete(SpeechModel model) => store.deleteModel(model.id);
}
