import 'dart:async';

import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'model_downloader.dart';
import 'speech_model.dart';
import 'speech_model_catalog.dart';
import 'speech_model_service.dart';

/// Where a model stands on the device.
enum ModelPhase {
  /// Not checked yet.
  unknown,

  /// Not on the device.
  absent,

  /// Partly downloaded (cancelled or app closed); can be continued.
  partial,

  /// Download running.
  downloading,

  /// Archive being unpacked.
  unpacking,

  /// Ready to use.
  installed,
}

/// Download state of one model.
@immutable
final class ModelState {
  /// Creates a state.
  const ModelState(this.phase, {this.progress = 0, this.error});

  /// Phase.
  final ModelPhase phase;

  /// Download progress 0–1.
  final double progress;

  /// Message of the last failure (German), if any.
  final String? error;

  /// Whether a download or unpacking is running.
  bool get busy =>
      phase == ModelPhase.downloading || phase == ModelPhase.unpacking;

  @override
  bool operator ==(Object other) =>
      other is ModelState &&
      other.phase == phase &&
      other.progress == progress &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, progress, error);

  @override
  String toString() => 'ModelState(${phase.name}, $progress, $error)';
}

/// German text for a failed download.
String downloadErrorText(Object e) => switch (e) {
  InsufficientSpaceException() => e.message,
  ModelDownloadException() => e.message,
  ArchiveRejected() => e.message,
  _ => 'Der Download ist fehlgeschlagen.',
};

/// Download state of all catalog models, without any framework: which
/// model is absent, partial, downloading, unpacking or installed, and the
/// transitions between them. The app wraps it in a Riverpod notifier that
/// publishes [onChanged] as its state.
///
/// Downloads end in [ModelState.error] with a German message
/// ([downloadErrorText]); cancelling keeps the partial file; a model counts
/// as installed only after [SpeechModelService.install] returned.
final class ModelInstallStates {
  /// Creates the state machine.
  ModelInstallStates({
    required this.catalog,
    required this.service,
    this.onChanged,
    this.onInstalled,
    this.log,
  });

  /// The catalog (read on every use, so a changed catalog applies).
  final SpeechModelCatalog Function() catalog;

  /// The model storage; fails if there is no model directory.
  final Future<SpeechModelService> Function() service;

  /// Called with the new states after every change.
  final void Function(Map<String, ModelState> states)? onChanged;

  /// Called after a model was installed or deleted (engines depending on it
  /// are rebuilt).
  final void Function(SpeechModel model)? onInstalled;

  /// Diagnostics (e.g. missing model directory).
  final void Function(String line)? log;

  final Map<String, ModelState> _states = {};
  final Map<String, CancelToken> _tokens = {};
  bool _disposed = false;

  /// The states by model id (unknown models are missing).
  Map<String, ModelState> get states => Map.unmodifiable(_states);

  /// State of [modelId].
  ModelState of(String modelId) =>
      _states[modelId] ?? const ModelState(ModelPhase.unknown);

  void _put(String id, ModelState s) {
    if (_disposed) return;
    _states[id] = s;
    onChanged?.call(states);
  }

  /// Re-reads which models are installed or partly downloaded.
  Future<void> refresh() async {
    final SpeechModelService storage;
    try {
      storage = await service();
    } on Object catch (e) {
      // No model directory (e.g. platform without path_provider): the
      // models stay „unknown“ and nothing can be downloaded.
      log?.call('Modellverzeichnis nicht verfügbar: $e');
      return;
    }
    if (_disposed) return;
    for (final m in catalog().models) {
      // The owner may be gone after an await (tests, engine end).
      if (_disposed || of(m.id).busy) continue;
      final phase = await storage.isInstalled(m)
          ? ModelPhase.installed
          : await storage.hasPartial(m)
          ? ModelPhase.partial
          : ModelPhase.absent;
      _put(m.id, ModelState(phase));
    }
  }

  /// Downloads [modelId] (continues a partial download). Failures end in
  /// [ModelState.error]; cancelling keeps the partial file.
  Future<void> download(String modelId) async {
    final model = catalog().byId(modelId);
    if (model == null || of(modelId).busy) return;
    final token = _tokens[modelId] = CancelToken();
    _put(modelId, const ModelState(ModelPhase.downloading));
    try {
      final storage = await service();
      await storage.install(
        model,
        cancel: token,
        onProgress: (p) => _put(
          modelId,
          ModelState(ModelPhase.downloading, progress: p.fraction),
        ),
        onUnpacking: () =>
            _put(modelId, const ModelState(ModelPhase.unpacking, progress: 1)),
      );
      _put(modelId, const ModelState(ModelPhase.installed, progress: 1));
      _installedChanged(model);
    } on Object catch (e) {
      final cancelled =
          e is CancelledException ||
          (e is ModelDownloadException &&
              e.kind == DownloadErrorKind.cancelled);
      _put(
        modelId,
        ModelState(
          cancelled ? ModelPhase.partial : ModelPhase.absent,
          error: cancelled ? null : downloadErrorText(e),
        ),
      );
      if (!cancelled) {
        // A failed download may still have left a resumable part.
        unawaited(refreshKeepingError(modelId));
      }
    } finally {
      if (identical(_tokens[modelId], token)) _tokens.remove(modelId);
    }
  }

  /// Re-checks [modelId] after a failure but keeps the error message.
  Future<void> refreshKeepingError(String modelId) async {
    final model = catalog().byId(modelId);
    if (model == null || _disposed) return;
    final storage = await service();
    final partial = await storage.hasPartial(model);
    final current = of(modelId);
    if (partial && !current.busy) {
      _put(modelId, ModelState(ModelPhase.partial, error: current.error));
    }
  }

  void _installedChanged(SpeechModel model) {
    if (_disposed) return;
    onInstalled?.call(model);
  }

  /// Cancels the download of [modelId] (the partial file stays).
  void cancel(String modelId) => _tokens[modelId]?.cancel();

  /// Deletes [modelId] from the device.
  Future<void> delete(String modelId) async {
    final model = catalog().byId(modelId);
    if (model == null || of(modelId).busy) return;
    final storage = await service();
    await storage.delete(model);
    _put(modelId, const ModelState(ModelPhase.absent));
    _installedChanged(model);
  }

  /// Continues every partly downloaded model (after an app restart).
  Future<void> resumePartial() async {
    await refresh();
    for (final e in _states.entries.toList()) {
      if (e.value.phase == ModelPhase.partial && e.value.error == null) {
        unawaited(download(e.key));
      }
    }
  }

  /// Cancels running downloads and stops reporting.
  void dispose() {
    _disposed = true;
    for (final t in _tokens.values) {
      t.cancel();
    }
  }
}
