import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Device calendar access (Android `CalendarContract`, iOS EventKit).
///
/// Implemented in the app (`app/lib/platform/`); every implementation must
/// pass `calendarPortContract`. Expected failures are thrown as
/// `PortException` (permission missing, read-only calendar, unknown id).
///
/// All instants are UTC [DateTime]s. All-day events use UTC midnights of
/// their first day and of the day **after** their last day (exclusive end),
/// like Android's `CalendarContract`.
abstract interface class CalendarPort {
  /// Whether calendar access is granted.
  Future<bool> hasPermission();

  /// All calendars visible on the device (Google, Exchange, CalDAV, local …).
  Future<List<CalendarInfo>> listCalendars();

  /// The calendar new events go to (chosen by the user), or `null`.
  Future<String?> defaultCalendarId();

  /// Events overlapping [range] (`start < range.end && end > range.start`),
  /// optionally only from [calendarIds]. Recurring events are returned as
  /// occurrences. All-day events may be included when their UTC day touches
  /// the range; callers filter by local day.
  Future<List<CalendarEvent>> listEvents(
    TimeRange range, {
    Set<String>? calendarIds,
  });

  /// The event with [id], or `null` if it does not exist.
  Future<CalendarEvent?> getEvent(String id);

  /// Creates an event and returns it with its new id.
  Future<CalendarEvent> createEvent(CalendarEventDraft draft);

  /// Replaces the stored fields of the event with `event.id`; returns the
  /// stored event. Throws `PortException(notFound)` for unknown ids.
  Future<CalendarEvent> updateEvent(CalendarEvent event);

  /// Deletes the event with [id]. Throws `PortException(notFound)` for
  /// unknown ids.
  Future<void> deleteEvent(String id);
}

/// A half-open time interval `[start, end)` of UTC instants.
@immutable
final class TimeRange {
  /// Creates a range; [end] must not be before [start].
  TimeRange(DateTime start, DateTime end)
    : start = start.toUtc(),
      end = end.toUtc() {
    if (end.isBefore(start)) {
      throw ArgumentError.value(end, 'end', 'liegt vor start');
    }
  }

  /// Inclusive start.
  final DateTime start;

  /// Exclusive end.
  final DateTime end;

  /// Length of the range.
  Duration get duration => end.difference(start);

  /// Whether this range and [other] share at least one instant.
  bool overlaps(TimeRange other) =>
      start.isBefore(other.end) && end.isAfter(other.start);

  @override
  bool operator ==(Object other) =>
      other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'TimeRange(${start.toIso8601String()}, ${end.toIso8601String()})';
}

/// A calendar on the device.
@immutable
final class CalendarInfo {
  /// Creates calendar info.
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.writable,
    this.accountName,
  });

  /// Platform id.
  final String id;

  /// Display name.
  final String name;

  /// Whether events can be created in it.
  final bool writable;

  /// Account it belongs to (e.g. a Google address), if known.
  final String? accountName;

  @override
  bool operator ==(Object other) =>
      other is CalendarInfo &&
      other.id == id &&
      other.name == name &&
      other.writable == writable &&
      other.accountName == accountName;

  @override
  int get hashCode => Object.hash(id, name, writable, accountName);

  @override
  String toString() => 'CalendarInfo($id, $name, writable: $writable)';
}

/// The fields of a new event.
@immutable
final class CalendarEventDraft {
  /// Creates a draft; see [CalendarPort] for the all-day convention.
  const CalendarEventDraft({
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
    this.timeZone,
  });

  /// Target calendar.
  final String calendarId;

  /// Title.
  final String title;

  /// Start (UTC).
  final DateTime start;

  /// Exclusive end (UTC).
  final DateTime end;

  /// Whether the event spans whole days.
  final bool allDay;

  /// Location, if any.
  final String? location;

  /// Notes, if any.
  final String? description;

  /// IANA zone the event was planned in (Android `EVENT_TIMEZONE`).
  final String? timeZone;

  @override
  bool operator ==(Object other) =>
      other is CalendarEventDraft &&
      other.calendarId == calendarId &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.location == location &&
      other.description == description &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(
    calendarId,
    title,
    start,
    end,
    allDay,
    location,
    description,
    timeZone,
  );
}

const _keep = Object();

/// A stored calendar event (or an occurrence of a recurring one).
@immutable
final class CalendarEvent {
  /// Creates an event; [attendees] is copied unmodifiable.
  CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
    List<String> attendees = const [],
    this.busy = true,
    this.recurring = false,
    this.timeZone,
  }) : attendees = List.unmodifiable(attendees);

  /// The stored event for [draft] with [id].
  factory CalendarEvent.fromDraft(String id, CalendarEventDraft draft) =>
      CalendarEvent(
        id: id,
        calendarId: draft.calendarId,
        title: draft.title,
        start: draft.start,
        end: draft.end,
        allDay: draft.allDay,
        location: draft.location,
        description: draft.description,
        timeZone: draft.timeZone,
      );

  /// Platform id (for recurring events: of the series).
  final String id;

  /// Calendar the event belongs to.
  final String calendarId;

  /// Title.
  final String title;

  /// Start (UTC).
  final DateTime start;

  /// Exclusive end (UTC).
  final DateTime end;

  /// Whether the event spans whole days.
  final bool allDay;

  /// Location, if any.
  final String? location;

  /// Notes, if any.
  final String? description;

  /// Attendee names or addresses.
  final List<String> attendees;

  /// Whether the event blocks time (`false` = shown as free).
  final bool busy;

  /// Whether the event is part of a series.
  final bool recurring;

  /// IANA zone the event was planned in, if known.
  final String? timeZone;

  /// A copy with the given fields replaced; pass `null` to clear
  /// [location] or [description].
  CalendarEvent copyWith({
    String? calendarId,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    Object? location = _keep,
    Object? description = _keep,
    String? timeZone,
  }) => CalendarEvent(
    id: id,
    calendarId: calendarId ?? this.calendarId,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    location: identical(location, _keep) ? this.location : location as String?,
    description: identical(description, _keep)
        ? this.description
        : description as String?,
    attendees: attendees,
    busy: busy,
    recurring: recurring,
    timeZone: timeZone ?? this.timeZone,
  );

  /// The time span of the event.
  TimeRange get range => TimeRange(start, end);

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.calendarId == calendarId &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.location == location &&
      other.description == description &&
      const ListEquality<String>().equals(other.attendees, attendees) &&
      other.busy == busy &&
      other.recurring == recurring &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(
    id,
    calendarId,
    title,
    start,
    end,
    allDay,
    location,
    description,
    const ListEquality<String>().hash(attendees),
    busy,
    recurring,
    timeZone,
  );

  @override
  String toString() =>
      'CalendarEvent($id, $title, ${start.toIso8601String()}–'
      '${end.toIso8601String()}${allDay ? ', ganztägig' : ''})';
}
