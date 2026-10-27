import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/platform/channel_station_port.dart';
import 'package:wendelin/platform/screen_protection.dart';
import 'package:wendelin/station/station_display.dart';
import 'package:wendelin/station/station_host.dart';
import 'package:wendelin/station/station_providers.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const station = MethodChannel(stationChannelName);
  const window = MethodChannel(windowChannelName);
  const assistant = MethodChannel(assistantChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var locked = false;
  var lockedAnswer = true;
  bool? finishAnswer;

  String? error;

  setUp(() {
    calls.clear();
    locked = false;
    lockedAnswer = true;
    error = null;
    messenger.setMockMethodCallHandler(station, (call) async {
      calls.add('station.${call.method}');
      if (error case final code?) throw PlatformException(code: code);
      return switch (call.method) {
        'isLocked' => lockedAnswer ? locked : null,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(assistant, (call) async => finishAnswer);
    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add('window.${call.method} ${call.arguments}');
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(station, null);
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(assistant, null);
  });

  stationPortContract(() => const ChannelStationPort());

  test('start und isLocked gehen an den Kotlin-Kanal', () async {
    locked = true;
    const port = ChannelStationPort();
    expect(await port.isLocked(), isTrue);
    await port.start();
    expect(calls, ['station.isLocked', 'station.start']);
  });

  test('isLocked ohne Antwort (null) gilt als gesperrt', () async {
    lockedAnswer = false;
    expect(await const ChannelStationPort().isLocked(), isTrue);
  });

  test('finish: false vom Kanal erreicht den Host, null (Fehler) gilt als nicht geschlossen', () async {
    final host = DeviceStationHost(
      AssistantPlatform(),
      const ScreenProtection(),
    );
    finishAnswer = false;
    expect(await host.finish(), isFalse);
    finishAnswer = null;
    expect(await host.finish(), isFalse);
  });

  test('Fehler der Plattform werden zu PortException', () async {
    error = 'locked';
    await expectLater(
      const ChannelStationPort().start(),
      throwsA(isA<PortException>()),
    );
  });

  test('Bildschirmplan: Wachhalten und Helligkeit gehen ans Fenster', () async {
    final host = DeviceStationHost(
      AssistantPlatform(),
      const ScreenProtection(),
    );
    await host.applyDisplay(
      const StationDisplay(keepOn: true, brightness: StationBrightness.quiet),
    );
    expect(calls, [
      'window.setKeepScreenOn {on: true}',
      'window.setBrightness {ambient: false}',
    ]);
  });

  test('Umgebungslicht von Kotlin kommt als Strom an', () async {
    final host = DeviceStationHost(
      AssistantPlatform(),
      const ScreenProtection(),
    );
    final seen = <bool>[];
    final sub = host.ambientDark.listen(seen.add);
    await messenger.handlePlatformMessage(
      stationChannelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('ambient', {'dark': true}),
      ),
      (_) {},
    );
    expect(seen, [true]);
    await sub.cancel();
  });

  test('Host.dispose beendet den Umgebungslicht-Strom', () async {
    final host = DeviceStationHost(
      AssistantPlatform(),
      const ScreenProtection(),
    );
    var done = false;
    host.ambientDark.listen((_) {}, onDone: () => done = true);
    host.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });

  test('Provider: Container-dispose räumt den Stationshost auf', () async {
    final container = ProviderContainer();
    var done = false;
    container
        .read(stationHostProvider)
        .ambientDark
        .listen((_) {}, onDone: () => done = true);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });
}
