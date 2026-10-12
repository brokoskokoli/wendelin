import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart';
import '../common/tool_args.dart';
import 'calendar_port.dart';
import 'free_slots.dart';

/// Shared state of the calendar tools: the port, a cache of recently seen
/// events (so `describeForConfirmation`, which is synchronous and gets only
/// the arguments, can name the event that will be deleted) and the zone
/// used for confirmation texts.
final class CalendarToolEnv {
  /// Creates the environment. [deviceTimeZone] supplies the IANA zone for
  /// confirmation texts; without it the zone of the last execution is used.
  CalendarToolEnv(this.port, {this.deviceTimeZone});

  /// Maximum number of cached events.
  static const cacheSize = 500;

  /// Device calendar.
  final CalendarPort port;

  /// Zone for confirmation texts.
  final String Function()? deviceTimeZone;

  final _cache = <String, CalendarEvent>{};
  String? _lastZone;

  /// The cached event with [id], if seen recently.
  CalendarEvent? cached(String id) => _cache[id];

  /// Caches the parts of [event] needed for confirmation texts (title,
  /// times, all-day, series), most recent last; the oldest is dropped
  /// beyond [cacheSize]. Location, notes, attendees are not kept.
  void remember(CalendarEvent event) {
    _cache
      ..remove(event.id)
      ..[event.id] = CalendarEvent(
        id: event.id,
        calendarId: '',
        title: event.title,
        start: event.start,
        end: event.end,
        allDay: event.allDay,
        recurring: event.recurring,
      );
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
  }

  /// Drops [id] from the cache.
  void forget(String id) => _cache.remove(id);

  /// Empties the cache; the app calls it when a session ends.
  void clearCache() => _cache.clear();

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

const _isoHint =
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
bool _overlapsLocal(CalendarEvent event, TimeRange range, tz.Location loc) {
  if (!event.allDay) return event.range.overlaps(range);
  final d = _allDayDates(event);
  return TimeRange(
    d.first.startIn(loc),
    d.last.addDays(1).startIn(loc),
  ).overlaps(range);
}

/// Model-facing JSON of [event] (shortened unless [details]).
Map<String, Object?> _eventJson(
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
TimeRange _readRange(ToolArgs args, tz.Location loc, int maxDays) {
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

Future<Map<String, String>> _calendarNames(CalendarPort port) async => {
  for (final c in await port.listCalendars()) c.id: c.name,
};

/// `calendar__list_calendars` (read).
final class ListCalendarsTool extends IntegrationTool {
  /// Creates the tool.
  const ListCalendarsTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  @override
  String get name => 'calendar__list_calendars';

  @override
  String get description =>
      'List the calendars on the device with id, name and whether events '
      'can be added. Use the id as calendar_id in other calendar tools.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final calendars = await env.port.listCalendars();
    final defaultId = await env.port.defaultCalendarId();
    return jsonOutcome({
      'calendars': [
        for (final c in calendars)
          {
            'id': c.id,
            'name': c.name,
            'writable': c.writable,
            if (c.id == defaultId) 'default': true,
          },
      ],
    }, summary: '${calendars.length} Kalender');
  }

  @override
  String describe(ToolArgs args) => 'Kalender auflisten';

  @override
  String get fallbackDescription => 'Kalender auflisten';
}

/// `calendar__list_events` (read).
final class ListEventsTool extends IntegrationTool {
  /// Creates the tool.
  const ListEventsTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  /// Most events returned to the model.
  static const maxEvents = 50;

  /// Longest range in days.
  static const maxDays = 92;

  @override
  String get name => 'calendar__list_events';

  @override
  String get description =>
      'List calendar events between start and end. Returns id, title, '
      'start, end, location and calendar. Set include_details to true only '
      'if the user asks for notes or attendees.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'start': {
        'type': 'string',
        'description': 'Start of the range, $_isoHint.',
      },
      'end': {
        'type': 'string',
        'description':
            'End of the range, e.g. "2026-10-15T23:59" or just '
            '"2026-10-15" for the whole day.',
      },
      'calendar_ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Only these calendars (default: all).',
      },
      'include_details': {
        'type': 'boolean',
        'description': 'Also return notes and attendees (default false).',
      },
    },
    'required': ['start', 'end'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final loc = env.zoneFor(ctx);
    final range = _readRange(args, loc, maxDays);
    final ids = args.optStringList('calendar_ids');
    final details = args.optBool('include_details') ?? false;
    final names = await _calendarNames(env.port);
    final raw = await env.port.listEvents(
      TimeRange(
        range.start.subtract(const Duration(days: 1)),
        range.end.add(const Duration(days: 1)),
      ),
      calendarIds: ids?.toSet(),
    );
    final events = raw.where((e) => _overlapsLocal(e, range, loc)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    events.forEach(env.remember);
    final shown = events.take(maxEvents).toList();
    return jsonOutcome(
      {
        'time_zone': loc.name,
        'events': [
          for (final e in shown) _eventJson(e, loc, names, details: details),
        ],
        if (events.length > shown.length)
          'truncated':
              '${events.length - shown.length} weitere Termine '
              'ausgelassen, Zeitraum verkleinern',
      },
      summary: switch (events.length) {
        0 => 'Keine Termine',
        1 => '1 Termin',
        final n => '$n Termine',
      },
    );
  }

  @override
  String describe(ToolArgs args) => 'Termine auflisten';

  @override
  String get fallbackDescription => 'Termine auflisten';
}

