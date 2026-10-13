import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice/file_model_store.dart';
import '../voice/model_installer.dart';
import '../voice/silero_vad.dart';
import '../voice/whisper_registry.dart';
import '../voice/whisper_sherpa.dart';
import '../voice/whisper_stt.dart';
import 'recognizer_host.dart';

/// Starts a Whisper backend for [files] (tests replace it).
typedef WhisperStarter = Future<WhisperBackend> Function(WhisperFiles files);

/// Finds the Whisper model another engine has loaded (tests replace it).
typedef SharedWhisperLookup = Future<WhisperBackend?> Function(String modelId);

/// Creates a VAD for a model path and threshold (tests replace it).
typedef VadFactory = VoiceActivityDetector Function(
  String modelPath,
  double threshold,
);

/// Models of the recognizer engine on the device (ADR 0008):
/// - Whisper of the app engine, if it has one loaded (no second copy);
///   otherwise loaded here and released [idleRelease] after the last
///   request.
/// - A Silero VAD per request (small, loads in milliseconds).
final class DeviceRecognizerEngines implements RecognizerEngines {
  /// Creates the engines over the installed [models].
  DeviceRecognizerEngines({
    required this.models,
    this.catalog = SpeechModelCatalog.standard,
    this.idleRelease = const Duration(seconds: 30),
    WhisperStarter? startWhisper,
    SharedWhisperLookup? lookupShared,
    VadFactory? createVad,
  }) : _startWhisper = startWhisper ?? IsolateWhisperBackend.start,
       _lookupShared = lookupShared ?? lookupSharedWhisper,
       _createVad = createVad ?? _silero;

  /// Installed models.
  final SpeechModelService models;

  /// Model catalog.
  final SpeechModelCatalog catalog;

  /// How long an own Whisper model stays loaded after the last request.
  final Duration idleRelease;

  final WhisperStarter _startWhisper;
  final SharedWhisperLookup _lookupShared;
  final VadFactory _createVad;

  String? _ownId;
  Future<WhisperBackend>? _own;
  Timer? _idle;
  bool _disposed = false;

  static VoiceActivityDetector _silero(String path, double threshold) =>
      SileroVoiceActivityDetector(modelPath: path, threshold: threshold);

  Future<SpeechModel> _installed(String id, String what) async {
    final model = catalog.byId(id);
    if (model == null || !await models.isInstalled(model)) {
      throw VoiceException(
        VoiceErrorKind.modelMissing,
        '$what ist noch nicht geladen (Wendelin → Einstellungen → Sprache).',
      );
    }
    return model;
  }

  @override
  Future<void> checkInstalled(String modelId) async {
    await _installed(modelId, 'Das Whisper-Modell');
    await _installed(
      SpeechModelCatalog.sileroVad.id,
      'Die Sprachaktivitätserkennung',
    );
  }

  @override
  VoiceActivityDetector vad(double threshold) {
    final model = SpeechModelCatalog.sileroVad;
    return _createVad(
      '${models.directoryOf(model).path}/${model.files.single.name}',
      threshold,
    );
  }

  @override
  void releaseVad(VoiceActivityDetector vad) {
    if (vad is SileroVoiceActivityDetector) vad.dispose();
  }

  @override
  Future<SpeechToText> speechToText(String modelId) async {
    _idle?.cancel();
    if (_disposed) throw StateError('Erkenner ist beendet.');
    _active++;
    final own = _own;
    if (own != null && _ownId == modelId) {
      return WhisperSpeechToText(backend: await own, modelId: modelId);
    }
    final shared = await _lookupShared(modelId);
    if (shared != null) {
      return WhisperSpeechToText(
        backend: _SharedOrOwn(shared, () => _loadOwn(modelId)),
        modelId: modelId,
      );
    }
    return WhisperSpeechToText(
      backend: await _loadOwn(modelId),
      modelId: modelId,
    );
  }

  /// The own model [modelId], loaded once (another model is released).
  Future<WhisperBackend> _loadOwn(String modelId) async {
    final own = _own;
    if (own != null && _ownId == modelId) return own;
    final model = await _installed(modelId, 'Das Whisper-Modell');
    await _releaseOwn();
    final loading = _startWhisper(
      WhisperFiles.of(model, models.directoryOf(model).path),
    );
    _ownId = modelId;
    _own = loading;
    try {
      final backend = await loading;
      // The request may have ended while the model loaded.
      _armIdle();
      return backend;
    } on Object {
      if (identical(_own, loading)) {
        _own = null;
        _ownId = null;
      }
      rethrow;
    }
  }

  /// Whether this engine holds its own Whisper model (for tests).
  @visibleForTesting
  bool get holdsOwnModel => _own != null;

  /// Requests between [speechToText] and [idle].
  int _active = 0;

  @override
  void idle() {
    if (_active > 0) _active--;
    _armIdle();
  }

  /// Releases the own model [idleRelease] after the last request.
  void _armIdle() {
    _idle?.cancel();
    if (_own != null && _active == 0 && !_disposed) {
      _idle = Timer(idleRelease, () {
        if (_active == 0) unawaited(_releaseOwn());
      });
    }
  }

  Future<void> _releaseOwn() async {
    final own = _own;
    _own = null;
    _ownId = null;
    if (own == null) return;
    try {
      await (await own).dispose();
    } on Object catch (e) {
      debugPrint('Erkenner: Whisper ließ sich nicht freigeben: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _idle?.cancel();
    await _releaseOwn();
  }
}

/// Entry of the recognizer engine (`recognizerMain` in `main.dart`): the
/// models from `<App-Support>/models` and the channel to the service.
Future<void> runRecognizerEngine() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FileModelStore(
    Directory('${(await getApplicationSupportDirectory()).path}/models'),
  );
  // The downloader is never used here (only `isInstalled`/`directoryOf`).
  final installer = ModelInstaller(
    store: store,
    downloader: ModelDownloader(client: http.Client(), store: store),
  );
  await RecognizerHost(engines: DeviceRecognizerEngines(models: installer))
      .attach();
}

/// Whisper of the app engine, with the own model as fallback when the app
/// engine is gone or does not answer in time (`VoiceErrorKind.unavailable`
/// of [RemoteWhisperBackend]).
final class _SharedOrOwn implements WhisperBackend {
  _SharedOrOwn(this.shared, this.own);

  final WhisperBackend shared;
  final Future<WhisperBackend> Function() own;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    try {
      return await shared.transcribe(samples, language: language);
    } on VoiceException catch (e) {
      if (e.kind != VoiceErrorKind.unavailable) rethrow;
      debugPrint('Erkenner: Whisper der App antwortet nicht, lade eigenes.');
    }
    return (await own()).transcribe(samples, language: language);
  }

  /// The shared model belongs to the app; the own one to the engines.
  @override
  Future<void> dispose() async {}
}
