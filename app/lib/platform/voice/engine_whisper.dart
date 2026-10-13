import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'whisper_registry.dart';
import 'whisper_sherpa.dart';
import 'whisper_stt.dart';

/// Loads an own Whisper model (tests replace it with a counting fake).
typedef WhisperLoader = Future<WhisperBackend> Function();

/// Process-wide directory of loaded Whisper models (ADR 0008): every
/// engine that loads a model publishes it, the others use it.
abstract interface class WhisperDirectory {
  /// The model [modelId] another engine has loaded and that answers, or
  /// `null`.
  Future<WhisperBackend?> lookup(String modelId);

  /// Offers the own [backend] of [modelId] to the other engines.
  void publish(String modelId, WhisperBackend backend);

  /// Withdraws [backend] again (only if it is still the published one).
  void withdraw(String modelId, WhisperBackend backend);

  /// Own Whisper models of all engines of the process (debug counter).
  int liveModels();
}

/// [WhisperDirectory] on the `IsolateNameServer` (`whisper_registry.dart`).
final class IsolateWhisperDirectory implements WhisperDirectory {
  /// Creates the directory.
  const IsolateWhisperDirectory();

  @override
  Future<WhisperBackend?> lookup(String modelId) =>
      lookupSharedWhisper(modelId);

  @override
  void publish(String modelId, WhisperBackend backend) {
    if (backend is IsolateWhisperBackend) {
      publishSharedWhisper(modelId, backend.sharePort);
      markLiveWhisper(voiceLogEngine, modelId, backend.sharePort);
    }
  }

  @override
  void withdraw(String modelId, WhisperBackend backend) {
    if (backend is IsolateWhisperBackend) {
      withdrawSharedWhisper(modelId, backend.sharePort);
      unmarkLiveWhisper(voiceLogEngine, modelId);
    }
  }

  @override
  int liveModels() => liveWhisperCount();
}

// Release of the last own model of this engine: a new one only loads after
// the old one is gone (model change, B14).
Future<void> _freed = Future.value();

/// Whisper of one engine with at most one loaded model per process (B14):
///
/// - [warm] (and the first [transcribe]) first looks for the model of
///   another engine ([WhisperDirectory.lookup]) and only loads its own when
///   there is none; the own one is published for the others.
/// - If the other engine is gone (its model does not answer), this engine
///   loads its own and takes over the owner role.
/// - [release] frees the own model (idle in the background, model change);
///   the next [warm] or [transcribe] loads again.
///
/// Logs `model-load`, `model-share`, `model-free` and `model-owner-gone`
/// with model id, engine and duration, never content.
final class EngineWhisper implements WhisperBackend {
  /// Creates the handle for [modelId]; nothing is loaded yet.
  EngineWhisper({
    required this.modelId,
    required this.load,
    this.directory = const IsolateWhisperDirectory(),
    this.countLive = kDebugMode,
    Stopwatch Function()? stopwatch,
  }) : _stopwatch = stopwatch ?? Stopwatch.new;

  /// Catalog id (`whisper-base`, `whisper-small`).
  final String modelId;

  /// Loads the own model.
  final WhisperLoader load;

  /// Models of the other engines.
  final WhisperDirectory directory;

  /// Whether the log lines carry the number of loaded models of the
  /// process (`live=`, debug builds).
  final bool countLive;

  final Stopwatch Function() _stopwatch;

  WhisperBackend? _own;
  Future<WhisperBackend>? _loading;
  bool _released = false;

  /// Whether this engine holds its own model (tests, debug counter).
  bool get ownsModel => _own != null;

  /// Makes sure a model is ready: another engine's or an own one.
  Future<void> warm() async {
    _released = false;
    await _backend();
  }

  Future<WhisperBackend> _backend() async {
    final own = _own;
    if (own != null) return own;
    final loading = _loading;
    if (loading != null) return loading;
    final shared = await directory.lookup(modelId);
    if (shared != null) {
      voiceLog('model-share', {'model': modelId});
      return shared;
    }
    return _loadOwn();
  }

  Future<WhisperBackend> _loadOwn() {
    final existing = _loading;
    if (existing != null) return existing;
    final loading = () async {
      await _freed;
      final watch = _stopwatch()..start();
      final backend = await load();
      if (_released) {
        // Released while it loaded: free it again right away.
        _freed = backend.dispose();
        voiceLog('model-free', {'model': modelId, 'reason': 'released'});
        throw const VoiceException(
          VoiceErrorKind.unavailable,
          'Das Whisper-Modell wurde freigegeben.',
        );
      }
      _own = backend;
      directory.publish(modelId, backend);
      voiceLog('model-load', {
        'model': modelId,
        'ms': watch.elapsed,
        'kind': 'whisper',
        if (countLive) 'live': directory.liveModels(),
      });
      return backend;
    }();
    _loading = loading;
    return loading.whenComplete(() {
      if (identical(_loading, loading)) _loading = null;
    });
  }

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    _released = false;
    final backend = await _backend();
    try {
      return await backend.transcribe(samples, language: language);
    } on VoiceException catch (e) {
      // Only the model of another engine is replaced (it may be gone).
      if (identical(backend, _own) || e.kind != VoiceErrorKind.unavailable) {
        rethrow;
      }
      voiceLog('model-owner-gone', {'model': modelId});
    }
    final own = await _loadOwn();
    return own.transcribe(samples, language: language);
  }

  /// Frees the own model (if any); a later [warm] or [transcribe] loads
  /// again. Returns when it is gone.
  Future<void> release({String reason = 'release'}) async {
    _released = true;
    final own = _own;
    _own = null;
    if (own == null) return;
    directory.withdraw(modelId, own);
    final watch = _stopwatch()..start();
    final freed = _freed = own.dispose();
    await freed;
    voiceLog('model-free', {
      'model': modelId,
      'ms': watch.elapsed,
      'reason': reason,
      'kind': 'whisper',
      if (countLive) 'live': directory.liveModels(),
    });
  }

  @override
  Future<void> dispose() => release(reason: 'dispose');
}
