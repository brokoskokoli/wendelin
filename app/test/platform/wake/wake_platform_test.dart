import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(wakeChannelName);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('configure schickt Schalter, Bedingung und Nachprüfung', () async {
    Object? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'configure');
      sent = call.arguments;
      return null;
    });
    await WakePlatform().configure(
      enabled: true,
      condition: WakeCondition.always,
      verify: false,
    );
    expect(sent, {'enabled': true, 'mode': 'always', 'verify': false});
  });

  test('status liest die Antwort von Kotlin', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'running': true,
        'holdsRole': true,
        'charging': true,
        'pausedUntil': 1760000000000,
        'lastStop': 'unplug',
      },
    );
    final s = await WakePlatform().status();
    expect(s.running, isTrue);
    expect(s.holdsRole, isTrue);
    expect(s.charging, isTrue);
    expect(s.pausedUntil, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    expect(s.lastStop, 'unplug');
  });

  test('ohne Android oder bei Fehlern: nicht aktiv, keine Ausnahme', () async {
    final p = WakePlatform();
    await p.configure(
      enabled: true,
      condition: WakeCondition.charging,
      verify: true,
    );
    expect((await p.status()).running, isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'x'),
    );
    expect((await p.status()).running, isFalse);
    expect(WakeServiceStatus.fromChannel('x').running, isFalse);
  });

  test('Bedingung: unbekannte Werte geben „nur beim Laden“', () {
    expect(WakeCondition.parse('always'), WakeCondition.always);
    expect(WakeCondition.parse('x'), WakeCondition.charging);
    expect(WakeCondition.parse(null), WakeCondition.charging);
  });
}
