import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 15, 8);
  final t1 = DateTime.utc(2026, 10, 15, 9);

  test('TimeRange: UTC, Dauer, Überlappung halboffen, Gleichheit', () {
    final r = TimeRange(t0.toLocal(), t1);
    expect(r.start.isUtc, isTrue);
    expect(r.duration, const Duration(hours: 1));
    expect(
      r.overlaps(TimeRange(t1, t1.add(const Duration(hours: 1)))),
      isFalse,
    );
    expect(
      r.overlaps(TimeRange(t0.subtract(const Duration(hours: 1)), t0)),
      isFalse,
    );
    expect(
      r.overlaps(TimeRange(t0.add(const Duration(minutes: 59)), t1)),
      isTrue,
    );
    expect(r, TimeRange(t0, t1));
    expect(r.hashCode, TimeRange(t0, t1).hashCode);
    expect(r.toString(), contains('2026-10-15T08:00'));
    expect(() => TimeRange(t1, t0), throwsArgumentError);
  });

  test('CalendarInfo und Draft: Gleichheit', () {
    const a = CalendarInfo(
      id: 'a',
      name: 'A',
      writable: true,
      accountName: 'x',
    );
    expect(
      a,
      const CalendarInfo(id: 'a', name: 'A', writable: true, accountName: 'x'),
    );
    expect(
      a.hashCode,
      const CalendarInfo(
        id: 'a',
        name: 'A',
        writable: true,
        accountName: 'x',
      ).hashCode,
    );
    expect(
      a,
      isNot(
        const CalendarInfo(
          id: 'a',
          name: 'A',
          writable: false,
          accountName: 'x',
        ),
      ),
    );
    expect(a.toString(), contains('writable: true'));
    final d = CalendarEventDraft(
      calendarId: 'a',
      title: 'T',
      start: t0,
      end: t1,
      location: 'L',
    );
    expect(
      d,
      CalendarEventDraft(
        calendarId: 'a',
        title: 'T',
        start: t0,
        end: t1,
        location: 'L',
      ),
    );
    expect(
      d.hashCode,
      CalendarEventDraft(
        calendarId: 'a',
        title: 'T',
        start: t0,
        end: t1,
        location: 'L',
      ).hashCode,
    );
    expect(
      d,
      isNot(
        CalendarEventDraft(calendarId: 'a', title: 'T', start: t0, end: t1),
      ),
    );
  });

  test('CalendarEvent: fromDraft, copyWith (inkl. Leeren), Gleichheit', () {
    final e = CalendarEvent.fromDraft(
      'id1',
      CalendarEventDraft(
        calendarId: 'a',
        title: 'T',
        start: t0,
        end: t1,
        location: 'L',
        description: 'D',
        timeZone: 'Europe/Berlin',
      ),
    );
    expect(e.id, 'id1');
    expect(e.busy, isTrue);
    expect(e.range, TimeRange(t0, t1));
    expect(e.copyWith(), e);
    expect(e.copyWith().hashCode, e.hashCode);
    final c = e.copyWith(title: 'U', location: null, description: null);
    expect(c.title, 'U');
    expect(c.location, isNull);
    expect(c.description, isNull);
    expect(c.timeZone, 'Europe/Berlin');
    expect(e.copyWith(location: 'M').location, 'M');
    expect(e, isNot(c));
    expect(
      CalendarEvent(
        id: 'x',
        calendarId: 'a',
        title: 'T',
        start: t0,
        end: t1,
        attendees: ['a'],
      ),
      isNot(
        CalendarEvent(
          id: 'x',
          calendarId: 'a',
          title: 'T',
          start: t0,
          end: t1,
          attendees: ['b'],
        ),
      ),
    );
    expect(e.toString(), contains('T'));
    expect(e.copyWith(allDay: true).toString(), contains('ganztägig'));
    expect(() => e.attendees.add('x'), throwsUnsupportedError);
  });

  test('PortException: Text', () {
    expect(
      const PortException(PortErrorKind.notFound, 'weg').toString(),
      'PortException(notFound): weg',
    );
  });
}
