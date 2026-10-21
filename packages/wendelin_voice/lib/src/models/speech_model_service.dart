import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';

import 'model_downloader.dart';
import 'speech_model.dart';

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

/// Why unpacking failed.
final class ArchiveRejected implements Exception {
  /// Creates the error.
  const ArchiveRejected(this.message, {this.reason = 'rejected'});

  /// Short log code of the cause (`too-large`, `corrupt`, `unsafe-path`,
  /// `forbidden-entry`, `io`); never a path or content.
  final String reason;

  /// German message for the user.
  final String message;

  @override
  String toString() => 'ArchiveRejected($message)';
}
