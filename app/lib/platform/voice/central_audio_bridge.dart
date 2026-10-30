import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../channels.dart';

/// Bridge interface to the native central audio capture service (WP180, ADR 0024).
abstract interface class CentralAudioBridge {
  /// Whether the central audio service is running and available.
  Future<bool> isAvailable();

  /// Starts streaming audio from the central service for [kind] ('session' or 'enroll').
  ///
  /// If [preRollMs] is given, the stream begins with the pre-roll audio from the ring buffer.
  Stream<Int16List> start({required String kind, int? preRollMs});

  /// Stops the current audio stream from the central service.
  Future<void> stop({String? kind});
}

/// Stand-in for [CentralAudioBridge] when central audio is unavailable (e.g. desktop/tests).
final class UnavailableCentralAudioBridge implements CentralAudioBridge {
  /// Creates an unavailable bridge.
  const UnavailableCentralAudioBridge();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Stream<Int16List> start({required String kind, int? preRollMs}) =>
      const Stream.empty();

  @override
  Future<void> stop({String? kind}) async {}
}

/// Platform channel implementation of [CentralAudioBridge] on [centralAudioChannelName].
final class ChannelCentralAudioBridge implements CentralAudioBridge {
  /// Creates the bridge on [channel].
  ChannelCentralAudioBridge([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(centralAudioChannelName);

  final MethodChannel _channel;
  StreamController<Int16List>? _controller;

  @override
  Future<bool> isAvailable() async {
    try {
      final res = await _channel
          .invokeMethod<bool>('isAvailable')
          .timeout(const Duration(milliseconds: 500), onTimeout: () => false);
      return res ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Stream<Int16List> start({required String kind, int? preRollMs}) {
    final existing = _controller;
    if (existing != null && !existing.isClosed) {
      unawaited(existing.close());
    }
    final controller = StreamController<Int16List>();
    _controller = controller;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'audioChunk':
          final args = call.arguments;
          final pcm = args is Map ? args['pcm'] as Uint8List? : null;
          if (pcm != null && pcm.length >= 2 && !controller.isClosed) {
            controller.add(_bytesToSamples(pcm));
          }
        case 'audioError':
          final args = call.arguments;
          final error =
              (args is Map ? args['error'] as String? : null) ?? 'audioError';
          if (!controller.isClosed) {
            controller.addError(StateError(error));
          }
      }
    });

    () async {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>('start', {
          'kind': kind,
          if (preRollMs != null && preRollMs > 0) 'preRollMs': preRollMs,
        });
        final started = res?['started'] == true;
        if (!started) {
          if (!controller.isClosed) {
            controller.addError(
              StateError(res?['reason']?.toString() ?? 'startFailed'),
            );
            await controller.close();
          }
          return;
        }
        final preRoll = res?['preRoll'] as Uint8List?;
        if (preRoll != null && preRoll.length >= 2 && !controller.isClosed) {
          controller.add(_bytesToSamples(preRoll));
        }
      } on Object catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stop({String? kind}) async {
    final controller = _controller;
    _controller = null;
    _channel.setMethodCallHandler(null);
    try {
      await _channel
          .invokeMethod<void>('stop', {'kind': ?kind})
          .timeout(const Duration(milliseconds: 500), onTimeout: () {});
    } on Object {
      // Ignored if channel is unavailable.
    }
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  static Int16List _bytesToSamples(Uint8List bytes) {
    final frame = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < frame.length; i++) {
      frame[i] = data.getInt16(i * 2, Endian.little);
    }
    return frame;
  }
}
