import 'dart:async';

import 'package:test/test.dart';

import '../src/calendar/calendar_port.dart';
import '../src/common/port_exception.dart';

/// Creates the [CalendarPort] under test.
///
/// Preconditions for real devices: calendar permission granted and at least
/// one writable calendar. The checks only touch events they created
/// themselves (title prefix [calendarContractTitlePrefix], in March 2031)
/// and delete them again.
typedef CalendarPortFactory = FutureOr<CalendarPort> Function();

/// Title prefix of events created by [calendarPortContract].
const calendarContractTitlePrefix = 'Wendelin-Contract';

/// Names of the checks in [calendarPortContractChecks].
abstract final class CalendarPortChecks {
  /// Calendars have unique ids; the default calendar exists and is writable.
  static const calendars =
      'listCalendars: eindeutige Ids, Standardkalender beschreibbar';

  /// createEvent stores all fields and returns a new id.
  static const create = 'createEvent liefert gespeicherten Termin mit neuer Id';

  /// listEvents uses half-open overlap and the calendar filter.
  static const listOverlap =
      'listEvents: Überlappung halboffen, Kalenderfilter';

  /// updateEvent changes fields and keeps the id.
  static const update = 'updateEvent ändert Felder und behält die Id';

  /// deleteEvent removes; deleting again is notFound.
  static const delete =
      'deleteEvent entfernt den Termin, zweites Löschen ist notFound';

  /// Unknown ids: getEvent null, updateEvent notFound.
  static const unknownId = 'unbekannte Id: getEvent null, updateEvent notFound';

  /// All-day events keep UTC midnights and the exclusive end.
  static const allDay = 'ganztägiger Termin: UTC-Mitternacht, exklusives Ende';

  /// Read-only calendars reject createEvent (if one exists).
  static const readOnly = 'schreibgeschützter Kalender lehnt createEvent ab';
}

/// Reusable contract suite for every [CalendarPort] implementation
/// (`FakeCalendarPort`, the app's device calendar port); registers one test
/// per entry of [calendarPortContractChecks].
void calendarPortContract(
  CalendarPortFactory create, {
  String name = 'CalendarPort',
}) {
  group('$name erfüllt den CalendarPort-Vertrag', () {
    calendarPortContractChecks(create).forEach(test);
  });
}

