import 'dart:async';
import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';

import '../src/models/model_downloader.dart';
import '../src/models/speech_model.dart';
import '../src/models/speech_model_service.dart';

/// A running fake download, driven by the test.
final class FakeDownload {
  FakeDownload(this.model, this.onProgress, this.onUnpacking);

  final SpeechModel model;
  final void Function(DownloadProgress)? onProgress;
  final void Function()? onUnpacking;
  final done = Completer<void>();
}

/// [SpeechModelService] in memory: downloads only advance when the test
/// calls [progress], [unpack], [finish] or [fail].
final class FakeSpeechModelService implements SpeechModelService {
  /// Installed model ids.
  final installed = <String>{};

  /// Partly downloaded model ids.
  final partial = <String>{};

  /// Model ids that are unpacked but unusable (see [isDamaged]).
  final damaged = <String>{};

  /// Running downloads by model id.
  final running = <String, FakeDownload>{};

  /// Deleted model ids.
  final deleted = <String>[];

  @override
  Future<bool> isInstalled(SpeechModel model) async =>
      installed.contains(model.id);

  @override
  Future<bool> isDamaged(SpeechModel model) async => damaged.contains(model.id);

  @override
  Future<bool> hasPartial(SpeechModel model) async =>
      partial.contains(model.id);

  @override
  Directory directoryOf(SpeechModel model) => Directory('/fake/${model.id}');

  @override
  Future<void> install(
    SpeechModel model, {
    void Function(DownloadProgress progress)? onProgress,
    void Function()? onUnpacking,
    CancelToken? cancel,
  }) {
    final d = running[model.id] = FakeDownload(model, onProgress, onUnpacking);
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (d.done.isCompleted) return;
        partial.add(model.id);
        running.remove(model.id);
        d.done.completeError(
          const ModelDownloadException(
            DownloadErrorKind.cancelled,
            'Download abgebrochen.',
          ),
        );
      }),
    );
    return d.done.future;
  }

  /// Reports [fraction] of [id] as downloaded.
  void progress(String id, double fraction) {
    final d = running[id]!;
    final total = d.model.sizeBytes;
    d.onProgress?.call(
      DownloadProgress(
        modelId: id,
        file: d.model.files.first.name,
        receivedBytes: (total * fraction).round(),
        totalBytes: total,
      ),
    );
  }

  /// Starts unpacking [id].
  void unpack(String id) => running[id]!.onUnpacking?.call();

  /// Finishes [id] successfully.
  void finish(String id) {
    installed.add(id);
    partial.remove(id);
    running.remove(id)!.done.complete();
  }

  /// Fails [id] with [error]; with [keepPartial] a part stays.
  void fail(String id, Object error, {bool keepPartial = false}) {
    if (keepPartial) partial.add(id);
    running.remove(id)!.done.completeError(error);
  }

  @override
  Future<void> delete(SpeechModel model) async {
    deleted.add(model.id);
    installed.remove(model.id);
    partial.remove(model.id);
  }
}