/// `calendar__find_free_slots` (read): free time between events within a
/// daily window, see [findFreeSlots].
final class FindFreeSlotsTool extends IntegrationTool {
  /// Creates the tool.
  const FindFreeSlotsTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  /// Longest range in days.
  static const maxDays = 31;

  @override
  String get name => 'calendar__find_free_slots';

  @override
  String get description =>
      'Find free time slots between start and end, only inside the daily '
      'window day_start–day_end. Example: start "2026-10-15T00:00", end '
      '"2026-10-16", min_duration_minutes 60.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'start': {
        'type': 'string',
        'description': 'Start of the search, $_isoHint.',
      },
      'end': {
        'type': 'string',
        'description': 'End of the search, e.g. "2026-10-17T18:00".',
      },
      'min_duration_minutes': {
        'type': 'integer',
        'minimum': 5,
        'description': 'Shortest useful slot (default 30).',
      },
      'buffer_minutes': {
        'type': 'integer',
        'minimum': 0,
        'description':
            'Free time to keep before and after events '
            '(default 0).',
      },
      'day_start': {
        'type': 'string',
        'description': 'Earliest time of day, e.g. "08:00" (default).',
      },
      'day_end': {
        'type': 'string',
        'description': 'Latest time of day, e.g. "20:00" (default).',
      },
      'weekdays': {
        'type': 'array',
        'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
        'description': 'Days to search, 1=Monday … 7=Sunday (default all).',
      },
      'calendar_ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Only consider these calendars (default: all).',
      },
      'max_results': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 50,
        'description': 'Most slots to return (default 10).',
      },
    },
    'required': ['start', 'end'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final loc = env.zoneFor(ctx);
    final range = _readRange(args, loc, maxDays);
    final dayStart = parseClockTime(
      args.optString('day_start') ?? '08:00',
      'day_start',
    );
    final dayEnd = parseClockTime(
      args.optString('day_end') ?? '20:00',
      'day_end',
    );
    if (dayEnd <= dayStart) {
      throw const InvalidArgumentsException(
        '„day_end“ muss nach „day_start“ liegen',
      );
    }
    final query = FreeSlotQuery(
      range: range,
      location: loc,
      minDuration: Duration(
        minutes:
            args.optInt('min_duration_minutes', min: 5, max: 24 * 60) ?? 30,
      ),
      buffer: Duration(
        minutes: args.optInt('buffer_minutes', min: 0, max: 24 * 60) ?? 0,
      ),
      dayStartMinutes: dayStart,
      dayEndMinutes: dayEnd,
      weekdays:
          args.optIntList('weekdays', min: 1, max: 7)?.toSet() ??
          const {1, 2, 3, 4, 5, 6, 7},
    );
    final maxResults = args.optInt('max_results', min: 1, max: 50) ?? 10;
    final events = await env.port.listEvents(
      TimeRange(
        range.start.subtract(const Duration(days: 1)),
        range.end.add(const Duration(days: 1)),
      ),
      calendarIds: args.optStringList('calendar_ids')?.toSet(),
    );
    final slots = findFreeSlots(query, events, maxResults: maxResults);
    return jsonOutcome(
      {
        'time_zone': loc.name,
        'slots': [
          for (final s in slots)
            {
              'start': isoInZone(s.start, loc),
              'end': isoInZone(s.end, loc),
              'minutes': s.duration.inMinutes,
            },
        ],
      },
      summary: slots.isEmpty
          ? 'Keine freie Zeit gefunden'
          : '${slots.length} freie Zeiten, ab '
                '${germanDateTime(slots.first.start, loc)}',
    );
  }

  @override
  String describe(ToolArgs args) => 'Freie Zeiten suchen';

  @override
  String get fallbackDescription => 'Freie Zeiten suchen';
}

