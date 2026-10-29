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
    expect(sent, {
      'enabled': true,
      'mode': 'always',
      'verify': false,
      'verifyB': true,
      'verifyModel': false,
      'detector': 'auto',
    });
  });

  test('setTexts schickt die Texte unverändert an den Kanal', () async {
    Object? sent;
    String? method;
    messenger.setMockMethodCallHandler(channel, (call) async {
      method = call.method;
      sent = call.arguments;
      return null;
    });
    await WakePlatform().setTexts({'off': 'Off', 'pausedText': 'Until {time}'});
    expect(method, 'texts');
    expect(sent, {
      'texts': {'off': 'Off', 'pausedText': 'Until {time}'},
    });
  });

  test('recheckStage2 ruft den Kanal „recheck“; Fehler sind still', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    await WakePlatform().recheckStage2();
    expect(methods, ['recheck']);
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'x');
    });
    await WakePlatform().recheckStage2();
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
        'offByUser': true,
      },
    );
    final s = await WakePlatform().status();
    expect(s.running, isTrue);
    expect(s.holdsRole, isTrue);
    expect(s.charging, isTrue);
    expect(s.pausedUntil, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    expect(s.lastStop, 'unplug');
    expect(s.offByUser, isTrue);
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

  test('WP93: Sichtbarkeit, Ende des Chat-Zuges und Debug-Treffer', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'debugHit' ? true : null;
    });
    final p = WakePlatform();
    await p.setChatVisible(visible: true);
    await p.chatDone();
    expect(await p.debugHit(), isTrue);
    expect(calls.map((c) => c.method), ['chatVisible', 'chatDone', 'debugHit']);
    expect(calls.first.arguments, {'visible': true});
  });

  test(
    'WP93: wakeHit von Kotlin fragt den Chat, ohne Chat keine Antwort',
    () async {
      final p = WakePlatform();
      p.onWakeHit = () async => true;
      Future<Object?> ask() async {
        Object? out;
        await messenger.handlePlatformMessage(
          wakeChannelName,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('wakeHit'),
          ),
          (data) => out = const StandardMethodCodec().decodeEnvelope(data!),
        );
        return out;
      }

      expect(await ask(), isTrue);
      p.onWakeHit = null;
      expect(p.onWakeHit, isNull);
    },
  );
}
