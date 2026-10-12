import 'package:test/test.dart';
import 'package:wendelin_integrations/src/common/time.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// One table row: events and query in wall time of [zone], expected slots
/// as `<Tag>. HH:MM–HH:MM` (start day).
final class _Case {
  const _Case(
    this.name, {
    required this.from,
    required this.to,
    this.events = const [],
    this.expected = const [],
    this.zone = 'Europe/Berlin',
    this.dayStart = '08:00',
    this.dayEnd = '20:00',
    this.minMinutes = 30,
    this.bufferMinutes = 0,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.maxResults,
    this.expectedMinutes,
  });

  final String name;
  final String from;
  final String to;
  final List<(String, String, {bool busy, bool allDay})> events;
  final List<String> expected;
  final String zone;
  final String dayStart;
  final String dayEnd;
  final int minMinutes;
  final int bufferMinutes;
  final Set<int> weekdays;
  final int? maxResults;
  final List<int>? expectedMinutes;
}

const _cases = <_Case>[
  _Case(
    'leerer Kalender: ganzes Tagesfenster',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    expected: ['14. 08:00–20:00'],
  ),
  _Case(
    'ein Termin teilt das Fenster',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 11:00–20:00'],
  ),
  _Case(
    'überlappende Termine werden verschmolzen',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T11:00', '2026-10-14T13:00', busy: true, allDay: false),
      ('2026-10-14T10:00', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 13:00–20:00'],
  ),
  _Case(
    'verschachtelte Termine',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T14:00', busy: true, allDay: false),
      ('2026-10-14T11:00', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 14:00–20:00'],
  ),
  _Case(
    'aneinandergrenzende Termine lassen keine Lücke',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
      ('2026-10-14T11:00', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 12:00–20:00'],
  ),
  _Case(
    'Lücke kürzer als Mindestdauer fällt weg',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
      ('2026-10-14T11:29', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 12:00–20:00'],
  ),
  _Case(
    'Lücke genau Mindestdauer bleibt',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
      ('2026-10-14T11:30', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00', '14. 11:00–11:30', '14. 12:00–20:00'],
  ),
  _Case(
    'Puffer vor und nach Terminen',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    bufferMinutes: 15,
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–09:45', '14. 11:15–20:00'],
  ),
  _Case(
    'Puffer schließt kleine Lücke',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    bufferMinutes: 10,
    minMinutes: 5,
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
      ('2026-10-14T11:20', '2026-10-14T12:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–09:50', '14. 12:10–20:00'],
  ),
  _Case(
    'Termine über die Fenstergrenzen',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T07:00', '2026-10-14T09:00', busy: true, allDay: false),
      ('2026-10-14T19:00', '2026-10-14T22:00', busy: true, allDay: false),
    ],
    expected: ['14. 09:00–19:00'],
  ),
  _Case(
    'Termin außerhalb des Fensters stört nicht',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T21:00', '2026-10-14T22:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–20:00'],
  ),
  _Case(
    'Suchbereich schneidet das Fenster (Grenzen)',
    from: '2026-10-14T12:00',
    to: '2026-10-14T15:00',
    expected: ['14. 12:00–15:00'],
  ),
  _Case(
    'Suchbereich beginnt mitten im Termin',
    from: '2026-10-14T10:30',
    to: '2026-10-14T13:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
    ],
    expected: ['14. 11:00–13:00'],
  ),
  _Case(
    'Suchbereich endet vor dem Fenster',
    from: '2026-10-14T00:00',
    to: '2026-10-14T08:00',
    expected: [],
  ),
  _Case(
    'ganztägiger belegter Termin blockiert den ganzen Tag',
    from: '2026-10-14T00:00',
    to: '2026-10-16T00:00',
    events: [('2026-10-14', '2026-10-15', busy: true, allDay: true)],
    expected: ['15. 08:00–20:00'],
  ),
  _Case(
    'ganztägiger freier Termin (Geburtstag) blockiert nicht',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [('2026-10-14', '2026-10-15', busy: false, allDay: true)],
    expected: ['14. 08:00–20:00'],
  ),
  _Case(
    'mehrtägig ganztägig (exklusives Ende)',
    from: '2026-10-14T00:00',
    to: '2026-10-17T00:00',
    events: [('2026-10-14', '2026-10-16', busy: true, allDay: true)],
    expected: ['16. 08:00–20:00'],
  ),
  _Case(
    'ganztägig in New York: lokaler Tag, nicht UTC-Tag',
    zone: 'America/New_York',
    from: '2026-10-14T00:00',
    to: '2026-10-16T00:00',
    events: [('2026-10-15', '2026-10-16', busy: true, allDay: true)],
    expected: ['14. 08:00–20:00'],
  ),
  _Case(
    'freier Termin mit Uhrzeit wird ignoriert',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: false, allDay: false),
    ],
    expected: ['14. 08:00–20:00'],
  ),
  _Case(
    'nur Werktage (Fr bis Mo)',
    from: '2026-10-16T00:00',
    to: '2026-10-20T00:00',
    weekdays: {1, 2, 3, 4, 5},
    expected: ['16. 08:00–20:00', '19. 08:00–20:00'],
  ),
  _Case(
    'Termin über Mitternacht',
    from: '2026-10-14T00:00',
    to: '2026-10-16T00:00',
    events: [
      ('2026-10-14T19:00', '2026-10-15T09:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–19:00', '15. 09:00–20:00'],
  ),
  _Case(
    'maxResults begrenzt',
    from: '2026-10-14T00:00',
    to: '2026-10-17T00:00',
    maxResults: 2,
    expected: ['14. 08:00–20:00', '15. 08:00–20:00'],
  ),
  _Case(
    'maxResults innerhalb eines Tages',
    from: '2026-10-14T00:00',
    to: '2026-10-15T00:00',
    maxResults: 1,
    events: [
      ('2026-10-14T10:00', '2026-10-14T11:00', busy: true, allDay: false),
    ],
    expected: ['14. 08:00–10:00'],
  ),
  _Case(
    'Fenster bis 24:00',
    from: '2026-10-14T00:00',
    to: '2026-10-16T00:00',
    dayStart: '22:00',
    dayEnd: '24:00',
    expected: ['14. 22:00–00:00', '15. 22:00–00:00'],
    expectedMinutes: [120, 120],
  ),
  _Case(
    'Sommerzeitbeginn: 00:00–06:00 sind nur 5 Stunden',
    from: '2026-03-29T00:00',
    to: '2026-03-30T00:00',
    dayStart: '00:00',
    dayEnd: '06:00',
    expected: ['29. 00:00–06:00'],
    expectedMinutes: [300],
  ),
  _Case(
    'Sommerzeitbeginn: Mindestdauer 6 h passt nicht mehr',
    from: '2026-03-29T00:00',
    to: '2026-03-30T00:00',
    dayStart: '00:00',
    dayEnd: '06:00',
    minMinutes: 360,
    expected: [],
  ),
  _Case(
    'Sommerzeitende: 00:00–06:00 sind 7 Stunden',
    from: '2026-10-25T00:00',
    to: '2026-10-26T00:00',
    dayStart: '00:00',
    dayEnd: '06:00',
    minMinutes: 420,
    expected: ['25. 00:00–06:00'],
    expectedMinutes: [420],
  ),
  _Case(
    'Sommerzeitbeginn: Termin 01:00–04:00 über den Sprung',
    from: '2026-03-29T00:00',
    to: '2026-03-30T00:00',
    dayStart: '00:00',
    dayEnd: '06:00',
    events: [
      ('2026-03-29T01:00', '2026-03-29T04:00', busy: true, allDay: false),
    ],
    expected: ['29. 00:00–01:00', '29. 04:00–06:00'],
    expectedMinutes: [60, 120],
  ),
  _Case(
    'Woche über den Sommerzeitwechsel: Fenster bleibt 08–20 Ortszeit',
    from: '2026-10-24T00:00',
    to: '2026-10-27T00:00',
    expected: ['24. 08:00–20:00', '25. 08:00–20:00', '26. 08:00–20:00'],
    expectedMinutes: [720, 720, 720],
  ),
];

void main() {
  for (final c in _cases) {
    test(c.name, () {
      final loc = timeZoneLocation(c.zone);
      DateTime at(String s) => IsoInput.parse(s, 't').instantIn(loc);
      var n = 0;
      final events = [
        for (final e in c.events)
          CalendarEvent(
            id: 'e${n++}',
            calendarId: 'c',
            title: 'T',
            start: e.allDay
                ? IsoInput.parse(e.$1, 't').date.utcMidnight
                : at(e.$1),
            end: e.allDay
                ? IsoInput.parse(e.$2, 't').date.utcMidnight
                : at(e.$2),
            allDay: e.allDay,
            busy: e.busy,
          ),
      ];
      final slots = findFreeSlots(
        FreeSlotQuery(
          range: TimeRange(at(c.from), at(c.to)),
          location: loc,
          minDuration: Duration(minutes: c.minMinutes),
          buffer: Duration(minutes: c.bufferMinutes),
          dayStartMinutes: parseClockTime(c.dayStart, 'x'),
          dayEndMinutes: parseClockTime(c.dayEnd, 'x'),
          weekdays: c.weekdays,
        ),
        events,
        maxResults: c.maxResults,
      );
      expect([
        for (final s in slots)
          '${LocalDate.of(s.start, loc).day}. '
              '${germanClock(s.start, loc)}–${germanClock(s.end, loc)}',
      ], c.expected);
      if (c.expectedMinutes != null) {
        expect([
          for (final s in slots) s.duration.inMinutes,
        ], c.expectedMinutes);
      }
    });
  }

  group('FreeSlotQuery prüft Parameter', () {
    final range = TimeRange(DateTime.utc(2026), DateTime.utc(2026, 1, 2));
    final loc = timeZoneLocation('UTC');
    test('Mindestdauer > 0', () {
      expect(
        () => FreeSlotQuery(
          range: range,
          location: loc,
          minDuration: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
    test('Puffer nicht negativ', () {
      expect(
        () => FreeSlotQuery(
          range: range,
          location: loc,
          buffer: const Duration(minutes: -1),
        ),
        throwsArgumentError,
      );
    });
    test('Fenster: Beginn vor Ende, innerhalb des Tages', () {
      expect(
        () => FreeSlotQuery(
          range: range,
          location: loc,
          dayStartMinutes: 600,
          dayEndMinutes: 600,
        ),
        throwsArgumentError,
      );
      expect(
        () => FreeSlotQuery(range: range, location: loc, dayEndMinutes: 1441),
        throwsArgumentError,
      );
      expect(
        () => FreeSlotQuery(range: range, location: loc, dayStartMinutes: -1),
        throwsArgumentError,
      );
    });
  });
}
