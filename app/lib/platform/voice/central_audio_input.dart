import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'central_audio_bridge.dart';

/// Single active or detached stream session of [CentralAudioInput] (WP184).
final class _ActiveStream {
  _ActiveStream({
    required this.subId,
    required this.controller,
    required this.isFallback,
  });

  final String subId;
  final StreamController<Int16List> controller;
  bool isFallback;
  void Function()? cancelSubscription;
  Future<void> Function()? fallbackCloser;
  bool closed = false;

  Future<void> close(
    CentralAudioBridge bridge,
    String kind,
    AudioInput? fallback,
  ) async {
    if (closed) return;
    closed = true;
    final cancel = cancelSubscription;
    cancelSubscription = null;
    cancel?.call();
    if (isFallback) {
      if (fallbackCloser != null) {
        await fallbackCloser!();
      } else {
        await fallback?.stop();
      }
    } else {
      await bridge.stop(subId: subId, kind: kind);
    }
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }
}

StreamController<Int16List> _newController() => StreamController<Int16List>();

/// [AudioInput] connecting to the central audio service on Android (WP180, ADR 0024).
///
/// Uses [bridge] to stream from the central Kotlin audio source without opening a competing
/// `AudioRecord`. Falls back to [fallback] when central audio is not available (e.g. desktop,
/// unit tests without the Android service).
final class CentralAudioInput implements DetachableAudioInput {
  /// Creates the central audio input.
  CentralAudioInput({
    CentralAudioBridge? bridge,
    this.fallback,
    this.kind = 'session',
    bool? isAndroid,
  }) : _bridge = bridge ?? ChannelCentralAudioBridge(),
       isAndroid =
           isAndroid ?? (defaultTargetPlatform == TargetPlatform.android) {
    if (!this.isAndroid) {
      _available = false;
    }
  }

  final CentralAudioBridge _bridge;

  /// Fallback audio input when central audio is unavailable.
  final AudioInput? fallback;

  /// Subscriber kind ('session' or 'enroll').
  final String kind;

  /// Whether running on Android (injected for tests).
  final bool isAndroid;

  bool? _available;
  int _subCounter = 0;
  _ActiveStream? _active;
  final List<_ActiveStream> _detached = [];

  @override
  bool get isRunning => _active != null && !_active!.controller.isClosed;

  /// Whether the input currently streams from the fallback input.
  bool get isUsingFallback => _active?.isFallback ?? false;

  /// Creates a copy of this input configured for [newKind] (e.g. 'enroll').
  CentralAudioInput withKind(String newKind) => CentralAudioInput(
    bridge: _bridge,
    fallback: fallback,
    kind: newKind,
    isAndroid: isAndroid,
  );

  @override
  Stream<Int16List> start({int? preRollMs}) {
    if (isRunning) {
      throw const VoiceException(
        VoiceErrorKind.busy,
        'CentralAudioInput stream runs already.',
      );
    }
    final subId = '${kind}_${++_subCounter}';
    final controller = _newController();
    final active = _ActiveStream(
      subId: subId,
      controller: controller,
      isFallback: !isAndroid || _available == false,
    );
    _active = active;

    if (!isAndroid || _available == false) {
      _useFallback(active);
      return controller.stream;
    }

    () async {
      final available = await _bridge.isAvailable();
      _available = available;
      if (active.closed) {
        return;
      }
      if (!available) {
        active.isFallback = true;
        _useFallback(active);
        return;
      }
      try {
        final stream = _bridge.start(
          kind: kind,
          preRollMs: preRollMs,
          subId: subId,
        );
        if (active.closed) {
          await _bridge.stop(subId: subId, kind: kind);
          return;
        }
        active.isFallback = false;
        final sub = stream.listen(
          controller.add,
          onError: (Object e) {
            if (!controller.isClosed) {
              controller.addError(
                e is VoiceException
                    ? e
                    : VoiceException(
                        VoiceErrorKind.unavailable,
                        '$e',
                        cause: e,
                      ),
              );
            }
          },
          onDone: () {
            if (!controller.isClosed) unawaited(controller.close());
          },
        );
        active.cancelSubscription = () => unawaited(sub.cancel());
      } on Object catch (e) {
        if (!active.closed) {
          active.isFallback = true;
          _useFallback(active, cause: e);
        }
      }
    }();

    return controller.stream;
  }

  void _useFallback(_ActiveStream active, {Object? cause}) {
    final controller = active.controller;
    final fb = fallback;
    if (fb == null) {
      if (!controller.isClosed) {
        controller.addError(
          VoiceException(
            VoiceErrorKind.unavailable,
            'Zentraler Audiodienst nicht verfügbar und kein Rückfall konfiguriert.',
            cause: cause,
          ),
        );
        unawaited(controller.close());
      }
      return;
    }
    try {
      final sub = fb.start().listen(
        controller.add,
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
        onDone: () {
          if (!controller.isClosed) unawaited(controller.close());
        },
      );
      active.cancelSubscription = () => unawaited(sub.cancel());
    } on Object catch (e, st) {
      if (!controller.isClosed) {
        controller.addError(e, st);
        unawaited(controller.close());
      }
    }
  }

  @override
  Future<void> stop() async {
    final active = _active;
    _active = null;
    if (active != null) {
      await active.close(_bridge, kind, fallback);
    }
  }

  @override
  Future<void> Function()? detach() {
    final active = _active;
    if (active == null || active.closed) return null;
    _active = null;
    _detached.add(active);

    if (active.isFallback && fallback is DetachableAudioInput) {
      active.fallbackCloser = (fallback as DetachableAudioInput).detach();
    }

    return () async {
      _detached.remove(active);
      await active.close(_bridge, kind, fallback);
    };
  }

  /// Closes active and detached subscriptions and controllers.
  Future<void> dispose() async {
    await stop();
    final detachedList = List<_ActiveStream>.from(_detached);
    _detached.clear();
    for (final s in detachedList) {
      await s.close(_bridge, kind, fallback);
    }
  }
}
