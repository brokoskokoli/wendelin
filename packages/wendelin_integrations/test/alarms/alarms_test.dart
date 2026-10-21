import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeAlarmPort port;
  late AlarmsIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  setUp(() {
    port = FakeAlarmPort();
    integration = AlarmsIntegration(port);
  });

  test('Integration: Metadaten', () async {
    expect(integration.id, 'alarms');
    expect(integration.displayName, 'Wecker und Timer');
    expect(integration.iconId, 'alarm');
    expect(integration.sensitive, isFalse);
    expect(integration.platforms, hasLength(2));
    expect(await integration.checkAvailability(), Availability.yes);
    expect(integration.setup, isEmpty);
    expect((await integration.setupState()).complete, isTrue);
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'alarms__set_alarm': RiskLevel.write,
        'alarms__set_timer': RiskLevel.write,
        'alarms__list': RiskLevel.read,
      },
    );
  });

  test('Verfügbarkeit kommt vom Port', () async {
    port.available = false;
    final a = await integration.checkAvailability();
    expect(a.available, isFalse);
    expect(a.reason, contains('keine Wecker'));
  });

  test('germanDays und germanDuration', () {
    expect(germanDays({}), 'einmalig');
    expect(germanDays({1, 2, 3, 4, 5}), 'Mo–Fr');
    expect(germanDays({7, 6}), 'Sa, So');
    expect(germanDays({1, 2, 3, 4, 5, 6, 7}), 'täglich');
    expect(germanDuration(const Duration(minutes: 10)), '10 min');
    expect(
      germanDuration(const Duration(minutes: 90, seconds: 5)),
      '1 h 30 min 5 s',
    );
    expect(germanDuration(const Duration(seconds: 45)), '45 s');
    expect(germanDuration(Duration.zero), '0 s');
  });

  group('alarms__set_alarm', () {
    test('Erfolg mit Tagen und Name; Undo löscht', () async {
      final o = await tool('alarms__set_alarm').execute({
        'time': '06:45',
        'label': 'Tauchen',
        'days': [5, 1, 2, 3, 4],
      }, ctx());
      expect(o.isError, isFalse);
      expect(port.alarms.single.hour, 6);
      expect(port.alarms.single.minute, 45);
      expect(port.alarms.single.days, {1, 2, 3, 4, 5});
      expect(port.alarms.single.label, 'Tauchen');
      expect(o.text, 'Wecker gestellt: 06:45 (Mo–Fr), „Tauchen“.');
      expect(o.summary, 'Wecker gestellt: 06:45 (Mo–Fr)');
      expect(o.undo!.label, 'Wecker löschen');
      await o.undo!();
      expect(port.alarms, isEmpty);
    });

    test('einmalig ohne Name: Port bekommt keine Tage', () async {
      final o = await tool('alarms__set_alarm')
          .execute({'time': '7:00', 'label': ''}, ctx());
      expect(o.text, 'Wecker gestellt: 07:00 (einmalig).');
      expect(port.alarms.single.label, isNull);
      expect(port.alarms.single.days, isEmpty);
    });

    test('Plattform ohne Handle: kein Undo', () async {
      port = FakeAlarmPort(returnsIds: false);
      integration = AlarmsIntegration(port);
      final o = await tool('alarms__set_alarm')
          .execute({'time': '07:00'}, ctx());
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
    });

    test('Port-Fehler', () async {
      port.failNext('setAlarm');
      final o = await tool('alarms__set_alarm')
          .execute({'time': '07:00'}, ctx());
      expect(o.isError, isTrue);
    });

    for (final (label, args) in [
      ('Zeit fehlt', <String, Object?>{}),
      ('24:00', {'time': '24:00'}),
      ('kein HH:MM', {'time': '7 Uhr'}),
      (
        'Tag 0',
        {
          'time': '07:00',
          'days': [0],
        },
      ),
      ('Tage kein Array', {'time': '07:00', 'days': 'Mo'}),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await tool('alarms__set_alarm').execute(args, ctx());
        expect(o.isError, isTrue);
        expect(o.text, startsWith('Ungültige Argumente'));
        expect(port.alarms, isEmpty);
      });
    }

    test('Bestätigungstext', () {
      final t = tool('alarms__set_alarm');
      expect(
        t.describeForConfirmation({
          'time': '06:45',
          'days': [6, 7],
        }),
        'Wecker 06:45 (Sa, So) stellen',
      );
      expect(t.describeForConfirmation({}), 'Wecker stellen');
    });
  });

  group('alarms__set_timer', () {
    test('Erfolg; Ablaufzeit in Ortszeit; Undo löscht', () async {
      final o = await tool('alarms__set_timer')
          .execute({'duration_seconds': 600, 'label': 'Nudeln'}, ctx());
      expect(o.isError, isFalse);
      expect(port.timers.single.duration, const Duration(minutes: 10));
      expect(port.timers.single.label, 'Nudeln');
      expect(
        o.text,
        'Timer gestellt: 10 min, „Nudeln“; läuft ab um 2026-10-13T14:10:00+02:00.',
      );
      expect(o.summary, 'Timer: 10 min');
      await o.undo!();
      expect(port.timers, isEmpty);
    });

    test('ohne Name, als 90.0 gesendet; ohne Handle kein Undo', () async {
      port = FakeAlarmPort(returnsIds: false);
      integration = AlarmsIntegration(port);
      final o = await tool('alarms__set_timer')
          .execute({'duration_seconds': 90.0}, ctx());
      expect(o.text, startsWith('Timer gestellt: 1 min 30 s;'));
      expect(port.timers.single.label, isNull);
      expect(o.undo, isNull);
    });

    test('Port-Fehler', () async {
      port.failNext('setTimer');
      final o = await tool('alarms__set_timer')
          .execute({'duration_seconds': 60}, ctx());
      expect(o.isError, isTrue);
    });

    for (final args in [
      <String, Object?>{},
      {'duration_seconds': 0},
      {'duration_seconds': SetTimerTool.maxSeconds + 1},
      {'duration_seconds': '10 min'},
    ]) {
      test('ungültige Argumente: $args', () async {
        final o = await tool('alarms__set_timer').execute(args, ctx());
        expect(o.isError, isTrue);
        expect(port.timers, isEmpty);
      });
    }

    test('Bestätigungstext', () {
      final t = tool('alarms__set_timer');
      expect(
        t.describeForConfirmation({'duration_seconds': 3600}),
        'Timer 1 h stellen',
      );
      expect(t.describeForConfirmation({}), 'Timer stellen');
    });
  });

  group('alarms__list', () {
    test('Erfolg sortiert', () async {
      await port.setAlarm(hour: 9, minute: 0, label: 'Spät');
      await port.setAlarm(hour: 6, minute: 30, days: {6, 7});
      port.alarms.add(AlarmInfo(hour: 7, minute: 0, enabled: false));
      final o = await tool('alarms__list').execute({}, ctx());
      expect(o.isError, isFalse);
      expect(json(o)['alarms'], [
        {'time': '06:30', 'days': 'Sa, So'},
        {'time': '07:00', 'days': 'einmalig', 'enabled': false},
        {'time': '09:00', 'label': 'Spät', 'days': 'einmalig'},
      ]);
      expect(o.summary, '3 Wecker');
    });

    test('nur nächster Wecker (Android): only_next und Hinweis', () async {
      port = FakeAlarmPort(onlyNext: true);
      integration = AlarmsIntegration(port);
      await port.setAlarm(hour: 9, minute: 0);
      await port.setAlarm(hour: 6, minute: 30);
      final o = await tool('alarms__list').execute({}, ctx());
      final j = json(o);
      expect(j['only_next'], isTrue);
      expect(j['alarms'], [
        {'time': '06:30', 'days': 'einmalig'},
      ]);
      expect(j['note'], contains('Nur der nächste Wecker'));
      expect(o.summary, 'Nächster Wecker 06:30');
    });

    test('nur nächster Wecker mit Zeitpunkt: next_ring in Ortszeit', () async {
      port = FakeAlarmPort(onlyNext: true)
        ..alarms.add(
          AlarmInfo(hour: 7, minute: 5, at: DateTime.utc(2026, 10, 22, 5, 5)),
        );
      integration = AlarmsIntegration(port);
      final o = await tool('alarms__list').execute({}, ctx());
      final ring = ((json(o)['alarms'] as List).single as Map)['next_ring'];
      expect(ring, startsWith('2026-10-22T07:05'));
    });

    test('kein Wecker gestellt: leere Liste, kein Fehler', () async {
      port = FakeAlarmPort(onlyNext: true);
      integration = AlarmsIntegration(port);
      final o = await tool('alarms__list').execute({}, ctx());
      expect(o.isError, isFalse);
      expect(json(o)['alarms'], isEmpty);
      expect(json(o)['note'], 'Es ist kein Wecker gestellt.');
      expect(o.summary, 'Kein Wecker gestellt');
    });

    test('nicht unterstützt: Fehler mit Hinweis', () async {
      port = FakeAlarmPort(canList: false);
      integration = AlarmsIntegration(port);
      final o = await tool('alarms__list').execute({}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, contains('nicht ausgelesen'));
    });

    test('Port-Fehler', () async {
      port.failNext('listAlarms');
      final o = await tool('alarms__list').execute({}, ctx());
      expect(o.isError, isTrue);
    });

    test('Lesefehler (nur nächster): Fehler, nie „kein Wecker“', () async {
      port = FakeAlarmPort(onlyNext: true);
      integration = AlarmsIntegration(port);
      port.failNext('listAlarms');
      final o = await tool('alarms__list').execute({}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, isNot(contains('kein Wecker')));
      expect(o.text, isNot(contains('Kein Wecker')));
    });

    test('Bestätigungstext', () {
      expect(
        tool('alarms__list').describeForConfirmation({}),
        'Wecker auflisten',
      );
    });
  });

  test('AlarmInfo: Gleichheit und Text', () {
    final a = AlarmInfo(id: '1', hour: 7, minute: 5, label: 'x', days: {1});
    expect(a, AlarmInfo(id: '1', hour: 7, minute: 5, label: 'x', days: {1}));
    expect(
      a.hashCode,
      AlarmInfo(id: '1', hour: 7, minute: 5, label: 'x', days: {1}).hashCode,
    );
    expect(
      a,
      isNot(AlarmInfo(id: '1', hour: 7, minute: 5, label: 'x', days: {2})),
    );
    expect(a.toString(), contains('07:05'));
  });
}
