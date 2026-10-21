import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late CalendarIntegration integration;

  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());

  setUp(() {
    integration = CalendarIntegration(
      FakeCalendarPort(
        calendars: [
          const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
          const CalendarInfo(id: 'arbeit', name: 'Arbeit', writable: true),
          const CalendarInfo(
            id: 'feiertage',
            name: 'Feiertage',
            writable: false,
          ),
        ],
      ),
    );
  });

  group('feste Bestätigung', () {
    test('create_event: Ortszeit des Termins im Satz', () async {
      final t = tool('calendar__create_event');
      expectFixed(
        await run('calendar__create_event', {
          'title': 'Tauchen',
          'start': '2026-10-15T10:00',
        }),
        t,
        'event.created',
        de: 'Der Termin „Tauchen“ ist eingetragen: Do. 15.10., 10:00 Uhr.',
      );
      expectFixed(
        await run('calendar__create_event', {
          'title': 'Call Lissabon',
          'start': '2026-10-15T10:00',
          'time_zone': 'Europe/Lisbon',
        }),
        t,
        'event.created',
        de: 'Der Termin „Call Lissabon“ ist eingetragen: Do. 15.10., 10:00 Uhr.',
      );
    });

    test('create_event: ganztägig → Modell formuliert', () async {
      final o = await run('calendar__create_event', {
        'title': 'Urlaub',
        'start': '2026-10-15',
        'all_day': true,
      });
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('create_event: Fehler → kein Satz', () async {
      final o = await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
        'calendar_id': 'feiertage',
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });
  });
}
