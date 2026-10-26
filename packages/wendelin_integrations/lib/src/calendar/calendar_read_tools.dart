import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/time.dart';
import '../common/tool_args.dart';
import 'calendar_port.dart';
import 'calendar_tools.dart';
import 'free_slots.dart';

/// `calendar__list_calendars` (read).
final class ListCalendarsTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
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
final class ListEventsTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
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
        'description': 'Start of the range, $isoHint.',
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
    final range = readRange(args, loc, maxDays);
    final ids = args.optStringList('calendar_ids');
    final details = args.optBool('include_details') ?? false;
    final names = await calendarNames(env.port);
    final raw = await env.port.listEvents(
      TimeRange(
        range.start.subtract(const Duration(days: 1)),
        range.end.add(const Duration(days: 1)),
      ),
      calendarIds: ids?.toSet(),
    );
    final events = raw.where((e) => overlapsLocal(e, range, loc)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final shown = events.take(maxEvents).toList();
    return jsonOutcome(
      {
        'time_zone': loc.name,
        'events': [
          for (final e in shown) eventJson(e, loc, names, details: details),
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
final class FindFreeSlotsTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
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
        'description': 'Start of the search, $isoHint.',
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
    final range = readRange(args, loc, maxDays);
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
