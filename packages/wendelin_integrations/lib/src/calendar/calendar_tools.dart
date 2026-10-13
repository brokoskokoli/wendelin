import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/time.dart';
import '../common/tool_args.dart';
import 'calendar_port.dart';

/// Shared state of the calendar tools: the port and the zone used for
/// confirmation texts. Confirmation texts of update/delete look the event up
/// live (`prepareConfirmation`); nothing is cached.
final class CalendarToolEnv {
  /// Creates the environment. [deviceTimeZone] supplies the IANA zone for
  /// synchronous confirmation texts; without it the zone of the last
  /// execution is used.
  CalendarToolEnv(this.port, {this.deviceTimeZone});

  /// Device calendar.
  final CalendarPort port;

  /// Zone for confirmation texts.
  final String Function()? deviceTimeZone;

  String? _lastZone;

  /// The zone for an execution: [override] if given, else the device zone
  /// from [ctx].
  tz.Location zoneFor(ToolContext ctx, [String? override]) {
    final loc = timeZoneLocation(ctx.timeZone);
    _lastZone = ctx.timeZone;
    return override == null ? loc : timeZoneLocation(override);
  }

  /// The zone for confirmation texts; falls back to UTC.
  tz.Location get describeZone {
    try {
      return timeZoneLocation(deviceTimeZone?.call() ?? _lastZone ?? 'UTC');
    } on InvalidArgumentsException {
      return timeZoneLocation('UTC');
    }
  }
}

const isoHint =
    'ISO 8601 local time, e.g. "2026-10-15T10:00"; without offset the '
    'device time zone applies';

/// Days of an all-day [event] (first and last, inclusive).
({LocalDate first, LocalDate last}) _allDayDates(CalendarEvent event) {
  final first = LocalDate.fromUtcMidnight(event.start);
  final endEx = LocalDate.fromUtcMidnight(event.end);
  return (
    first: first,
    last: endEx.compareTo(first) > 0 ? endEx.addDays(-1) : first,
  );
}

/// German span of [event] for summaries and confirmations.
String describeEventSpan(CalendarEvent event, tz.Location loc) {
  if (event.allDay) {
    final d = _allDayDates(event);
    return germanAllDaySpan(d.first, d.last);
  }
  return germanSpan(event.start, event.end, loc);
}

/// Whether [event] overlaps [range] when all-day events are read as local
/// days in [loc].
bool overlapsLocal(CalendarEvent event, TimeRange range, tz.Location loc) {
  if (!event.allDay) return event.range.overlaps(range);
  final d = _allDayDates(event);
  return TimeRange(
    d.first.startIn(loc),
    d.last.addDays(1).startIn(loc),
  ).overlaps(range);
}

/// Model-facing JSON of [event] (shortened unless [details]).
Map<String, Object?> eventJson(
  CalendarEvent event,
  tz.Location loc,
  Map<String, String> calendarNames, {
  bool details = false,
}) {
  final allDay = event.allDay ? _allDayDates(event) : null;
  return {
    'id': event.id,
    'title': event.title,
    if (allDay != null) ...{
      'all_day': true,
      'start': allDay.first.toIso(),
      'end': allDay.last.toIso(),
    } else ...{
      'start': isoInZone(event.start, loc),
      'end': isoInZone(event.end, loc),
    },
    if (event.location != null && event.location!.isNotEmpty)
      'location': event.location,
    'calendar': calendarNames[event.calendarId] ?? event.calendarId,
    if (event.recurring) 'recurring': true,
    if (!event.busy) 'free': true,
    if (details) ...{
      if (event.description != null && event.description!.isNotEmpty)
        'description': event.description,
      if (event.attendees.isNotEmpty) 'attendees': event.attendees,
    },
  };
}

/// Reads a required search range from `start`/`end`, at most [maxDays].
TimeRange readRange(ToolArgs args, tz.Location loc, int maxDays) {
  final start = IsoInput.parse(
    args.requireString('start'),
    'start',
  ).instantIn(loc);
  final endInput = IsoInput.parse(args.requireString('end'), 'end');
  // Ein reines Datum als Ende meint „bis Ende dieses Tages“.
  final end = endInput.hasTime
      ? endInput.instantIn(loc)
      : endInput.date.addDays(1).startIn(loc);
  if (!end.isAfter(start)) {
    throw const InvalidArgumentsException('„end“ muss nach „start“ liegen');
  }
  if (end.difference(start) > Duration(days: maxDays)) {
    throw InvalidArgumentsException(
      'Zeitraum ist zu lang (höchstens $maxDays Tage)',
    );
  }
  return TimeRange(start, end);
}

Future<Map<String, String>> calendarNames(CalendarPort port) async => {
  for (final c in await port.listCalendars()) c.id: c.name,
};

/// Start and exclusive end read from `start`/`end`/`all_day` arguments.
///
/// For updates, [old] supplies missing values: an unchanged start, and the
/// old length (or number of days) when only the start moves.
({DateTime start, DateTime end, bool allDay}) readEventTimes(
  ToolArgs args,
  tz.Location loc, {
  CalendarEvent? old,
}) {
  final allDay = args.optBool('all_day') ?? old?.allDay ?? false;
  final startText = args.optString('start');
  final startInput = startText == null
      ? null
      : IsoInput.parse(startText, 'start');
  final endText = args.optString('end');
  final endInput = endText == null ? null : IsoInput.parse(endText, 'end');
  if (allDay) {
    final LocalDate first;
    if (startInput != null) {
      first = startInput.date;
    } else if (old != null) {
      first = old.allDay
          ? LocalDate.fromUtcMidnight(old.start)
          : LocalDate.of(old.start, loc);
    } else {
      throw const InvalidArgumentsException('„start“ fehlt');
    }
    var days = 1;
    if (old != null && old.allDay) {
      days = old.end.difference(old.start).inDays.clamp(1, 3660);
    }
    final last = endInput?.date ?? first.addDays(days - 1);
    if (last.compareTo(first) < 0) {
      throw const InvalidArgumentsException('„end“ liegt vor „start“');
    }
    return (
      start: first.utcMidnight,
      end: last.addDays(1).utcMidnight,
      allDay: true,
    );
  }
  if (startInput != null && !startInput.hasTime) {
    throw const InvalidArgumentsException(
      '„start“ braucht eine Uhrzeit (z. B. 2026-10-15T10:00) '
      'oder all_day: true',
    );
  }
  if (startInput == null && (old == null || old.allDay)) {
    throw const InvalidArgumentsException(
      '„start“ mit Uhrzeit fehlt (z. B. 2026-10-15T10:00)',
    );
  }
  final start = startInput?.instantIn(loc) ?? old!.start;
  final DateTime end;
  if (endInput != null) {
    if (!endInput.hasTime) {
      throw const InvalidArgumentsException(
        '„end“ braucht eine Uhrzeit (z. B. 2026-10-15T11:00)',
      );
    }
    end = endInput.instantIn(loc);
  } else if (old != null && !old.allDay) {
    end = start.add(old.end.difference(old.start));
  } else {
    end = start.add(const Duration(hours: 1));
  }
  if (!end.isAfter(start)) {
    throw const InvalidArgumentsException('„end“ muss nach „start“ liegen');
  }
  return (start: start, end: end, allDay: false);
}
