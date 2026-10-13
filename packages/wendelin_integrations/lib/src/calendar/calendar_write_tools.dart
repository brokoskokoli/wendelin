import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart';
import '../common/tool_args.dart';
import 'calendar_port.dart';
import 'calendar_tools.dart';

String? _optText(ToolArgs args, String key) {
  final v = args.optString(key);
  return v == null || v.isEmpty ? null : v;
}

/// German span for confirmation texts from raw arguments.
String _describeArgsSpan(ToolArgs args, tz.Location loc, {CalendarEvent? old}) {
  final t = readEventTimes(args, loc, old: old);
  if (t.allDay) {
    return germanAllDaySpan(
      LocalDate.fromUtcMidnight(t.start),
      LocalDate.fromUtcMidnight(t.end).addDays(-1),
    );
  }
  return germanSpan(t.start, t.end, loc);
}

/// `calendar__create_event` (write, undo deletes the event).
final class CreateEventTool extends IntegrationTool
    implements TrustedContentSource {
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
      'start': {'type': 'string', 'description': 'Start, $isoHint.'},
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
    final times = readEventTimes(args, loc);
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
    final when = event.allDay
        ? describeEventSpan(event, loc)
        : germanDateTime(event.start, loc);
    return jsonOutcome(
      {
        // Only the calendar id: names of shared calendars come from others.
        'created': eventJson(event, loc, const {}),
      },
      summary: 'Termin angelegt: ${event.title}, $when',
      undo: UndoAction(
        label: 'Termin entfernen',
        run: () => env.port.deleteEvent(event.id),
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
final class UpdateEventTool extends IntegrationTool
    implements ConfirmationPreparer {
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
      'start': {'type': 'string', 'description': 'New start, $isoHint.'},
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
        ? readEventTimes(args, loc, old: old)
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
    final names = await calendarNames(env.port);
    final series = old.recurring ? ' (ganze Serie)' : '';
    return jsonOutcome(
      {
        'updated': eventJson(updated, loc, names),
        if (old.recurring) 'scope': 'ganze Serie',
      },
      summary:
          'Termin geändert: ${updated.title}, '
          '${describeEventSpan(updated, loc)}$series',
      undo: UndoAction(
        label: 'Änderung rückgängig',
        run: () async => env.port.updateEvent(old),
      ),
    );
  }

  @override
  String describe(ToolArgs args) => _text(args, null, env.describeZone);

  /// Looks the event up to name its title, time and series.
  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final a = ToolArgs(args);
    try {
      final old = await env.port.getEvent(a.requireString('event_id'));
      return _text(a, old, timeZoneLocation(ctx.timeZone));
    } on InvalidArgumentsException {
      return fallbackDescription;
    }
  }

  String _text(ToolArgs args, CalendarEvent? old, tz.Location deviceZone) {
    final id = args.requireString('event_id');
    final title = old == null ? '(ID $id)' : '‚${old.title}‘';
    final zone = _optText(args, 'time_zone');
    final loc = zone == null ? deviceZone : timeZoneLocation(zone);
    final series = old?.recurring ?? false ? ' (ganze Serie)' : '';
    if (!args.has('start')) return 'Termin $title ändern$series';
    return 'Termin $title ändern: '
        '${_describeArgsSpan(args, loc, old: old)}$series';
  }

  @override
  String get fallbackDescription => 'Termin ändern';
}

/// `calendar__delete_event` (external: always confirmed).
final class DeleteEventTool extends IntegrationTool
    implements ConfirmationPreparer {
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
  String describe(ToolArgs args) =>
      'Termin (ID ${args.requireString('event_id')}) löschen';

  /// Looks the event up to name its title, time and series.
  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final a = ToolArgs(args);
    try {
      final id = a.requireString('event_id');
      final event = await env.port.getEvent(id);
      if (event == null) return describe(a);
      return 'Termin ‚${event.title}‘ '
          '${describeEventSpan(event, timeZoneLocation(ctx.timeZone))} löschen'
          '${event.recurring ? ' (ganze Serie)' : ''}';
    } on InvalidArgumentsException {
      return fallbackDescription;
    }
  }

  @override
  String get fallbackDescription => 'Termin löschen';
}
