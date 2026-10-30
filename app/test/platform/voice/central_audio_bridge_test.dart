import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channels.dart';
import 'package:wendelin/platform/voice/central_audio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> channelCalls;
  late ChannelCentralAudioBridge bridge;

  setUp(() {
    channelCalls = [];
    channel = const MethodChannel(centralAudioChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls.add(call);
          switch (call.method) {
            case 'isAvailable':
              return true;
            case 'start':
              return {'started': true};
            case 'stop':
              return null;
            default:
              return null;
          }
        });
    bridge = ChannelCentralAudioBridge(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ChannelCentralAudioBridge', () {
    test('isAvailable returns true when channel succeeds', () async {
      final available = await bridge.isAvailable();
      expect(available, isTrue);
      expect(channelCalls.single.method, 'isAvailable');
    });

    test('isAvailable returns false when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'ERROR', message: 'Channel error');
          });
      final available = await bridge.isAvailable();
      expect(available, isFalse);
    });

    test('start invokes channel and delivers live audio chunks', () async {
      final stream = bridge.start(kind: 'session', preRollMs: 1000);
      final received = <Int16List>[];
      final sub = stream.listen(received.add);

      await pumpEventQueue();

      expect(channelCalls.any((c) => c.method == 'start'), isTrue);
      final startCall = channelCalls.firstWhere((c) => c.method == 'start');
      final startArgs = startCall.arguments as Map;
      expect(startArgs['kind'], 'session');
      expect(startArgs['preRollMs'], 1000);

      // Simulate native sending audioChunk
      final chunkBytes = Uint8List.fromList([0x01, 0x00, 0x02, 0x00]); // 1, 2
      final byteData = const StandardMethodCodec().encodeMethodCall(
        MethodCall('audioChunk', {'pcm': chunkBytes}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(centralAudioChannelName, byteData, (_) {});

      await pumpEventQueue();
      expect(received.length, 1);
      expect(received.first, [1, 2]);

      await sub.cancel();
      await bridge.stop(kind: 'session');
    });

    test('start delivers pre-roll if returned in response', () async {
      final preRollBytes = Uint8List.fromList([0x0A, 0x00, 0x0B, 0x00]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls.add(call);
            if (call.method == 'start') {
              return {'started': true, 'preRoll': preRollBytes};
            }
            return null;
          });

      final stream = bridge.start(kind: 'session');
      final received = <Int16List>[];
      final sub = stream.listen(received.add);

      await pumpEventQueue();

      expect(received.length, 1);
      expect(received.first, [10, 11]);

      await sub.cancel();
      await bridge.stop();
    });

    test('start emits error if native reports startFailed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls.add(call);
            if (call.method == 'start') {
              return {'started': false, 'reason': 'busy'};
            }
            return null;
          });

      final stream = bridge.start(kind: 'session');
      Object? errorSeen;
      final sub = stream.listen(
        (_) {},
        onError: (Object e) {
          errorSeen = e;
        },
      );

      await pumpEventQueue();

      expect(errorSeen, isA<StateError>());
      await sub.cancel();
    });

    test('emits error on audioError from native', () async {
      final stream = bridge.start(kind: 'enroll');
      Object? errorSeen;
      final sub = stream.listen(
        (_) {},
        onError: (Object e) {
          errorSeen = e;
        },
      );

      await pumpEventQueue();

      final byteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('audioError', {'error': 'micDisconnected'}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(centralAudioChannelName, byteData, (_) {});

      await pumpEventQueue();

      expect(errorSeen, isA<StateError>());
      await sub.cancel();
    });

    test('stop sends stop to channel and closes stream', () async {
      final stream = bridge.start(kind: 'session');
      var closed = false;
      final sub = stream.listen((_) {}, onDone: () => closed = true);

      await pumpEventQueue();
      await bridge.stop(kind: 'session');
      await pumpEventQueue();

      expect(closed, isTrue);
      expect(channelCalls.any((c) => c.method == 'stop'), isTrue);
      await sub.cancel();
    });
  });
}