/// Start and exclusive end read from `start`/`end`/`all_day` arguments.
///
/// For updates, [old] supplies missing values: an unchanged start, and the
/// old length (or number of days) when only the start moves.
({DateTime start, DateTime end, bool allDay}) _readEventTimes(
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

String? _optText(ToolArgs args, String key) {
  final v = args.optString(key);
  return v == null || v.isEmpty ? null : v;
}

/// German span for confirmation texts from raw arguments.
String _describeArgsSpan(ToolArgs args, tz.Location loc, {CalendarEvent? old}) {
  final t = _readEventTimes(args, loc, old: old);
  if (t.allDay) {
    return germanAllDaySpan(
      LocalDate.fromUtcMidnight(t.start),
      LocalDate.fromUtcMidnight(t.end).addDays(-1),
    );
  }
  return germanSpan(t.start, t.end, loc);
}

/// `calendar__create_event` (write, undo deletes the event).
final class CreateEventTool extends IntegrationTool {
  /// Creates the tool.
  const CreateEventTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  @override
  String get name => 'calendar__create_event';

  @override
  String get description =>
      'Create a calendar event. Example: title "Tauchen", start '
      '"2026-10-15T10:00", end "2026-10-15T11:00". Without end it lasts one '
      'hour. All-day: start "2026-10-15", all_day true. Goes to the default '
      'calendar unless calendar_id is given.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Event title.'},
      'start': {'type': 'string', 'description': 'Start, $_isoHint.'},
      'end': {
        'type': 'string',
        'description':
            'End, e.g. "2026-10-15T11:00" (default: start + 1 h). '
            'For all-day events the last day, e.g. "2026-10-16".',
      },
      'all_day': {
        'type': 'boolean',
        'description': 'Whole-day event (default false).',
      },
      'location': {'type': 'string', 'description': 'Place, optional.'},
      'description': {'type': 'string', 'description': 'Notes, optional.'},
      'calendar_id': {
        'type': 'string',
        'description': 'Target calendar id from calendar__list_calendars.',
      },
      'time_zone': {
        'type': 'string',
        'description':
            'IANA zone like "Europe/Lisbon", only if the user '
            'names a different zone.',
      },
    },
    'required': ['title', 'start'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final zoneName = _optText(args, 'time_zone');
    final loc = env.zoneFor(ctx, zoneName);
    final title = args.requireString('title');
    final times = _readEventTimes(args, loc);
    final calendarId = await _targetCalendar(_optText(args, 'calendar_id'));
    final event = await env.port.createEvent(
      CalendarEventDraft(
        calendarId: calendarId,
        title: title,
        start: times.start,
        end: times.end,
        allDay: times.allDay,
        location: _optText(args, 'location'),
        description: _optText(args, 'description'),
        timeZone: times.allDay ? 'UTC' : loc.name,
      ),
    );
    env.remember(event);
    final names = await _calendarNames(env.port);
    final when = event.allDay
        ? describeEventSpan(event, loc)
        : germanDateTime(event.start, loc);
    return jsonOutcome(
      {'created': _eventJson(event, loc, names)},
      summary: 'Termin angelegt: ${event.title}, $when',
      undo: UndoAction(
        label: 'Termin entfernen',
        run: () async {
          await env.port.deleteEvent(event.id);
          env.forget(event.id);
        },
      ),
    );
  }

  Future<String> _targetCalendar(String? requested) async {
    final calendars = await env.port.listCalendars();
    if (requested != null) {
      final match = calendars.where((c) => c.id == requested).firstOrNull;
      if (match == null) {
        throw PortException(
          PortErrorKind.notFound,
          'Kalender „$requested“ gibt es nicht',
        );
      }
      if (!match.writable) {
        throw PortException(
          PortErrorKind.readOnly,
          'Kalender „${match.name}“ ist schreibgeschützt',
        );
      }
      return match.id;
    }
    final defaultId = await env.port.defaultCalendarId();
    final writable = calendars.where((c) => c.writable);
    final chosen =
        writable.where((c) => c.id == defaultId).firstOrNull ??
        writable.firstOrNull;
    if (chosen == null) {
      throw const PortException(
        PortErrorKind.readOnly,
        'Kein beschreibbarer Kalender vorhanden',
      );
    }
    return chosen.id;
  }

  @override
  String describe(ToolArgs args) {
    final zone = _optText(args, 'time_zone');
    final loc = zone == null ? env.describeZone : timeZoneLocation(zone);
    return 'Termin ‚${args.requireString('title')}‘ '
        '${_describeArgsSpan(args, loc)} anlegen';
  }

  @override
  String get fallbackDescription => 'Termin anlegen';
}

