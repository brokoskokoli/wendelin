import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/central_audio_bridge.dart';
import 'package:wendelin/platform/voice/central_audio_input.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

class FakeCentralAudioBridge implements CentralAudioBridge {
  FakeCentralAudioBridge({this.available = true});

  bool available;
  String? lastStartedKind;
  int? lastStartedPreRollMs;
  String? lastStoppedKind;
  StreamController<Int16List>? controller;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<Int16List> start({required String kind, int? preRollMs}) {
    lastStartedKind = kind;
    lastStartedPreRollMs = preRollMs;
    controller = StreamController<Int16List>();
    return controller!.stream;
  }

  @override
  Future<void> stop({String? kind}) async {
    lastStoppedKind = kind;
    await controller?.close();
    controller = null;
  }

  void close() {
    controller?.close();
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

    test('detach calls stop', () async {
      final input = CentralAudioInput(
        bridge: bridge,
        fallback: fallback,
        isAndroid: true,
      );
      final stream = input.start();
      final sub = stream.listen((_) {});
      await pumpEventQueue();

      final detachFn = input.detach();
      expect(detachFn, isNotNull);
      await detachFn!();

      expect(input.isRunning, isFalse);
      await sub.cancel();
    });
  });
}
