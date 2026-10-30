import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'central_audio_bridge.dart';

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
  StreamSubscription<Int16List>? _sub;
  StreamController<Int16List>? _controller;
  bool _usingFallback = false;

  @override
  bool get isRunning => _controller != null && !_controller!.isClosed;

  /// Whether the input currently streams from the fallback input.
  bool get isUsingFallback => _usingFallback;

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
    final controller = StreamController<Int16List>();
    _controller = controller;

    if (!isAndroid || _available == false) {
      _useFallback(controller);
      return controller.stream;
    }

    () async {
      final available = await _bridge.isAvailable();
      _available = available;
      if (_controller != controller) {
        return;
      }
      if (!available) {
        _useFallback(controller);
        return;
      }
      try {
        final stream = _bridge.start(kind: kind, preRollMs: preRollMs);
        if (_controller != controller) {
          await _bridge.stop(kind: kind);
          return;
        }
        _usingFallback = false;
        _sub = stream.listen(
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
      } on Object catch (e) {
        if (_controller == controller) {
          _useFallback(controller, cause: e);
        }
      }
    }();

    return controller.stream;
  }

  void _useFallback(StreamController<Int16List> controller, {Object? cause}) {
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
    _usingFallback = true;
    try {
      _sub = fb.start().listen(
        controller.add,
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
        onDone: () {
          if (!controller.isClosed) unawaited(controller.close());
        },
      );
    } on Object catch (e, st) {
      if (!controller.isClosed) {
        controller.addError(e, st);
        unawaited(controller.close());
      }
    }
  }

  @override
  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    final controller = _controller;
    _controller = null;
    final wasFallback = _usingFallback;
    _usingFallback = false;

    unawaited(sub?.cancel());
    if (wasFallback) {
      await fallback?.stop();
    } else {
      await _bridge.stop(kind: kind);
    }
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  @override
  Future<void> Function()? detach() => stop;

  /// Closes active subscriptions and controllers.
  void close() {
    _sub?.cancel();
    _controller?.close();
  }
}
