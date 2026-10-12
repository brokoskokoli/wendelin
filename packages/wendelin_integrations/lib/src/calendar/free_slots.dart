import 'package:timezone/timezone.dart' as tz;

import '../common/time.dart';
import 'calendar_port.dart';

/// Parameters of [findFreeSlots].
final class FreeSlotQuery {
  /// Creates a query.
  ///
  /// [dayStartMinutes]/[dayEndMinutes] are the daily window as wall-clock
  /// minutes after midnight in [location] (`24 * 60` = midnight at the end
  /// of the day). [weekdays] are ISO weekdays (1 = Monday … 7 = Sunday).
  FreeSlotQuery({
    required this.range,
    required this.location,
    this.minDuration = const Duration(minutes: 30),
    this.buffer = Duration.zero,
    this.dayStartMinutes = 8 * 60,
    this.dayEndMinutes = 20 * 60,
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  }) : weekdays = Set.unmodifiable(weekdays) {
    if (minDuration <= Duration.zero) {
      throw ArgumentError.value(minDuration, 'minDuration', 'muss > 0 sein');
    }
    if (buffer.isNegative) {
      throw ArgumentError.value(buffer, 'buffer', 'darf nicht negativ sein');
    }
    if (dayStartMinutes < 0 ||
        dayEndMinutes > 24 * 60 ||
        dayStartMinutes >= dayEndMinutes) {
      throw ArgumentError('Tagesfenster ungültig');
    }
  }

  /// Search range (UTC).
  final TimeRange range;

  /// Zone of the daily window and of all-day events.
  final tz.Location location;

  /// Shortest slot to report (real elapsed time).
  final Duration minDuration;

  /// Free time kept before and after every busy event.
  final Duration buffer;

  /// Start of the daily window (minutes after local midnight).
  final int dayStartMinutes;

  /// End of the daily window (minutes after local midnight).
  final int dayEndMinutes;

  /// ISO weekdays to search on.
  final Set<int> weekdays;
}

/// Free slots within [query]'s daily windows that are not covered by a
/// busy event of [events] (plus buffer), at least `minDuration` long, in
/// chronological order, at most [maxResults].
///
/// - Events with `busy == false` are ignored.
/// - All-day events block their whole local days in `query.location`.
/// - Windows are built per local date, so DST changes shorten or lengthen
///   the window in real time (e.g. 00:00–06:00 is 5 h on the spring-forward
///   day in Europe/Berlin).
List<TimeRange> findFreeSlots(
  FreeSlotQuery query,
  Iterable<CalendarEvent> events, {
  int? maxResults,
}) {
  final loc = query.location;
  final busy = _mergedBusy(events, query);
  final slots = <TimeRange>[];
  final last = LocalDate.of(query.range.end, loc);
  for (
    var d = LocalDate.of(query.range.start, loc);
    d.compareTo(last) <= 0;
    d = d.addDays(1)
  ) {
    if (!query.weekdays.contains(d.weekday)) continue;
    var from = _max(d.atMinutes(query.dayStartMinutes, loc), query.range.start);
    final to = _min(d.atMinutes(query.dayEndMinutes, loc), query.range.end);
    if (!from.isBefore(to)) continue;
    for (final b in busy) {
      if (!b.end.isAfter(from)) continue;
      if (!b.start.isBefore(to)) break;
      _addIfLong(slots, from, b.start, query.minDuration);
      from = _max(from, b.end);
      if (!from.isBefore(to)) break;
    }
    _addIfLong(slots, from, to, query.minDuration);
    if (maxResults != null && slots.length >= maxResults) {
      return slots.sublist(0, maxResults);
    }
  }
  return slots;
}

/// Busy intervals (with buffer) sorted by start and merged.
List<TimeRange> _mergedBusy(
  Iterable<CalendarEvent> events,
  FreeSlotQuery query,
) {
  final raw = <TimeRange>[
    for (final e in events)
      if (e.busy) _blockOf(e, query),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TimeRange>[];
  for (final r in raw) {
    if (merged.isNotEmpty && !r.start.isAfter(merged.last.end)) {
      final last = merged.removeLast();
      merged.add(TimeRange(last.start, _max(last.end, r.end)));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

TimeRange _blockOf(CalendarEvent e, FreeSlotQuery query) {
  if (e.allDay) {
    // Ganztägig: blockiert die lokalen Tage, ohne Puffer.
    final first = LocalDate.fromUtcMidnight(e.start);
    var endExclusive = LocalDate.fromUtcMidnight(e.end);
    if (endExclusive.compareTo(first) <= 0) endExclusive = first.addDays(1);
    return TimeRange(
      first.startIn(query.location),
      endExclusive.startIn(query.location),
    );
  }
  return TimeRange(e.start.subtract(query.buffer), e.end.add(query.buffer));
}

void _addIfLong(List<TimeRange> out, DateTime from, DateTime to, Duration min) {
  if (to.difference(from) >= min) out.add(TimeRange(from, to));
}

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
