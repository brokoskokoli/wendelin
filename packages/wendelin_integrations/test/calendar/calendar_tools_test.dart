import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// UTC instant of a Berlin wall time in October 2026 (CEST, +02:00).
DateTime berlin(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour - 2, minute);

void main() {
  late FakeCalendarPort port;
  late CalendarIntegration integration;

  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());

  CalendarEvent event(
    String id,
    DateTime start,
    DateTime end, {
    String title = 'Tauchen',
    String calendarId = 'privat',
    bool allDay = false,
    bool recurring = false,
    String? location,
    String? description,
    List<String> attendees = const [],
  }) => CalendarEvent(
    id: id,
    calendarId: calendarId,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    recurring: recurring,
    location: location,
    description: description,
    attendees: attendees,
  );

  setUp(() {
    port = FakeCalendarPort(
      calendars: [
        const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
        const CalendarInfo(id: 'arbeit', name: 'Arbeit', writable: true),
        const CalendarInfo(id: 'feiertage', name: 'Feiertage', writable: false),
      ],
    );
    integration = CalendarIntegration(port);
  });

  group('Integration', () {
    test('Metadaten und Einrichtung', () async {
      expect(integration.id, 'calendar');
      expect(integration.displayName, 'Kalender');
      expect(integration.iconId, 'calendar');
      expect(integration.sensitive, isTrue);
      expect(integration.platforms, {AppPlatform.android, AppPlatform.ios});
      expect(await integration.checkAvailability(), Availability.yes);
      expect(integration.setup.single.kind, SetupStepKind.permission);
      expect((await integration.setupState()).complete, isTrue);
      port.permissionGranted = false;
      expect((await integration.setupState()).missingSteps, [
        CalendarIntegration.permissionStep,
      ]);
    });

    test('Tool-Namen und Risikostufen', () {
      expect(
        {for (final t in integration.tools) t.name: t.risk},
        {
          'calendar__list_calendars': RiskLevel.read,
          'calendar__list_events': RiskLevel.read,
          'calendar__find_free_slots': RiskLevel.read,
          'calendar__create_event': RiskLevel.write,
          'calendar__update_event': RiskLevel.write,
          'calendar__delete_event': RiskLevel.external,
        },
      );
    });
  });

  group('calendar__list_calendars', () {
    test('Erfolg: Ids, Namen, Schreibrecht, Standard', () async {
      final o = await run('calendar__list_calendars', {});
      expect(o.isError, isFalse);
      expect(json(o)['calendars'], [
        {'id': 'privat', 'name': 'Privat', 'writable': true, 'default': true},
        {'id': 'arbeit', 'name': 'Arbeit', 'writable': true},
        {'id': 'feiertage', 'name': 'Feiertage', 'writable': false},
      ]);
      expect(o.summary, '3 Kalender');
    });

    test('Port-Fehler: fehlende Berechtigung wird Fehler-Outcome', () async {
      port.permissionGranted = false;
      final o = await run('calendar__list_calendars', {});
      expect(o.isError, isTrue);
      expect(o.text, contains('Kein Zugriff'));
    });

    test('Bestätigungstext', () {
      expect(
        tool('calendar__list_calendars').describeForConfirmation({}),
        'Kalender auflisten',
      );
    });
  });

  group('calendar__list_events', () {
    setUp(() {
      port = FakeCalendarPort(
        calendars: [
          const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
          const CalendarInfo(id: 'arbeit', name: 'Arbeit', writable: true),
        ],
        events: [
          event(
            'b',
            berlin(15, 14),
            berlin(15, 15),
            title: 'Meeting',
            calendarId: 'arbeit',
            description: 'Agenda',
            attendees: ['anna@example.org'],
          ),
          event('a', berlin(15, 10), berlin(15, 11), location: 'Hafen'),
          event(
            'g',
            DateTime.utc(2026, 10, 15),
            DateTime.utc(2026, 10, 17),
            title: 'Urlaub',
            allDay: true,
          ),
          event(
            'y',
            DateTime.utc(2026, 10, 14),
            DateTime.utc(2026, 10, 15),
            title: 'Gestern ganztägig',
            allDay: true,
          ),
          event('x', berlin(16, 10), berlin(16, 11), title: 'Morgen'),
        ],
      );
      integration = CalendarIntegration(port);
    });

    test(
      'Erfolg: sortiert, gekürzt, Ortszeit mit Offset, Kalendername',
      () async {
        final o = await run('calendar__list_events', {
          'start': '2026-10-15T00:00',
          'end': '2026-10-15',
        });
        expect(o.isError, isFalse);
        final data = json(o);
        expect(data['time_zone'], 'Europe/Berlin');
        expect(data['events'], [
          {
            'id': 'g',
            'title': 'Urlaub',
            'all_day': true,
            'start': '2026-10-15',
            'end': '2026-10-16',
            'calendar': 'Privat',
          },
          {
            'id': 'a',
            'title': 'Tauchen',
            'start': '2026-10-15T10:00:00+02:00',
            'end': '2026-10-15T11:00:00+02:00',
            'location': 'Hafen',
            'calendar': 'Privat',
          },
          {
            'id': 'b',
            'title': 'Meeting',
            'start': '2026-10-15T14:00:00+02:00',
            'end': '2026-10-15T15:00:00+02:00',
            'calendar': 'Arbeit',
          },
        ]);
        expect(o.text, isNot(contains('anna@')));
        expect(o.text, isNot(contains('Agenda')));
        expect(o.summary, '3 Termine');
      },
    );

    test('include_details liefert Notizen und Teilnehmer', () async {
      final o = await run('calendar__list_events', {
        'start': '2026-10-15T14:00',
        'end': '2026-10-15T14:30',
        'include_details': true,
      });
      final e = (json(o)['events']! as List)
          .whereType<Map<String, Object?>>()
          .singleWhere((e) => e['id'] == 'b');
      expect(e['description'], 'Agenda');
      expect(e['attendees'], ['anna@example.org']);
      expect(o.summary, '2 Termine');
    });

    test('calendar_ids filtert', () async {
      final o = await run('calendar__list_events', {
        'start': '2026-10-15T00:00',
        'end': '2026-10-16T00:00',
        'calendar_ids': ['arbeit'],
      });
      expect(
        [for (final e in json(o)['events']! as List) (e as Map)['id']],
        ['b'],
      );
      expect(o.summary, '1 Termin');
    });

    test('keine Termine', () async {
      final o = await run('calendar__list_events', {
        'start': '2026-11-01T00:00',
        'end': '2026-11-02T00:00',
      });
      expect(json(o)['events'], isEmpty);
      expect(o.summary, 'Keine Termine');
    });

    test('mehr als 50 Termine werden gekürzt und markiert', () async {
      for (var i = 0; i < 55; i++) {
        await port.createEvent(
          CalendarEventDraft(
            calendarId: 'privat',
            title: 'T$i',
            start: DateTime.utc(2026, 11, 2, 8, i),
            end: DateTime.utc(2026, 11, 2, 9, i),
          ),
        );
      }
      final o = await run('calendar__list_events', {
        'start': '2026-11-02',
        'end': '2026-11-02',
      });
      final data = json(o);
      expect(data['events'], hasLength(ListEventsTool.maxEvents));
      expect(data['truncated'], contains('5 weitere'));
      expect(o.summary, '55 Termine');
    });

    test('Port-Fehler', () async {
      port.failNext('listEvents');
      final o = await run('calendar__list_events', {
        'start': '2026-10-15T00:00',
        'end': '2026-10-16T00:00',
      });
      expect(o.isError, isTrue);
      expect(o.text, 'Simulierter Fehler');
    });

    for (final (label, args, message) in [
      ('end fehlt', {'start': '2026-10-15T00:00'}, '„end“ fehlt'),
      ('start fehlt', {'end': '2026-10-15T00:00'}, '„start“ fehlt'),
      (
        'Ende vor Beginn',
        {'start': '2026-10-15T10:00', 'end': '2026-10-15T09:00'},
        'nach „start“',
      ),
      (
        'kein ISO-Datum',
        {'start': 'morgen', 'end': '2026-10-15T09:00'},
        'kein gültiges Datum',
      ),
      (
        'Zeitraum zu lang',
        {'start': '2026-01-01', 'end': '2026-06-01'},
        'zu lang',
      ),
      (
        'calendar_ids kein Array',
        {'start': '2026-10-15', 'end': '2026-10-16', 'calendar_ids': 'privat'},
        'Liste',
      ),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await run('calendar__list_events', args);
        expect(o.isError, isTrue);
        expect(o.text, contains('Ungültige Argumente'));
        expect(o.text, contains(message));
        expect(port.methodCalls, isNot(contains('listEvents')));
      });
    }

    test('unbekannte Gerätezeitzone wird Fehler-Outcome', () async {
      final o = await tool('calendar__list_events').execute({
        'start': '2026-10-15',
        'end': '2026-10-16',
      }, ctxAt(DateTime.utc(2026, 10, 13), timeZone: 'Nirgendwo/Stadt'));
      expect(o.isError, isTrue);
      expect(o.text, contains('Unbekannte Zeitzone'));
    });

    test(
      'ganztägig in Los Angeles: lokaler Tag zählt, nicht der UTC-Tag',
      () async {
        final la = ctxAt(
          DateTime.utc(2026, 10, 13),
          timeZone: 'America/Los_Angeles',
        );
        final o = await tool(
          'calendar__list_events',
        ).execute({'start': '2026-10-16T18:00', 'end': '2026-10-16T20:00'}, la);
        expect(
          [for (final e in json(o)['events']! as List) (e as Map)['id']],
          ['g'],
        );
        final early = await tool(
          'calendar__list_events',
        ).execute({'start': '2026-10-13T18:00', 'end': '2026-10-13T20:00'}, la);
        expect(json(early)['events'], isEmpty);
      },
    );

    test('andere Gerätezeitzone verschiebt Offsets', () async {
      final o = await tool('calendar__list_events').execute({
        'start': '2026-10-15T00:00',
        'end': '2026-10-15T12:00',
      }, ctxAt(DateTime.utc(2026, 10, 13), timeZone: 'Europe/London'));
      final events = json(o)['events']! as List;
      expect(
        events
            .whereType<Map<String, Object?>>()
            .where((e) => e['id'] == 'a')
            .single['start'],
        '2026-10-15T09:00:00+01:00',
      );
    });
  });

  group('calendar__find_free_slots', () {
    setUp(() {
      port = FakeCalendarPort(
        events: [
          event('a', berlin(15, 10), berlin(15, 11)),
          CalendarEvent(
            id: 'f',
            calendarId: 'privat',
            title: 'frei',
            start: berlin(15, 12),
            end: berlin(15, 13),
            busy: false,
          ),
          event('w', berlin(15, 15), berlin(15, 16), calendarId: 'arbeit'),
        ],
        calendars: [
          const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
          const CalendarInfo(id: 'arbeit', name: 'Arbeit', writable: true),
        ],
      );
      integration = CalendarIntegration(port);
    });

    test('Erfolg mit Standardfenster 08–20', () async {
      final o = await run('calendar__find_free_slots', {
        'start': '2026-10-15T00:00',
        'end': '2026-10-15',
      });
      expect(o.isError, isFalse);
      expect(json(o)['slots'], [
        {
          'start': '2026-10-15T08:00:00+02:00',
          'end': '2026-10-15T10:00:00+02:00',
          'minutes': 120,
        },
        {
          'start': '2026-10-15T11:00:00+02:00',
          'end': '2026-10-15T15:00:00+02:00',
          'minutes': 240,
        },
        {
          'start': '2026-10-15T16:00:00+02:00',
          'end': '2026-10-15T20:00:00+02:00',
          'minutes': 240,
        },
      ]);
      expect(o.summary, '3 freie Zeiten, ab Do 15.10. 08:00');
    });

    test(
      'Parameter: Fenster, Mindestdauer, Puffer, Kalender, max_results',
      () async {
        final o = await run('calendar__find_free_slots', {
          'start': '2026-10-15T00:00',
          'end': '2026-10-17T00:00',
          'day_start': '09:00',
          'day_end': '17:00',
          'min_duration_minutes': 90,
          'buffer_minutes': 15,
          'calendar_ids': ['privat'],
          'weekdays': [4],
          'max_results': 5,
        });
        expect(
          [
            for (final s in json(o)['slots']! as List)
              '${(s as Map)['start']}/${s['end']}',
          ],
          ['2026-10-15T11:15:00+02:00/2026-10-15T17:00:00+02:00'],
        );
      },
    );

    test(
      'ganztägiger Termin blockiert den lokalen Tag auch fern von UTC',
      () async {
        await port.createEvent(
          CalendarEventDraft(
            calendarId: 'privat',
            title: 'Urlaub',
            start: DateTime.utc(2026, 10, 20),
            end: DateTime.utc(2026, 10, 21),
            allDay: true,
          ),
        );
        final o = await tool('calendar__find_free_slots').execute({
          'start': '2026-10-20T18:00',
          'end': '2026-10-20T20:00',
        }, ctxAt(DateTime.utc(2026, 10, 13), timeZone: 'America/Los_Angeles'));
        expect(json(o)['slots'], isEmpty);
      },
    );

    test('keine freie Zeit', () async {
      final o = await run('calendar__find_free_slots', {
        'start': '2026-10-15T10:00',
        'end': '2026-10-15T11:00',
      });
      expect(json(o)['slots'], isEmpty);
      expect(o.summary, 'Keine freie Zeit gefunden');
    });

    test('Port-Fehler', () async {
      port.failNext(
        'listEvents',
        const PortException(PortErrorKind.permissionDenied, 'Kein Zugriff'),
      );
      final o = await run('calendar__find_free_slots', {
        'start': '2026-10-15',
        'end': '2026-10-16',
      });
      expect(o.isError, isTrue);
      expect(o.text, 'Kein Zugriff');
    });

    for (final (label, extra, message) in [
      (
        'Fensterende vor Beginn',
        {'day_start': '18:00', 'day_end': '09:00'},
        '„day_end“',
      ),
      ('Uhrzeit ungültig', {'day_start': '9 Uhr'}, '„day_start“'),
      (
        'Wochentag 8',
        {
          'weekdays': [8],
        },
        '„weekdays[0]“',
      ),
      ('Mindestdauer 0', {'min_duration_minutes': 0}, '„min_duration_minutes“'),
      ('Puffer negativ', {'buffer_minutes': -5}, '„buffer_minutes“'),
      ('max_results 0', {'max_results': 0}, '„max_results“'),
      ('Zeitraum zu lang', {'end': '2026-12-31'}, 'zu lang'),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await run('calendar__find_free_slots', {
          'start': '2026-10-15',
          'end': '2026-10-16',
          ...extra,
        });
        expect(o.isError, isTrue);
        expect(o.text, contains(message));
      });
    }

    test('Bestätigungstext', () {
      expect(
        tool('calendar__find_free_slots').describeForConfirmation({}),
        'Freie Zeiten suchen',
      );
    });
  });

  group('calendar__create_event', () {
    test('Erfolg: Standardkalender, 1 Stunde, Undo löscht', () async {
      final o = await run('calendar__create_event', {
        'title': 'Tauchen',
        'start': '2026-10-15T10:00',
      });
      expect(o.isError, isFalse);
      final created = json(o)['created']! as Map;
      expect(created['start'], '2026-10-15T10:00:00+02:00');
      expect(created['end'], '2026-10-15T11:00:00+02:00');
      expect(created['calendar'], 'Privat');
      expect(o.summary, 'Termin angelegt: Tauchen, Do 15.10. 10:00');
      final stored = port.events.single;
      expect(stored.start, berlin(15, 10));
      expect(stored.timeZone, 'Europe/Berlin');
      expect(stored.calendarId, 'privat');
      expect(o.undo!.label, 'Termin entfernen');
      await o.undo!();
      expect(port.events, isEmpty);
    });

    test('alle Felder, eigener Kalender, Ende angegeben', () async {
      final o = await run('calendar__create_event', {
        'title': 'Review',
        'start': '2026-10-15T14:00',
        'end': '2026-10-15T14:45',
        'location': 'Büro',
        'description': 'Unterlagen',
        'calendar_id': 'arbeit',
      });
      expect(o.isError, isFalse);
      final e = port.events.single;
      expect(e.calendarId, 'arbeit');
      expect(e.end.difference(e.start), const Duration(minutes: 45));
      expect(e.location, 'Büro');
      expect(e.description, 'Unterlagen');
    });

    test('andere Zeitzone, wenn der Nutzer sie nennt', () async {
      final o = await run('calendar__create_event', {
        'title': 'Call Lissabon',
        'start': '2026-10-15T10:00',
        'time_zone': 'Europe/Lisbon',
      });
      expect(o.isError, isFalse);
      expect(port.events.single.start, DateTime.utc(2026, 10, 15, 9));
      expect(port.events.single.timeZone, 'Europe/Lisbon');
      expect(
        (json(o)['created']! as Map)['start'],
        '2026-10-15T10:00:00+01:00',
      );
    });

    test('Offset in der Zeitangabe gilt', () async {
      await run('calendar__create_event', {
        'title': 'UTC',
        'start': '2026-10-15T10:00Z',
      });
      expect(port.events.single.start, DateTime.utc(2026, 10, 15, 10));
    });

    test('ganztägig, mehrere Tage (Ende = letzter Tag)', () async {
      final o = await run('calendar__create_event', {
        'title': 'Urlaub',
        'start': '2026-10-15',
        'end': '2026-10-17',
        'all_day': true,
      });
      final e = port.events.single;
      expect(e.allDay, isTrue);
      expect(e.start, DateTime.utc(2026, 10, 15));
      expect(e.end, DateTime.utc(2026, 10, 18));
      expect(e.timeZone, 'UTC');
      expect(
        o.summary,
        'Termin angelegt: Urlaub, Do 15.10.–Sa 17.10. (ganztägig)',
      );
      expect((json(o)['created']! as Map)['end'], '2026-10-17');
    });

    test('ganztägig ohne Ende: ein Tag', () async {
      await run('calendar__create_event', {
        'title': 'Geburtstag',
        'start': '2026-10-15T09:00',
        'all_day': true,
      });
      expect(port.events.single.end, DateTime.utc(2026, 10, 16));
    });

    test('ohne Standardkalender: erster beschreibbarer', () async {
      port.defaultId = null;
      port.calendars.insert(
        0,
        const CalendarInfo(id: 'abo', name: 'Abo', writable: false),
      );
      await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
      });
      expect(port.events.single.calendarId, 'privat');
    });

    test('Standardkalender schreibgeschützt: erster beschreibbarer', () async {
      port.defaultId = 'feiertage';
      await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
      });
      expect(port.events.single.calendarId, 'privat');
    });

    test('kein beschreibbarer Kalender', () async {
      port.calendars
        ..clear()
        ..add(
          const CalendarInfo(
            id: 'feiertage',
            name: 'Feiertage',
            writable: false,
          ),
        );
      final o = await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('Kein beschreibbarer Kalender'));
    });

    test('schreibgeschützter Kalender', () async {
      final o = await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
        'calendar_id': 'feiertage',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('schreibgeschützt'));
      expect(port.events, isEmpty);
    });

    test('unbekannter Kalender', () async {
      final o = await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
        'calendar_id': 'gibtsnicht',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('gibt es nicht'));
    });

    test('Port-Fehler beim Anlegen', () async {
      port.failNext('createEvent');
      final o = await run('calendar__create_event', {
        'title': 'X',
        'start': '2026-10-15T10:00',
      });
      expect(o.isError, isTrue);
      expect(o.undo, isNull);
    });

    for (final (label, args, message) in [
      ('Titel fehlt', {'start': '2026-10-15T10:00'}, '„title“ fehlt'),
      (
        'Titel leer',
        {'title': ' ', 'start': '2026-10-15T10:00'},
        '„title“ fehlt',
      ),
      ('Start fehlt', {'title': 'X'}, '„start“'),
      (
        'Start ohne Uhrzeit',
        {'title': 'X', 'start': '2026-10-15'},
        'braucht eine Uhrzeit',
      ),
      (
        'Ende ohne Uhrzeit',
        {'title': 'X', 'start': '2026-10-15T10:00', 'end': '2026-10-15'},
        'braucht eine Uhrzeit',
      ),
      (
        'Ende vor Beginn',
        {'title': 'X', 'start': '2026-10-15T10:00', 'end': '2026-10-15T09:00'},
        'nach „start“',
      ),
      (
        'ganztägig Ende vor Beginn',
        {
          'title': 'X',
          'start': '2026-10-15',
          'end': '2026-10-14',
          'all_day': true,
        },
        'liegt vor',
      ),
      (
        'ganztägig ohne Start',
        {'title': 'X', 'all_day': true},
        '„start“ fehlt',
      ),
      (
        'unbekannte Zeitzone',
        {'title': 'X', 'start': '2026-10-15T10:00', 'time_zone': 'Mond/Basis'},
        'Unbekannte Zeitzone',
      ),
      (
        'all_day kein Bool',
        {'title': 'X', 'start': '2026-10-15T10:00', 'all_day': 'ja'},
        'true oder false',
      ),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await run('calendar__create_event', args);
        expect(o.isError, isTrue);
        expect(o.text, contains(message));
        expect(port.events, isEmpty);
      });
    }

    test('Bestätigungstext deutsch formatiert', () {
      final t = tool('calendar__create_event');
      // Ohne Ausführung ist die Gerätezone unbekannt: Wandzeit gilt direkt.
      expect(
        t.describeForConfirmation({
          'title': 'Tauchen',
          'start': '2026-10-15T10:00',
          'end': '2026-10-15T11:00',
        }),
        'Termin ‚Tauchen‘ Do 15.10. 10:00–11:00 anlegen',
      );
      expect(
        t.describeForConfirmation({
          'title': 'Urlaub',
          'start': '2026-10-15',
          'all_day': true,
        }),
        'Termin ‚Urlaub‘ Do 15.10. (ganztägig) anlegen',
      );
      expect(
        t.describeForConfirmation({
          'title': 'Lissabon',
          'start': '2026-10-15T10:00',
          'time_zone': 'Europe/Lisbon',
        }),
        'Termin ‚Lissabon‘ Do 15.10. 10:00–11:00 anlegen',
      );
      expect(t.describeForConfirmation({'start': 'x'}), 'Termin anlegen');
    });

    test('Bestätigungstext rechnet Offsets in die Gerätezone um', () {
      final i = CalendarIntegration(
        port,
        deviceTimeZone: () => 'Europe/Berlin',
      );
      final t = i.tools.singleWhere((t) => t.name == 'calendar__create_event');
      expect(
        t.describeForConfirmation({'title': 'T', 'start': '2026-10-15T08:00Z'}),
        'Termin ‚T‘ Do 15.10. 10:00–11:00 anlegen',
      );
    });
  });

  group('calendar__update_event', () {
    setUp(() {
      port = FakeCalendarPort(
        events: [
          event(
            'a',
            berlin(15, 10),
            berlin(15, 11),
            location: 'Hafen',
            description: 'alt',
          ),
          event(
            'u',
            DateTime.utc(2026, 10, 20),
            DateTime.utc(2026, 10, 23),
            title: 'Urlaub',
            allDay: true,
          ),
          event(
            's',
            berlin(16, 18),
            berlin(16, 19),
            title: 'Training',
            recurring: true,
            location: 'Halle',
          ),
        ],
      );
      integration = CalendarIntegration(port);
    });

    CalendarEvent stored(String id) =>
        port.events.singleWhere((e) => e.id == id);

    test(
      'Serientermin: Zeitänderung wird abgelehnt, nichts geändert',
      () async {
        for (final args in [
          {'start': '2026-10-16T19:00'},
          {'end': '2026-10-16T20:00'},
          {'all_day': true},
        ]) {
          final o = await run('calendar__update_event', {
            'event_id': 's',
            ...args,
          });
          expect(o.isError, isTrue, reason: '$args');
          expect(o.text, contains('Serientermin'));
          expect(o.text, contains('Kalender-App'));
        }
        expect(stored('s').start, berlin(16, 18));
        expect(port.methodCalls, isNot(contains('updateEvent')));
      },
    );

    test('Serientermin: Titel/Ort ändern mit Hinweis „ganze Serie“', () async {
      final o = await run('calendar__update_event', {
        'event_id': 's',
        'title': 'Lauftraining',
        'location': 'Park',
      });
      expect(o.isError, isFalse);
      expect(stored('s').title, 'Lauftraining');
      expect(stored('s').location, 'Park');
      expect(stored('s').start, berlin(16, 18));
      expect(json(o)['scope'], 'ganze Serie');
      expect(o.summary, endsWith('(ganze Serie)'));
      expect(
        await tool('calendar__update_event')
            .confirmationText({'event_id': 's', 'title': 'X'}, ctx()),
        'Termin ‚Lauftraining‘ ändern (ganze Serie)',
      );
    });

    test('Zeitzone wird wie beim Anlegen gesetzt', () async {
      await run('calendar__update_event', {
        'event_id': 'a',
        'start': '2026-10-15T10:00',
        'time_zone': 'Europe/Lisbon',
      });
      expect(stored('a').timeZone, 'Europe/Lisbon');
      expect(stored('a').start, DateTime.utc(2026, 10, 15, 9));
      await run('calendar__update_event', {
        'event_id': 'a',
        'start': '2026-10-15T10:00',
      });
      expect(stored('a').timeZone, 'Europe/Berlin');
      await run('calendar__update_event', {
        'event_id': 'a',
        'title': 'Nur Titel',
      });
      expect(stored('a').timeZone, 'Europe/Berlin');
      await run('calendar__update_event', {'event_id': 'a', 'all_day': true});
      expect(stored('a').timeZone, 'UTC');
    });

    test('nur Titel: Zeiten bleiben; Undo stellt alten Zustand her', () async {
      final before = stored('a');
      final o = await run('calendar__update_event', {
        'event_id': 'a',
        'title': 'Schnorcheln',
      });
      expect(o.isError, isFalse);
      expect(stored('a').title, 'Schnorcheln');
      expect(stored('a').start, before.start);
      expect(o.summary, 'Termin geändert: Schnorcheln, Do 15.10. 10:00–11:00');
      expect(o.undo!.label, 'Änderung rückgängig');
      await o.undo!();
      expect(stored('a'), before);
    });

    test('nur Start: Dauer bleibt', () async {
      await run('calendar__update_event', {
        'event_id': 'a',
        'end': '2026-10-15T11:30',
      });
      await run('calendar__update_event', {
        'event_id': 'a',
        'start': '2026-10-15T13:30',
      });
      expect(stored('a').start, berlin(15, 13, 30));
      expect(stored('a').end, berlin(15, 15));
    });

    test('nur Ende', () async {
      await run('calendar__update_event', {
        'event_id': 'a',
        'end': '2026-10-15T12:00',
      });
      expect(stored('a').start, berlin(15, 10));
      expect(stored('a').end, berlin(15, 12));
    });

    test('Ort und Notiz leeren, Ort ändern', () async {
      await run('calendar__update_event', {
        'event_id': 'a',
        'location': '',
        'description': '',
      });
      expect(stored('a').location, isNull);
      expect(stored('a').description, isNull);
      await run('calendar__update_event', {
        'event_id': 'a',
        'location': 'Bucht',
      });
      expect(stored('a').location, 'Bucht');
      expect(stored('a').description, isNull);
    });

    test('ganztägig verschieben behält Anzahl Tage', () async {
      await run('calendar__update_event', {
        'event_id': 'u',
        'start': '2026-10-27',
      });
      expect(stored('u').start, DateTime.utc(2026, 10, 27));
      expect(stored('u').end, DateTime.utc(2026, 10, 30));
    });

    test('Termin mit Uhrzeit wird ganztägig (lokaler Tag)', () async {
      await run('calendar__update_event', {'event_id': 'a', 'all_day': true});
      expect(stored('a').allDay, isTrue);
      expect(stored('a').start, DateTime.utc(2026, 10, 15));
      expect(stored('a').end, DateTime.utc(2026, 10, 16));
    });

    test('ganztägig zu Uhrzeit braucht Start mit Uhrzeit', () async {
      final o = await run('calendar__update_event', {
        'event_id': 'u',
        'all_day': false,
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('„start“ mit Uhrzeit fehlt'));
      final ok = await run('calendar__update_event', {
        'event_id': 'u',
        'all_day': false,
        'start': '2026-10-20T09:00',
      });
      expect(ok.isError, isFalse);
      expect(stored('u').end, berlin(20, 10));
    });

    test('unbekannte Id', () async {
      final o = await run('calendar__update_event', {
        'event_id': 'nix',
        'title': 'X',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('gibt es nicht'));
    });

    test('Port-Fehler beim Ändern', () async {
      port.failNext('updateEvent');
      final o = await run('calendar__update_event', {
        'event_id': 'a',
        'title': 'X',
      });
      expect(o.isError, isTrue);
      expect(stored('a').title, 'Tauchen');
    });

    test('ungültige Argumente', () async {
      for (final args in [
        <String, Object?>{},
        {'event_id': 'a', 'start': 'bald'},
        {'event_id': 'a', 'end': '2026-10-15T09:00'},
        {'event_id': 7},
      ]) {
        final o = await run('calendar__update_event', args);
        expect(o.isError, isTrue, reason: '$args');
        expect(o.text, contains('Ungültige Argumente'), reason: '$args');
      }
      expect(stored('a').start, berlin(15, 10));
    });

    test('Bestätigungstext schlägt den Titel live nach', () async {
      final t = tool('calendar__update_event');
      expect(
        t.describeForConfirmation({
          'event_id': 'a',
          'start': '2026-10-15T12:00',
        }),
        'Termin (ID a) ändern: Do 15.10. 12:00–13:00',
      );
      expect(
        await t.confirmationText({
          'event_id': 'a',
          'start': '2026-10-15T12:00',
        }, ctx()),
        'Termin ‚Tauchen‘ ändern: Do 15.10. 12:00–13:00',
      );
      expect(
        await t.confirmationText({'event_id': 'a'}, ctx()),
        'Termin ‚Tauchen‘ ändern',
      );
      expect(
        await t.confirmationText({'event_id': 'fehlt'}, ctx()),
        'Termin (ID fehlt) ändern',
      );
      expect(await t.confirmationText({}, ctx()), 'Termin ändern');
      expect(t.describeForConfirmation({}), 'Termin ändern');
      expect(port.methodCalls, isNot(contains('updateEvent')));
    });
  });

  group('calendar__delete_event', () {
    setUp(() {
      port = FakeCalendarPort(
        events: [
          event('a', berlin(15, 10), berlin(15, 11)),
          event(
            'r',
            berlin(16, 18),
            berlin(16, 19),
            title: 'Training',
            recurring: true,
          ),
        ],
      );
      integration = CalendarIntegration(port);
    });

    test('Erfolg', () async {
      final o = await run('calendar__delete_event', {'event_id': 'a'});
      expect(o.isError, isFalse);
      expect(json(o), {'deleted': 'a', 'title': 'Tauchen'});
      expect(o.summary, 'Termin gelöscht: Tauchen, Do 15.10. 10:00–11:00');
      expect(port.events.map((e) => e.id), ['r']);
    });

    test('Serie: Ergebnis und Beschreibung sagen „ganze Serie“', () async {
      expect(
        tool('calendar__delete_event').description,
        contains('WHOLE series'),
      );
      final o = await run('calendar__delete_event', {'event_id': 'r'});
      expect(json(o), {
        'deleted': 'r',
        'title': 'Training',
        'scope': 'ganze Serie',
      });
      expect(
        o.summary,
        'Termin gelöscht: Training, Fr 16.10. 18:00–19:00 (ganze Serie)',
      );
    });

    test('unbekannte Id', () async {
      final o = await run('calendar__delete_event', {'event_id': 'nix'});
      expect(o.isError, isTrue);
      expect(port.methodCalls, isNot(contains('deleteEvent')));
    });

    test('Port-Fehler beim Löschen', () async {
      port.failNext('deleteEvent');
      final o = await run('calendar__delete_event', {'event_id': 'a'});
      expect(o.isError, isTrue);
      expect(port.events, hasLength(2));
    });

    test('ungültige Argumente', () async {
      final o = await run('calendar__delete_event', {});
      expect(o.isError, isTrue);
      expect(o.text, contains('„event_id“ fehlt'));
    });

    test(
      'Bestätigungstext: „Termin ‚Tauchen‘ Do 15.10. 10:00–11:00 löschen“',
      () async {
        final t = tool('calendar__delete_event');
        expect(
          t.describeForConfirmation({'event_id': 'a'}),
          'Termin (ID a) löschen',
        );
        expect(
          await t.confirmationText({'event_id': 'a'}, ctx()),
          'Termin ‚Tauchen‘ Do 15.10. 10:00–11:00 löschen',
        );
        expect(
          await t.confirmationText({'event_id': 'r'}, ctx()),
          'Termin ‚Training‘ Fr 16.10. 18:00–19:00 löschen (ganze Serie)',
        );
        expect(await t.confirmationText({}, ctx()), 'Termin löschen');
        expect(
          await t.confirmationText({'event_id': 'weg'}, ctx()),
          'Termin (ID weg) löschen',
        );
        expect(port.methodCalls, isNot(contains('deleteEvent')));
        expect(port.events, hasLength(2));
      },
    );

    test('Bestätigungstext in der Gerätezone aus dem Kontext', () async {
      final london = ctxAt(
        DateTime.utc(2026, 10, 13, 12),
        timeZone: 'Europe/London',
      );
      expect(
        await tool('calendar__delete_event')
            .confirmationText({'event_id': 'a'}, london),
        'Termin ‚Tauchen‘ Do 15.10. 09:00–10:00 löschen',
      );
      expect(
        await tool('calendar__update_event').confirmationText({
          'event_id': 'a',
          'start': '2026-10-15T08:00Z',
        }, london),
        'Termin ‚Tauchen‘ ändern: Do 15.10. 09:00–10:00',
      );
      expect(
        await tool('calendar__update_event').confirmationText({
          'event_id': 'a',
          'start': '2026-10-15T08:00Z',
        }, ctx()),
        'Termin ‚Tauchen‘ ändern: Do 15.10. 10:00–11:00',
      );
    });

    test('Bestätigungstext: Port-Fehler → Text nur mit Id', () async {
      port.failNext('getEvent');
      expect(
        await tool('calendar__delete_event')
            .confirmationText({'event_id': 'a'}, ctx()),
        'Termin (ID a) löschen',
      );
    });
  });

  test('describeZone fällt bei ungültiger Gerätezone auf UTC zurück', () {
    final env = CalendarToolEnv(port, deviceTimeZone: () => 'Kaputt/Zone');
    expect(env.describeZone, timeZoneLocation('UTC'));
  });
}
