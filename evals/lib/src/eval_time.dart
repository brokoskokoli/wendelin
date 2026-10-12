import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_integrations/wendelin_integrations.dart'
    show timeZoneLocation;

/// A wall-clock date and optional time of day, without zone.
@immutable
final class WallTime implements Comparable<WallTime> {
  /// Creates a wall time; [hour]/[minute] `null` = only a date.
  const WallTime(this.year, this.month, this.day, [this.hour, this.minute]);

  /// Year.
  final int year;

  /// Month 1–12.
  final int month;

  /// Day of month.
  final int day;

  /// Hour 0–23, or `null` for a date.
  final int? hour;

  /// Minute 0–59, or `null` for a date.
  final int? minute;

  /// Whether a time of day is set.
  bool get hasTime => hour != null;

  /// The date part only.
  WallTime get date => WallTime(year, month, day);

  DateTime get _utc => DateTime.utc(year, month, day, hour ?? 0, minute ?? 0);

  /// Minutes between this and [other] (positive if this is later).
  int minutesSince(WallTime other) => _utc.difference(other._utc).inMinutes;

  /// Whether both have the same date.
  bool sameDate(WallTime other) =>
      year == other.year && month == other.month && day == other.day;

  /// ISO 8601 without zone: `2026-10-15` or `2026-10-15T10:00`.
  String toIso() {
    final d = '$year-${_two(month)}-${_two(day)}';
    return hasTime ? '${d}T${_two(hour!)}:${_two(minute!)}' : d;
  }

  @override
  int compareTo(WallTime other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is WallTime &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute);

  @override
  String toString() => toIso();
}

String _two(int n) => n.toString().padLeft(2, '0');

final _isoValue = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?'
  r'\s*(Z|z|[+-]\d{2}(?::?\d{2})?)?$',
);

final _relative = RegExp(
  r'^(today|tomorrow|yesterday|[+-]\d+d|mon|tue|wed|thu|fri|sat|sun|'
  r'\d{4}-\d{2}-\d{2})?\s*(?:(\d{1,2}):(\d{2}))?$',
);

const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// The fixed „now“ of an eval run in a time zone (concept: „Fester
/// heute-Zeitpunkt pro Lauf“). Resolves relative specs like `+1d 10:00`
/// and reads date-times written by the model as wall times in that zone.
final class EvalTime {
  /// Creates the time from a wall time [now] in [timeZone] (IANA name).
  EvalTime(this.now, this.timeZone) : _location = timeZoneLocation(timeZone);

  /// Parses `2026-10-14T09:00` as wall time in [timeZone].
  /// Throws [FormatException] if malformed.
  factory EvalTime.parse(String now, String timeZone) {
    final wall = parseWallTime(now, timeZone: timeZone);
    if (wall == null || !wall.hasTime) {
      throw FormatException('Ungültiger Zeitpunkt „$now“ (2026-10-14T09:00)');
    }
    return EvalTime(wall, timeZone);
  }

  /// Wall time of „now“.
  final WallTime now;

  /// IANA time zone of the run.
  final String timeZone;

  final tz.Location _location;

  /// „Now“ as an instant whose fields show the wall time in [timeZone]
  /// (`tz.TZDateTime`), for the agent's clock.
  DateTime get instant => tz.TZDateTime(
    _location,
    now.year,
    now.month,
    now.day,
    now.hour!,
    now.minute!,
  );

  /// Resolves a relative spec against [now].
  ///
  /// Grammar: `[day] [HH:MM]` with day = `today`, `tomorrow`, `yesterday`,
  /// `+Nd`, `-Nd`, a weekday `mon`…`sun` (next one after today, 1–7 days
  /// ahead) or an absolute `YYYY-MM-DD`; without day it means today.
  /// Without time the result is a date. Throws [FormatException].
  WallTime resolve(String spec) {
    final m = _relative.firstMatch(spec.trim().toLowerCase());
    if (m == null || (m[1] == null && m[2] == null)) {
      throw FormatException('Ungültige Zeitangabe „$spec“');
    }
    final base = DateTime.utc(now.year, now.month, now.day);
    final day = m[1];
    final DateTime date;
    if (day == null || day == 'today') {
      date = base;
    } else if (day == 'tomorrow') {
      date = base.add(const Duration(days: 1));
    } else if (day == 'yesterday') {
      date = base.subtract(const Duration(days: 1));
    } else if (_weekdays.contains(day)) {
      final target = _weekdays.indexOf(day) + 1;
      var ahead = (target - base.weekday) % 7;
      if (ahead == 0) ahead = 7;
      date = base.add(Duration(days: ahead));
    } else if (day.startsWith('+') || day.startsWith('-')) {
      date = base.add(
        Duration(days: int.parse(day.substring(0, day.length - 1))),
      );
    } else {
      final parsed = parseWallTime(day, timeZone: timeZone);
      if (parsed == null) throw FormatException('Ungültiges Datum „$spec“');
      date = DateTime.utc(parsed.year, parsed.month, parsed.day);
    }
    if (m[2] == null) return WallTime(date.year, date.month, date.day);
    final hour = int.parse(m[2]!);
    final minute = int.parse(m[3]!);
    if (hour > 23 || minute > 59) {
      throw FormatException('Ungültige Uhrzeit in „$spec“');
    }
    return WallTime(date.year, date.month, date.day, hour, minute);
  }

  /// Reads an ISO date or date-time written by the model as wall time in
  /// [timeZone]; `null` if it is no ISO value.
  WallTime? read(String value) => parseWallTime(value, timeZone: timeZone);
}

/// Parses an ISO 8601 date or date-time; with an offset (`Z`, `+02:00`) the
/// instant is converted to the wall time in [timeZone]. Seconds are
/// ignored. Returns `null` if [value] is not ISO or out of range.
WallTime? parseWallTime(String value, {required String timeZone}) {
  final m = _isoValue.firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final check = DateTime.utc(y, mo, d);
  if (check.month != mo || check.day != d) return null;
  if (m[4] == null) return WallTime(y, mo, d);
  final h = int.parse(m[4]!);
  final mi = int.parse(m[5]!);
  if (h > 23 || mi > 59) return null;
  final o = m[7];
  if (o == null) return WallTime(y, mo, d, h, mi);
  var offset = Duration.zero;
  if (o != 'Z' && o != 'z') {
    final digits = o.substring(1).replaceAll(':', '');
    final total = Duration(
      hours: int.parse(digits.substring(0, 2)),
      minutes: digits.length > 2 ? int.parse(digits.substring(2)) : 0,
    );
    offset = o.startsWith('-') ? -total : total;
  }
  final instant = DateTime.utc(y, mo, d, h, mi).subtract(offset);
  final local = tz.TZDateTime.from(instant, timeZoneLocation(timeZone));
  return WallTime(local.year, local.month, local.day, local.hour, local.minute);
}
