import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/central_audio_bridge.dart';
import 'package:wendelin/platform/voice/central_audio_input.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

class FakeCentralAudioBridge implements CentralAudioBridge {
  FakeCentralAudioBridge({this.available = true});

  bool available;
  final List<String> startedKinds = [];
  final List<int?> startedPreRolls = [];
  final List<String?> startedSubIds = [];
  final List<String?> stoppedSubIds = [];
  final List<String?> stoppedKinds = [];
  final Map<String, StreamController<Int16List>> controllers = {};
  int _nextId = 0;

  String? get lastStartedKind => startedKinds.lastOrNull;
  int? get lastStartedPreRollMs => startedPreRolls.lastOrNull;
  String? get lastStoppedKind => stoppedKinds.lastOrNull;
  StreamController<Int16List>? get controller => controllers.values.lastOrNull;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<Int16List> start({
    required String kind,
    int? preRollMs,
    String? subId,
  }) {
    final id = subId ?? 'sub_${++_nextId}';
    startedKinds.add(kind);
    startedPreRolls.add(preRollMs);
    startedSubIds.add(id);
    controllers[id] = StreamController<Int16List>();
    return controllers[id]!.stream;
  }

  @override
  Future<void> stop({String? subId, String? kind}) async {
    stoppedSubIds.add(subId);
    stoppedKinds.add(kind);
    if (subId != null) {
      final c = controllers.remove(subId);
      await c?.close();
    } else {
      for (final c in controllers.values) {
        await c.close();
      }
      controllers.clear();
    }
  }

  void close() {
    for (final c in controllers.values) {
      c.close();
    }
    controllers.clear();
  }
}

class FakeFallbackAudioInput implements AudioInput {
  StreamController<Int16List>? controller;
  var startCount = 0;
  var stopCount = 0;

  @override
  bool get isRunning => controller != null && !controller!.isClosed;

  @override
  Stream<Int16List> start() {
    startCount++;
    controller = StreamController<Int16List>();
    return controller!.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await controller?.close();
    controller = null;
  }

  void close() {
    controller?.close();
  }
}

void main() {
  group('CentralAudioInput', () {
    late FakeCentralAudioBridge bridge;
    late FakeFallbackAudioInput fallback;

    setUp(() {
      bridge = FakeCentralAudioBridge(available: true);
      fallback = FakeFallbackAudioInput();
    });

    test('streams from bridge on Android when available', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        kind: 'session',
        isAndroid: true,
      );

      final stream = input.start(preRollMs: 2000);
      expect(input.isRunning, isTrue);

      final received = <Int16List>[];
      final sub = stream.listen(received.add);

      await pumpEventQueue();

      expect(bridge.lastStartedKind, 'session');
      expect(bridge.lastStartedPreRollMs, 2000);
      expect(input.isUsingFallback, isFalse);
      expect(fallback.startCount, 0);

      // Push a frame from bridge
      final frame = Int16List.fromList([100, 200]);
      bridge.controller?.add(frame);

      await pumpEventQueue();
      expect(received.single, frame);

      await input.stop();
      expect(input.isRunning, isFalse);
      expect(bridge.lastStoppedKind, 'session');
      await sub.cancel();
    });

    test('withKind creates input with specified kind', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        kind: 'session',
        isAndroid: true,
      );
      final enrollInput = input.withKind('enroll');
      expect(enrollInput.kind, 'enroll');

      final stream = enrollInput.start();
      final sub = stream.listen((_) {});
      await pumpEventQueue();

      expect(bridge.lastStartedKind, 'enroll');
      await enrollInput.stop();
      await sub.cancel();
    });

    test('falls back to fallback input when not on Android', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: false,
      );

      final stream = input.start();
      final received = <Int16List>[];
      final sub = stream.listen(received.add);

      await pumpEventQueue();

      expect(input.isUsingFallback, isTrue);
      expect(fallback.startCount, 1);
      expect(bridge.lastStartedKind, isNull);

      final frame = Int16List.fromList([300, 400]);
      fallback.controller?.add(frame);

      await pumpEventQueue();
      expect(received.single, frame);

      await input.stop();
      expect(fallback.stopCount, 1);
      await sub.cancel();
    });

    test('falls back when bridge is not available on Android', () async {
      bridge.available = false;
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );

      final stream = input.start();
      final sub = stream.listen((_) {});
      await pumpEventQueue();

      expect(input.isUsingFallback, isTrue);
      expect(fallback.startCount, 1);

      await input.stop();
      await sub.cancel();
    });

    test(
      'emits VoiceException when bridge unavailable and no fallback',
      () async {
        bridge.available = false;
        final input = CentralAudioInput(
          bridge: bridge,
          fallback: null,
          isAndroid: true,
        );

        final stream = input.start();
        Object? errorSeen;
        final sub = stream.listen(
          (_) {},
          onError: (Object e) {
            errorSeen = e;
          },
        );

        await pumpEventQueue();

        expect(errorSeen, isA<VoiceException>());
        expect((errorSeen as VoiceException).kind, VoiceErrorKind.unavailable);
        await sub.cancel();
      },
    );

    test('start throws VoiceException busy when called while running', () {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );
      input.start();

      expect(
        () => input.start(),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.busy,
          ),
        ),
      );
    });

    test('forwards errors from bridge as VoiceException', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );
      final stream = input.start();
      Object? errorSeen;
      final sub = stream.listen(
        (_) {},
        onError: (Object e) {
          errorSeen = e;
        },
      );

      await pumpEventQueue();

      bridge.controller?.addError(StateError('mic crashed'));
      await pumpEventQueue();

      expect(errorSeen, isA<VoiceException>());
      await sub.cancel();
    });

    test('detach returns null when not running', () {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );
      expect(input.detach(), isNull);
    });

    test('detach frees isRunning immediately and enables subsequent start without busy', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );
      final stream1 = input.start();
      expect(input.isRunning, isTrue);

      final rec1 = <Int16List>[];
      final sub1 = stream1.listen(rec1.add);
      await pumpEventQueue();

      final closer1 = input.detach();
      expect(closer1, isNotNull);
      // isRunning is immediately false after detach!
      expect(input.isRunning, isFalse);

      // Subsequent start can begin immediately without VoiceErrorKind.busy
      final stream2 = input.start();
      expect(input.isRunning, isTrue);
      final rec2 = <Int16List>[];
      final sub2 = stream2.listen(rec2.add);
      await pumpEventQueue();

      expect(bridge.startedSubIds.length, 2);
      final subId1 = bridge.startedSubIds[0]!;
      final subId2 = bridge.startedSubIds[1]!;
      expect(subId1, isNot(equals(subId2)));

      // Frame to detached stream 1
      bridge.controllers[subId1]?.add(Int16List.fromList([10, 20]));
      // Frame to active stream 2
      bridge.controllers[subId2]?.add(Int16List.fromList([30, 40]));
      await pumpEventQueue();

      expect(rec1.single, [10, 20]);
      expect(rec2.single, [30, 40]);

      // Stopping the active input does not stop the detached stream
      await input.stop();
      expect(input.isRunning, isFalse);
      expect(bridge.controllers.containsKey(subId1), isTrue);

      // Closing the detached stream cleans it up
      await closer1!();
      expect(bridge.controllers.containsKey(subId1), isFalse);

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