/// `calendar__update_event` (write, undo restores the previous state).
final class UpdateEventTool extends IntegrationTool {
  /// Creates the tool.
  const UpdateEventTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  @override
  String get name => 'calendar__update_event';

  @override
  String get description =>
      'Change an existing event by event_id (from calendar__list_events). '
      'Only pass the fields to change. If only start is given, the event '
      'keeps its length. Example: event_id "42", start "2026-10-15T11:00". '
      'Recurring events: only title, location and notes of the whole series '
      'can be changed, not the time.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'event_id': {'type': 'string', 'description': 'Id of the event.'},
      'title': {'type': 'string', 'description': 'New title.'},
      'start': {'type': 'string', 'description': 'New start, $_isoHint.'},
      'end': {'type': 'string', 'description': 'New end.'},
      'all_day': {'type': 'boolean', 'description': 'Make it all-day.'},
      'location': {
        'type': 'string',
        'description': 'New place; empty string removes it.',
      },
      'description': {
        'type': 'string',
        'description': 'New notes; empty string removes them.',
      },
      'time_zone': {
        'type': 'string',
        'description': 'IANA zone, only if the user names a different zone.',
      },
    },
    'required': ['event_id'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final loc = env.zoneFor(ctx, _optText(args, 'time_zone'));
    final id = args.requireString('event_id');
    final old = await env.port.getEvent(id);
    if (old == null) {
      throw PortException(PortErrorKind.notFound, 'Termin „$id“ gibt es nicht');
    }
    final changesTime =
        args.has('start') || args.has('end') || args.has('all_day');
    if (old.recurring && changesTime) {
      throw const PortException(
        PortErrorKind.rejected,
        'Serientermin: einzelne Vorkommen bitte in der Kalender-App ändern. '
        'Titel, Ort und Notizen lassen sich für die ganze Serie ändern.',
      );
    }
    final times = changesTime
        ? _readEventTimes(args, loc, old: old)
        : (start: old.start, end: old.end, allDay: old.allDay);
    final newTitle = args.optString('title');
    final location = args.optString('location');
    final notes = args.optString('description');
    final updated = await env.port.updateEvent(
      old.copyWith(
        title: newTitle == null || newTitle.isEmpty ? null : newTitle,
        start: times.start,
        end: times.end,
        allDay: times.allDay,
        timeZone: changesTime ? (times.allDay ? 'UTC' : loc.name) : null,
        location: location == null
            ? old.location
            : (location.isEmpty ? null : location),
        description: notes == null
            ? old.description
            : (notes.isEmpty ? null : notes),
      ),
    );
    env.remember(updated);
    final names = await _calendarNames(env.port);
    final series = old.recurring ? ' (ganze Serie)' : '';
    return jsonOutcome(
      {
        'updated': _eventJson(updated, loc, names),
        if (old.recurring) 'scope': 'ganze Serie',
      },
      summary:
          'Termin geändert: ${updated.title}, '
          '${describeEventSpan(updated, loc)}$series',
      undo: UndoAction(
        label: 'Änderung rückgängig',
        run: () async => env.remember(await env.port.updateEvent(old)),
      ),
    );
  }

  @override
  String describe(ToolArgs args) {
    final id = args.requireString('event_id');
    final old = env.cached(id);
    final title = old == null ? '(ID $id)' : '‚${old.title}‘';
    final zone = _optText(args, 'time_zone');
    final loc = zone == null ? env.describeZone : timeZoneLocation(zone);
    final series = old?.recurring ?? false ? ' (ganze Serie)' : '';
    if (!args.has('start')) return 'Termin $title ändern$series';
    return 'Termin $title ändern: '
        '${_describeArgsSpan(args, loc, old: old)}$series';
  }

  @override
  String get fallbackDescription => 'Termin ändern';
}

