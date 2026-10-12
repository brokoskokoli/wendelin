import '../src/calendar/calendar_port.dart';
import '../src/common/port_exception.dart';
import 'fake_failures.dart';

/// In-memory [CalendarPort] for tests and the demo mode.
///
/// Behaves like a device calendar: read-only calendars reject writes,
/// unknown ids throw `PortException(notFound)`, a missing permission makes
/// every call except [hasPermission] throw `permissionDenied`. Use
/// [failNext] to simulate other failures.
final class FakeCalendarPort with FakeFailures implements CalendarPort {
  /// Creates the fake with [calendars] (default: one writable „Privat“
  /// calendar with id `privat`) and optional initial [events].
  FakeCalendarPort({
    List<CalendarInfo>? calendars,
    this.defaultId = 'privat',
    Iterable<CalendarEvent> events = const [],
    this.permissionGranted = true,
  }) : calendars =
           calendars ??
           [const CalendarInfo(id: 'privat', name: 'Privat', writable: true)] {
    for (final e in events) {
      _events[e.id] = e;
    }
  }

  /// Calendars returned by [listCalendars] (mutable).
  final List<CalendarInfo> calendars;

  /// Returned by [defaultCalendarId].
  String? defaultId;

  /// Whether calendar access is granted.
  bool permissionGranted;

  final Map<String, CalendarEvent> _events = {};
  int _nextId = 1;

  /// All stored events (series, not occurrences).
  List<CalendarEvent> get events => List.unmodifiable(_events.values);

  void _guard(String method) {
    enter(method);
    if (!permissionGranted) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf den Kalender. Bitte in den Einstellungen erlauben.',
      );
    }
  }

  CalendarInfo _writableCalendar(String id) {
    final cal = calendars.where((c) => c.id == id).firstOrNull;
    if (cal == null) {
      throw PortException(
        PortErrorKind.notFound,
        'Kalender „$id“ gibt es nicht',
      );
    }
    if (!cal.writable) {
      throw PortException(
        PortErrorKind.readOnly,
        'Kalender „${cal.name}“ ist schreibgeschützt',
      );
    }
    return cal;
  }

  CalendarEvent _existing(String id) =>
      _events[id] ??
      (throw PortException(
        PortErrorKind.notFound,
        'Termin „$id“ gibt es nicht',
      ));

  @override
  Future<bool> hasPermission() async {
    enter('hasPermission');
    return permissionGranted;
  }

  @override
  Future<List<CalendarInfo>> listCalendars() async {
    _guard('listCalendars');
    return List.unmodifiable(calendars);
  }

  @override
  Future<String?> defaultCalendarId() async {
    _guard('defaultCalendarId');
    return defaultId;
  }

  @override
  Future<List<CalendarEvent>> listEvents(
    TimeRange range, {
    Set<String>? calendarIds,
  }) async {
    _guard('listEvents');
    return [
      for (final e in _events.values)
        if ((calendarIds == null || calendarIds.contains(e.calendarId)) &&
            e.range.overlaps(range))
          e,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<CalendarEvent?> getEvent(String id) async {
    _guard('getEvent');
    return _events[id];
  }

  @override
  Future<CalendarEvent> createEvent(CalendarEventDraft draft) async {
    _guard('createEvent');
    _writableCalendar(draft.calendarId);
    if (!draft.end.isAfter(draft.start)) {
      throw const PortException(
        PortErrorKind.rejected,
        'Ende muss nach dem Beginn liegen',
      );
    }
    var id = 'e${_nextId++}';
    while (_events.containsKey(id)) {
      id = 'e${_nextId++}';
    }
    return _events[id] = CalendarEvent.fromDraft(id, draft);
  }

  @override
  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    _guard('updateEvent');
    _existing(event.id);
    _writableCalendar(event.calendarId);
    return _events[event.id] = event;
  }

  @override
  Future<void> deleteEvent(String id) async {
    _guard('deleteEvent');
    final e = _existing(id);
    _writableCalendar(e.calendarId);
    _events.remove(id);
  }
}
