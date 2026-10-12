import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform/platform.dart';
import 'package:wendelin/platform/android_alarm_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _channel = MethodChannel('dev.fluttercommunity.plus/android_intent');

/// Stands in for android_intent_plus on a device with or without clock app.
final class _FakeIntents {
  bool clockApp = true;
  bool launchFails = false;
  final launched = <Map<Object?, Object?>>[];

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>;
    switch (call.method) {
      case 'canResolveActivity':
        return clockApp;
      case 'launch':
        if (launchFails) throw PlatformException(code: 'ActivityNotFound');
        launched.add(args);
        return null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeIntents intents;
  final android = FakePlatform(operatingSystem: 'android');

  setUp(() {
    intents = _FakeIntents();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, intents.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  alarmPortContract(
    () => AndroidAlarmPort(platform: android),
    name: 'AndroidAlarmPort',
  );

  test('kann nicht abbrechen und nicht auflisten', () async {
    final port = AndroidAlarmPort(platform: android);
    expect(port.supportsCancel, isFalse);
    expect(await port.listAlarms(), isNull);
  });

  test(
    'Wecker: SET_ALARM mit Stunde, Minute, Name, Tagen und SKIP_UI',
    () async {
      final port = AndroidAlarmPort(platform: android);
      final id = await port.setAlarm(
        hour: 6,
        minute: 30,
        label: 'Tauchen',
        days: {7, 1, 3},
      );
      expect(id, isNull);
      final intent = intents.launched.single;
      expect(intent['action'], AndroidAlarmPort.actionSetAlarm);
      expect(intent['arguments'], {
        AndroidAlarmPort.extraHour: 6,
        AndroidAlarmPort.extraMinutes: 30,
        AndroidAlarmPort.extraMessage: 'Tauchen',
        // ISO Mo=1, Mi=3, So=7 → Calendar Mo=2, Mi=4, So=1.
        AndroidAlarmPort.extraDays: [2, 4, 1],
        AndroidAlarmPort.extraSkipUi: true,
      });
    },
  );

  test('einmaliger Wecker ohne Tage und ohne leeren Namen', () async {
    await AndroidAlarmPort(platform: android)
        .setAlarm(hour: 0, minute: 0, label: '');
    expect(intents.launched.single['arguments'], {
      AndroidAlarmPort.extraHour: 0,
      AndroidAlarmPort.extraMinutes: 0,
      AndroidAlarmPort.extraSkipUi: true,
    });
  });

  test('Timer: SET_TIMER mit Länge in Sekunden', () async {
    await AndroidAlarmPort(platform: android)
        .setTimer(duration: const Duration(minutes: 5), label: 'Nudeln');
    final intent = intents.launched.single;
    expect(intent['action'], AndroidAlarmPort.actionSetTimer);
    expect(intent['arguments'], {
      AndroidAlarmPort.extraLength: 300,
      AndroidAlarmPort.extraMessage: 'Nudeln',
      AndroidAlarmPort.extraSkipUi: true,
    });
  });

  test('Timer über 24 h ist ungültig', () async {
    await expectLater(
      AndroidAlarmPort(platform: android)
          .setTimer(duration: const Duration(hours: 24, seconds: 1)),
      throwsArgumentError,
    );
    await AndroidAlarmPort(platform: android)
        .setTimer(duration: const Duration(hours: 24));
    expect(intents.launched, hasLength(1));
  });

  test('Wochentage: ISO → java.util.Calendar', () {
    expect(
      [for (var d = 1; d <= 7; d++) AndroidAlarmPort.calendarWeekday(d)],
      [2, 3, 4, 5, 6, 7, 1],
    );
  });

  group('ohne Uhr-App', () {
    setUp(() => intents.clockApp = false);

    test('ist nicht verfügbar', () async {
      expect(await AndroidAlarmPort(platform: android).isAvailable(), isFalse);
      final integration = AlarmsIntegration(
        AndroidAlarmPort(platform: android),
      );
      expect((await integration.checkAvailability()).available, isFalse);
    });

    test('Stellen meldet unavailable und startet nichts', () async {
      await expectLater(
        AndroidAlarmPort(platform: android).setAlarm(hour: 7, minute: 0),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.unavailable,
          ),
        ),
      );
      expect(intents.launched, isEmpty);
    });
  });

  test('mit Uhr-App verfügbar', () async {
    expect(await AndroidAlarmPort(platform: android).isAvailable(), isTrue);
  });

  test('abgelehnter Start wird zu PortException(failed)', () async {
    intents.launchFails = true;
    await expectLater(
      AndroidAlarmPort(platform: android).setAlarm(hour: 7, minute: 0),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.failed,
        ),
      ),
    );
  });

  test('außerhalb von Android nicht verfügbar', () async {
    final port = AndroidAlarmPort(
      platform: FakePlatform(operatingSystem: 'ios'),
    );
    expect(await port.isAvailable(), isFalse);
  });
}