/// The checks of [calendarPortContract] by name ([CalendarPortChecks]), so
/// single checks can be run against defective implementations.
Map<String, Future<void> Function()> calendarPortContractChecks(
  CalendarPortFactory create,
) {
  final base = DateTime.utc(2031, 3, 10, 9);
  const hour = Duration(hours: 1);
  const minute = Duration(minutes: 1);
  final notFound = throwsA(
    isA<PortException>().having((p) => p.kind, 'kind', PortErrorKind.notFound),
  );

  /// Runs [body] with a fresh port and a writable calendar id; deletes all
  /// events created through the helper afterwards.
  Future<void> withPort(Future<void> Function(_Harness h) body) async {
    final port = await create();
    expect(
      await port.hasPermission(),
      isTrue,
      reason: 'Vorbedingung: Kalenderzugriff erlaubt',
    );
    final writable = (await port.listCalendars()).where((c) => c.writable);
    expect(
      writable,
      isNotEmpty,
      reason: 'Vorbedingung: beschreibbarer Kalender',
    );
    final def = await port.defaultCalendarId();
    final h = _Harness(
      port,
      writable.any((c) => c.id == def) ? def! : writable.first.id,
      base,
    );
    try {
      await body(h);
    } finally {
      await h.cleanUp();
    }
  }

  return {
    CalendarPortChecks.calendars: () => withPort((h) async {
      final calendars = await h.port.listCalendars();
      final ids = calendars.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'Ids eindeutig');
      expect(calendars.every((c) => c.name.isNotEmpty), isTrue);
      final def = await h.port.defaultCalendarId();
      if (def != null) {
        final match = calendars.where((c) => c.id == def);
        expect(match, hasLength(1), reason: 'Standardkalender existiert');
        expect(match.single.writable, isTrue);
      }
    }),
    CalendarPortChecks.create: () => withPort((h) async {
      final e = await h.createTimed(location: 'Hafen', description: 'Notiz');
      expect(e.id, isNotEmpty);
      expect(e.title, startsWith(calendarContractTitlePrefix));
      expect(e.calendarId, h.calendarId);
      expect(e.start.isAtSameMomentAs(base), isTrue);
      expect(e.end.isAtSameMomentAs(base.add(hour)), isTrue);
      expect(e.allDay, isFalse);
      expect(e.location, 'Hafen');
      expect(e.description, 'Notiz');
      final again = await h.port.getEvent(e.id);
      expect(again, isNotNull);
      expect(again!.title, e.title);
      expect(again.calendarId, h.calendarId);
      expect(again.location, 'Hafen');
      expect(again.start.isAtSameMomentAs(e.start), isTrue);
      expect(again.end.isAtSameMomentAs(e.end), isTrue);
      final other = await h.createTimed();
      expect(other.id, isNot(e.id));
    }),
    CalendarPortChecks.listOverlap: () => withPort((h) async {
      final e = await h.createTimed();
      Future<bool> found(
        DateTime from,
        DateTime to, {
        Set<String>? ids,
      }) async => (await h.port.listEvents(
        TimeRange(from, to),
        calendarIds: ids,
      )).any((x) => x.id == e.id);

      expect(await found(base.subtract(hour), base.add(hour * 2)), isTrue);
      expect(await found(base.add(minute * 30), base.add(minute * 31)), isTrue);
      expect(await found(base.subtract(minute), base.add(minute)), isTrue);
      expect(
        await found(base.add(hour - minute), base.add(hour)),
        isTrue,
        reason: 'letzte Minute gehört dazu',
      );
      expect(
        await found(base.subtract(hour), base),
        isFalse,
        reason: 'Bereich endet genau am Beginn',
      );
      expect(
        await found(base.add(hour), base.add(hour * 2)),
        isFalse,
        reason: 'Bereich beginnt genau am Ende',
      );
      expect(
        await found(
          base.subtract(hour),
          base.add(hour * 2),
          ids: {h.calendarId},
        ),
        isTrue,
      );
      expect(
        await found(
          base.subtract(hour),
          base.add(hour * 2),
          ids: {'wendelin-contract-unknown-calendar'},
        ),
        isFalse,
        reason: 'Kalenderfilter',
      );
    }),
    CalendarPortChecks.update: () => withPort((h) async {
      final e = await h.createTimed(location: 'Hafen');
      final moved = base.add(hour * 3);
      final u = await h.port.updateEvent(
        e.copyWith(
          title: '$calendarContractTitlePrefix geändert',
          start: moved,
          end: moved.add(minute * 30),
          location: null,
        ),
      );
      expect(u.id, e.id);
      final again = (await h.port.getEvent(e.id))!;
      expect(again.title, '$calendarContractTitlePrefix geändert');
      expect(again.start.isAtSameMomentAs(moved), isTrue);
      expect(again.end.isAtSameMomentAs(moved.add(minute * 30)), isTrue);
      expect(again.location ?? '', isEmpty);
      final old = await h.port.listEvents(TimeRange(base, base.add(hour)));
      expect(old.any((x) => x.id == e.id), isFalse, reason: 'alter Zeitraum');
      final now = await h.port.listEvents(TimeRange(moved, moved.add(hour)));
      expect(now.any((x) => x.id == e.id), isTrue, reason: 'neuer Zeitraum');
    }),
    CalendarPortChecks.delete: () => withPort((h) async {
      final e = await h.createTimed();
      final keep = await h.createTimed();
      await h.port.deleteEvent(e.id);
      expect(await h.port.getEvent(e.id), isNull);
      expect(await h.port.getEvent(keep.id), isNotNull, reason: 'nur einer');
      final list = await h.port.listEvents(TimeRange(base, base.add(hour)));
      expect(list.any((x) => x.id == e.id), isFalse);
      await expectLater(h.port.deleteEvent(e.id), notFound);
    }),
    CalendarPortChecks.unknownId: () => withPort((h) async {
      final e = await h.createTimed();
      await h.port.deleteEvent(e.id);
      expect(await h.port.getEvent(e.id), isNull);
      await expectLater(h.port.updateEvent(e.copyWith(title: 'x')), notFound);
    }),
    CalendarPortChecks.allDay: () => withPort((h) async {
      final day = DateTime.utc(2031, 3, 12);
      final e = await h.port.createEvent(
        CalendarEventDraft(
          calendarId: h.calendarId,
          title: '$calendarContractTitlePrefix ganztägig',
          start: day,
          end: day.add(const Duration(days: 2)),
          allDay: true,
          timeZone: 'UTC',
        ),
      );
      h.created.add(e.id);
      final again = (await h.port.getEvent(e.id))!;
      expect(again.allDay, isTrue);
      expect(again.start.isAtSameMomentAs(day), isTrue);
      expect(
        again.end.isAtSameMomentAs(day.add(const Duration(days: 2))),
        isTrue,
      );
      final list = await h.port.listEvents(
        TimeRange(day.add(hour * 30), day.add(hour * 31)),
      );
      expect(list.any((x) => x.id == e.id), isTrue, reason: 'zweiter Tag');
    }),
    CalendarPortChecks.readOnly: () => withPort((h) async {
      final readOnly = (await h.port.listCalendars()).where((c) => !c.writable);
      // Ohne schreibgeschützten Kalender ist nichts zu prüfen.
      if (readOnly.isEmpty) return;
      await expectLater(
        h.port.createEvent(
          CalendarEventDraft(
            calendarId: readOnly.first.id,
            title: '$calendarContractTitlePrefix verboten',
            start: base,
            end: base.add(hour),
          ),
        ),
        throwsA(
          isA<PortException>().having(
            (p) => p.kind,
            'kind',
            PortErrorKind.readOnly,
          ),
        ),
      );
    }),
  };
}

final class _Harness {
  _Harness(this.port, this.calendarId, this.base);

  final CalendarPort port;
  final String calendarId;
  final DateTime base;
  final List<String> created = [];
  var _counter = 0;

  Future<CalendarEvent> createTimed({
    String? location,
    String? description,
  }) async {
    final e = await port.createEvent(
      CalendarEventDraft(
        calendarId: calendarId,
        title: '$calendarContractTitlePrefix ${++_counter}',
        start: base,
        end: base.add(const Duration(hours: 1)),
        location: location,
        description: description,
        timeZone: 'Europe/Berlin',
      ),
    );
    created.add(e.id);
    return e;
  }

  Future<void> cleanUp() async {
    for (final id in created) {
      try {
        await port.deleteEvent(id);
      } on PortException {
        // Bereits gelöscht.
      }
    }
  }
}
