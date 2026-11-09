import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/wake/service_audio_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('test/service-audio-input');
  late List<(String, Object?)> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add((call.method, call.arguments));
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  int lastToken() =>
      (calls.lastWhere((c) => c.$1 == 'startMic').$2! as Map)['token']! as int;

  Uint8List chunk() => Uint8List(3200);

  test('WP189: jeder Start sendet ein neues Token, nach Pause und Fortsetzen '
      'zählt ein verspäteter Block des alten Stroms nicht', () async {
    final input = ServiceAudioInput(channel);
    final first = <Int16List>[];
    final sub1 = input.start().listen(first.add);
    await pumpEventQueue();
    final t1 = lastToken();
    input.push(chunk(), token: t1);
    await pumpEventQueue();
    expect(first, hasLength(1));

    // Pause (overlay) and resume: a new stream with a new token.
    await sub1.cancel();
    await input.stop();
    final second = <Int16List>[];
    input.start().listen(second.add);
    await pumpEventQueue();
    final t2 = lastToken();
    expect(t2, isNot(t1));

    // Still on its way from the first stream: dropped; the new one counts.
    input.push(chunk(), token: t1);
    input.push(chunk(), token: t2);
    await pumpEventQueue();
    expect(second, hasLength(1));
    await input.stop();
  });

  test('ein Block ohne Token (alter Dienst, Tests) wird angenommen', () async {
    final input = ServiceAudioInput(channel);
    final got = <Int16List>[];
    input.start().listen(got.add);
    await pumpEventQueue();
    input.push(chunk());
    await pumpEventQueue();
    expect(got, hasLength(1));
    await input.stop();
  });
}