/// `calendar__delete_event` (external: always confirmed).
final class DeleteEventTool extends IntegrationTool {
  /// Creates the tool.
  const DeleteEventTool(this.env);

  /// Shared calendar state.
  final CalendarToolEnv env;

  @override
  String get name => 'calendar__delete_event';

  @override
  String get description =>
      'Delete an event by event_id (from calendar__list_events). The user '
      'is asked to confirm. For a recurring event this deletes the WHOLE '
      'series, not just one occurrence.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'event_id': {'type': 'string', 'description': 'Id of the event.'},
    },
    'required': ['event_id'],
  };

  @override
  RiskLevel get risk => RiskLevel.external;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final loc = env.zoneFor(ctx);
    final id = args.requireString('event_id');
    final event = await env.port.getEvent(id);
    if (event == null) {
      throw PortException(PortErrorKind.notFound, 'Termin „$id“ gibt es nicht');
    }
    await env.port.deleteEvent(id);
    env.forget(id);
    return jsonOutcome(
      {
        'deleted': id,
        'title': event.title,
        if (event.recurring) 'scope': 'ganze Serie',
      },
      summary:
          'Termin gelöscht: ${event.title}, ${describeEventSpan(event, loc)}'
          '${event.recurring ? ' (ganze Serie)' : ''}',
    );
  }

  @override
  String describe(ToolArgs args) {
    final id = args.requireString('event_id');
    final event = env.cached(id);
    if (event == null) return 'Termin (ID $id) löschen';
    return 'Termin ‚${event.title}‘ '
        '${describeEventSpan(event, env.describeZone)} löschen'
        '${event.recurring ? ' (ganze Serie)' : ''}';
  }

  @override
  String get fallbackDescription => 'Termin löschen';
}
