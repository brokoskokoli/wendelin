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

/// A [WhisperDirectory] that knows who uses a shared model (WP146): the owner
/// does not free it while another engine still uses it.
abstract interface class UsageAwareDirectory implements WhisperDirectory {
  /// Number of other engines that use the model [modelId] of this one.
  Future<int> users(String modelId);

  /// This engine starts using the model of another engine.
  void markUse(String modelId);

  /// This engine stops using it (the owner is told).
  void unmarkUse(String modelId);

  /// The owner hears when a user leaves.
  void watchUsers(String modelId, void Function() onLeft);

  /// Ends [watchUsers].
  void unwatchUsers(String modelId);
}

/// [WhisperDirectory] on the `IsolateNameServer` (`whisper_registry.dart`).
final class IsolateWhisperDirectory implements UsageAwareDirectory {
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

  @override
  Future<int> users(String modelId) => whisperUsers(modelId, voiceLogEngine);

  @override
  void markUse(String modelId) => markWhisperUse(voiceLogEngine, modelId);

  @override
  void unmarkUse(String modelId) => unmarkWhisperUse(voiceLogEngine, modelId);

  @override
  void watchUsers(String modelId, void Function() onLeft) =>
      watchWhisperUsers(modelId, onLeft);

  @override
  void unwatchUsers(String modelId) => unwatchWhisperUsers(modelId);
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
  // This engine uses the model of another engine (marked in the directory).
  bool _borrowing = false;
  // A release that waits for the users of the own model to leave.
  String? _deferred;

  UsageAwareDirectory? get _usage {
    final d = directory;
    return d is UsageAwareDirectory ? d : null;
  }

  /// Whether this engine holds its own model (tests, debug counter).
  bool get ownsModel => _own != null;

  /// Makes sure a model is ready: another engine's or an own one.
  Future<void> warm() async {
    _released = false;
    _deferred = null;
    await _backend();
  }

  Future<WhisperBackend> _backend() async {
    final own = _own;
    if (own != null) return own;
    final loading = _loading;
    if (loading != null) return loading;
    final shared = await directory.lookup(modelId);
    if (shared != null) {
      if (!_borrowing) {
        _borrowing = true;
        _usage?.markUse(modelId);
      }
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
      if (_released) throw _releasedWhileLoading();
      final watch = _stopwatch()..start();
      final backend = await load();
      if (_released) {
        // Released while it loaded: free it again right away.
        _freed = backend.dispose();
        voiceLog('model-free', {'model': modelId, 'reason': 'released'});
        throw _releasedWhileLoading();
      }
      _own = backend;
      directory.publish(modelId, backend);
      _usage?.watchUsers(modelId, _userLeft);
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

  static VoiceException _releasedWhileLoading() => const VoiceException(
    VoiceErrorKind.unavailable,
    'Das Whisper-Modell wurde freigegeben.',
  );

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    _released = false;
    _deferred = null;
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
  ///
  /// While another engine uses the model (the overlay), an idle release waits
  /// until it has left (WP146), also for `replaced` (the provider is rebuilt
  /// while the overlay still uses the model). Only [dispose] (the engine
  /// ends, its isolate goes with it) frees at once.
  Future<void> release({String reason = 'release'}) =>
      _release(reason, force: false);

  Future<void> _release(String reason, {required bool force}) async {
    if (_borrowing) {
      _borrowing = false;
      _usage?.unmarkUse(modelId);
    }
    final usage = _usage;
    if (!force && _own != null && usage != null) {
      // Another engine (the overlay) still uses this model: freeing it now
      // would make it load its own copy (WP146). The last user to leave
      // triggers the release.
      final users = await usage.users(modelId);
      if (_own == null) return; // freed meanwhile
      if (users > 0) {
        _deferred = reason;
        voiceLog('model-release-deferred', {
          'model': modelId,
          'users': users,
          'reason': reason,
        });
        return;
      }
    }
    _deferred = null;
    _released = true;
    final own = _own;
    _own = null;
    if (own == null) {
      // A model that is still loading is freed as soon as it is there (see
      // [_loadOwn]); wait for that, so the caller knows when nothing is left
      // (WP145: the overlay ends its engine, a model loaded after that would
      // stay in the process).
      final loading = _loading;
      if (loading != null) {
        try {
          await loading;
        } on Object {
          // Released while loading is the expected end.
        }
      }
      return;
    }
    _usage?.unwatchUsers(modelId);
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

  // A user of the model left: the release that waited for it runs now.
  void _userLeft() {
    final reason = _deferred;
    if (reason == null) return;
    unawaited(_release(reason, force: false));
  }

  @override
  Future<void> dispose() => _release('dispose', force: true);
}
