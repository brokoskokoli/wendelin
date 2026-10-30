import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../channels.dart';

/// Bridge interface to the native central audio capture service (WP180, WP184, ADR 0024).
abstract interface class CentralAudioBridge {
  /// Whether the central audio service is running and available.
  Future<bool> isAvailable();

  /// Starts streaming audio from the central service for [kind] ('session' or 'enroll').
  ///
  /// If [preRollMs] is given, the stream begins with the pre-roll audio from the ring buffer.
  /// If [subId] is provided, it identifies this subscription; otherwise one is generated.
  Stream<Int16List> start({
    required String kind,
    int? preRollMs,
    String? subId,
  });

  /// Stops audio streaming from the central service.
  /// If [subId] is given, only that subscription is stopped; otherwise all are stopped.
  Future<void> stop({String? subId, String? kind});
}

/// Stand-in for [CentralAudioBridge] when central audio is unavailable (e.g. desktop/tests).
final class UnavailableCentralAudioBridge implements CentralAudioBridge {
  /// Creates an unavailable bridge.
  const UnavailableCentralAudioBridge();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Stream<Int16List> start({
    required String kind,
    int? preRollMs,
    String? subId,
  }) => const Stream.empty();

  @override
  Future<void> stop({String? subId, String? kind}) async {}
}

/// Platform channel implementation of [CentralAudioBridge] on [centralAudioChannelName].
final class ChannelCentralAudioBridge implements CentralAudioBridge {
  /// Creates the bridge on [channel].
  ChannelCentralAudioBridge([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(centralAudioChannelName) {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;
  final Map<String, StreamController<Int16List>> _controllers = {};
  int _nextId = 0;

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'audioChunk':
        final args = call.arguments;
        if (args is Map) {
          final subId = args['subId'] as String?;
          final pcm = args['pcm'] as Uint8List?;
          if (pcm != null && pcm.length >= 2) {
            final samples = _bytesToSamples(pcm);
            if (subId != null) {
              if (_controllers[subId]?.isClosed == false) {
                _controllers[subId]!.add(samples);
              }
            } else {
              for (final entry in _controllers.entries) {
                if (!entry.value.isClosed) entry.value.add(samples);
              }
            }
          }
        }
      case 'audioError':
        final args = call.arguments;
        if (args is Map) {
          final subId = args['subId'] as String?;
          final error = (args['error'] as String?) ?? 'audioError';
          final err = StateError(error);
          if (subId != null) {
            if (_controllers[subId]?.isClosed == false) {
              _controllers[subId]!.addError(err);
            }
          } else {
            for (final entry in _controllers.entries) {
              if (!entry.value.isClosed) entry.value.addError(err);
            }
          }
        }
    }
  }

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

  StreamController<Int16List> _newController() => StreamController<Int16List>();

  @override
  Stream<Int16List> start({
    required String kind,
    int? preRollMs,
    String? subId,
  }) {
    final id = subId ?? '${kind}_${++_nextId}';
    final controller = _newController();
    _controllers[id] = controller;

    () async {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>('start', {
          'kind': kind,
          'subId': id,
          if (preRollMs != null && preRollMs > 0) 'preRollMs': preRollMs,
        });
        final started = res?['started'] == true;
        if (!started) {
          _controllers.remove(id);
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
        _controllers.remove(id);
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stop({String? subId, String? kind}) async {
    if (subId != null) {
      final c = _controllers.remove(subId);
      try {
        await _channel
            .invokeMethod<void>('stop', {'subId': subId, 'kind': ?kind})
            .timeout(const Duration(milliseconds: 500), onTimeout: () {});
      } on Object {
        // Ignored if channel is unavailable.
      }
      if (c != null && !c.isClosed) {
        await c.close();
      }
    } else {
      final list = _controllers.values.toList();
      _controllers.clear();
      try {
        await _channel
            .invokeMethod<void>('stop', {'kind': ?kind})
            .timeout(const Duration(milliseconds: 500), onTimeout: () {});
      } on Object {
        // Ignored if channel is unavailable.
      }
      for (final c in list) {
        if (!c.isClosed) await c.close();
      }
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
