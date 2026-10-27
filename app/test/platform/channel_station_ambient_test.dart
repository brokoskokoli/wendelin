import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_station_ambient.dart';
import 'package:wendelin/platform/channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<bool> send(bool dark) async {
    var handled = false;
    await messenger.handlePlatformMessage(
      stationChannelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('ambient', {'dark': dark}),
      ),
      (reply) => handled = reply != null,
    );
    return handled;
  }

  test('dispose: Handler weg und Strom beendet', () async {
    final ambient = StationAmbientChannel();
    var done = false;
    ambient.dark.listen((_) {}, onDone: () => done = true);
    expect(await send(true), isTrue);
    ambient.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
    expect(await send(true), isFalse);
  });

  test('zwei Instanzen: die neuere gewinnt, dispose der älteren lässt ihren '
      'Handler stehen', () async {
    final old = StationAmbientChannel();
    final newer = StationAmbientChannel();
    final seenOld = <bool>[];
    final seenNew = <bool>[];
    old.dark.listen(seenOld.add);
    newer.dark.listen(seenNew.add);
    await send(true);
    expect(seenNew, [true]);
    expect(seenOld, isEmpty);
    old.dispose();
    await send(false);
    expect(seenNew, [true, false]);
    newer.dispose();
    expect(await send(true), isFalse);
  });

  test(
    'dispose ohne je zu lauschen und doppeltes dispose sind harmlos',
    () async {
      final ambient = StationAmbientChannel()..dispose();
      ambient.dispose();
      expect(await send(true), isFalse);
    },
  );
}
