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

    test('supports concurrent subscriptions with subId', () async {
      final stream1 = bridge.start(kind: 'session', subId: 'sub-1');
      final stream2 = bridge.start(kind: 'session', subId: 'sub-2');

      final rec1 = <Int16List>[];
      final rec2 = <Int16List>[];
      var done1 = false;
      var done2 = false;

      final sub1 = stream1.listen(rec1.add, onDone: () => done1 = true);
      final sub2 = stream2.listen(rec2.add, onDone: () => done2 = true);

      await pumpEventQueue();

      // Chunk for sub-1
      final chunk1 = Uint8List.fromList([0x01, 0x00]);
      final byteData1 = const StandardMethodCodec().encodeMethodCall(
        MethodCall('audioChunk', {'subId': 'sub-1', 'pcm': chunk1}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(centralAudioChannelName, byteData1, (_) {});

      // Chunk for sub-2
      final chunk2 = Uint8List.fromList([0x02, 0x00]);
      final byteData2 = const StandardMethodCodec().encodeMethodCall(
        MethodCall('audioChunk', {'subId': 'sub-2', 'pcm': chunk2}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(centralAudioChannelName, byteData2, (_) {});

      await pumpEventQueue();

      expect(rec1.length, 1);
      expect(rec1.single, [1]);
      expect(rec2.length, 1);
      expect(rec2.single, [2]);

      // Stop sub-1 selectively
      await bridge.stop(subId: 'sub-1');
      await pumpEventQueue();

      expect(done1, isTrue);
      expect(done2, isFalse);

      // Chunk for sub-2 still received
      final chunk3 = Uint8List.fromList([0x03, 0x00]);
      final byteData3 = const StandardMethodCodec().encodeMethodCall(
        MethodCall('audioChunk', {'subId': 'sub-2', 'pcm': chunk3}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(centralAudioChannelName, byteData3, (_) {});

      await pumpEventQueue();
      expect(rec2.length, 2);
      expect(rec2.last, [3]);

      await bridge.stop(subId: 'sub-2');
      await pumpEventQueue();
      expect(done2, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
