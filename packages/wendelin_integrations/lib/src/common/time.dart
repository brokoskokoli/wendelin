// Zeitzonen und ISO-8601-Hilfen für die Tools.
//
// Zeiten ohne Offset gelten in der Gerätezeitzone (`ToolContext.timeZone`,
// IANA-Name) bzw. in einer vom Nutzer genannten Zone. Dafür wird
// `package:timezone` genutzt, weil `DateTime` nur UTC und die Systemzone
// kennt und Sommerzeitwechsel korrekt behandelt werden müssen.
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'tool_args.dart';

bool _tzInitialized = false;

/// Looks up the IANA time zone [name] (e.g. `Europe/Berlin`).
///
/// Throws [InvalidArgumentsException] for unknown names. The time zone
/// database is loaded lazily on first use.
tz.Location timeZoneLocation(String name) {
  if (name == 'UTC' || name == 'Etc/UTC' || name == 'Z') return tz.UTC;
  if (!_tzInitialized) {
    tzdata.initializeTimeZones();
    _tzInitialized = true;
  }
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    throw InvalidArgumentsException('Unbekannte Zeitzone „$name“');
  }
}

/// A calendar date without time or zone (used for all-day events and day
/// iteration). Internally a UTC midnight, so arithmetic never hits DST.
final class LocalDate implements Comparable<LocalDate> {
  /// Creates the date; out-of-range values are normalized like [DateTime].
  LocalDate(int year, int month, int day)
    : _utc = DateTime.utc(year, month, day);

  /// The date of a UTC-midnight [DateTime] (all-day representation).
  LocalDate.fromUtcMidnight(DateTime utc)
    : _utc = DateTime.utc(utc.year, utc.month, utc.day);

  /// The wall-clock date of [instant] in [location].
  factory LocalDate.of(DateTime instant, tz.Location location) {
    final local = tz.TZDateTime.from(instant, location);
    return LocalDate(local.year, local.month, local.day);
  }

  final DateTime _utc;

  /// Year.
  int get year => _utc.year;

  /// Month 1–12.
  int get month => _utc.month;

  /// Day of month.
  int get day => _utc.day;

  /// ISO weekday, 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  /// The date [days] later (negative = earlier).
  LocalDate addDays(int days) => LocalDate(year, month, day + days);

  /// This date as UTC midnight (all-day event representation).
  DateTime get utcMidnight => _utc;

  /// Start of this date (00:00 wall time) in [location].
  DateTime startIn(tz.Location location) =>
      tz.TZDateTime(location, year, month, day).toUtc();

  /// Instant of the wall time [minutes] after midnight on this date in
  /// [location]; `24 * 60` is the next midnight.
  DateTime atMinutes(int minutes, tz.Location location) => tz.TZDateTime(
    location,
    year,
    month,
    day,
    minutes ~/ 60,
    minutes % 60,
  ).toUtc();

  /// `YYYY-MM-DD`.
  String toIso() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  @override
  int compareTo(LocalDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) => other is LocalDate && other._utc == _utc;

  @override
  int get hashCode => _utc.hashCode;

  @override
  String toString() => toIso();
}

final _isoPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?'
  r'\s*(Z|z|[+-]\d{2}(?::?\d{2})?)?$',
);

/// An ISO 8601 date or date-time as written by the model.
final class IsoInput {
  const IsoInput._(this.date, this.minutes, this.second, this.offset);

  /// Parses `2026-10-15`, `2026-10-15T10:00`, `2026-10-15T10:00:00`,
  /// `2026-10-15 10:00`, optionally with `Z` or `+02:00`.
  ///
  /// Throws [InvalidArgumentsException] naming [field] if malformed.
  factory IsoInput.parse(String input, String field) {
    final m = _isoPattern.firstMatch(input.trim());
    InvalidArgumentsException bad() => InvalidArgumentsException(
      '„$field“ ist kein gültiges Datum im Format 2026-10-15T10:00 '
      '(war „$input“)',
    );
    if (m == null) throw bad();
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    final date = LocalDate(y, mo, d);
    if (date.year != y || date.month != mo || date.day != d) throw bad();
    int? minutes;
    var second = 0;
    if (m[4] != null) {
      final h = int.parse(m[4]!);
      final mi = int.parse(m[5]!);
      second = m[6] == null ? 0 : int.parse(m[6]!);
      if (h > 23 || mi > 59 || second > 59) throw bad();
      minutes = h * 60 + mi;
    }
    Duration? offset;
    final o = m[7];
    if (o != null) {
      if (o == 'Z' || o == 'z') {
        offset = Duration.zero;
      } else {
        final digits = o.substring(1).replaceAll(':', '');
        final oh = int.parse(digits.substring(0, 2));
        final om = digits.length > 2 ? int.parse(digits.substring(2)) : 0;
        if (oh > 18 || om > 59) throw bad();
        final total = Duration(hours: oh, minutes: om);
        offset = o.startsWith('-') ? -total : total;
      }
    }
    return IsoInput._(date, minutes, second, offset);
  }

  /// The date part.
  final LocalDate date;

  /// Minutes after midnight, or `null` for a date without time.
  final int? minutes;

  /// Seconds of the time part.
  final int second;

  /// Explicit UTC offset, or `null` (= wall time in the target zone).
  final Duration? offset;

  /// Whether a time of day was given.
  bool get hasTime => minutes != null;

  /// The instant (UTC): with an explicit [offset] that offset applies,
  /// otherwise the wall time is interpreted in [location]. A date without
  /// time means 00:00.
  ///
  /// Wall times in a DST gap are moved forward by the gap; ambiguous wall
  /// times in the repeated hour resolve as `package:timezone` does.
  DateTime instantIn(tz.Location location) {
    final mins = minutes ?? 0;
    if (offset != null) {
      return DateTime.utc(
        date.year,
        date.month,
        date.day,
        mins ~/ 60,
        mins % 60,
        second,
      ).subtract(offset!);
    }
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      mins ~/ 60,
      mins % 60,
      second,
    ).toUtc();
  }
}

/// Parses `HH:MM` (00:00–24:00) to minutes after midnight.
int parseClockTime(String input, String field) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input.trim());
  final h = m == null ? -1 : int.parse(m[1]!);
  final mi = m == null ? -1 : int.parse(m[2]!);
  if (m == null || h > 24 || mi > 59 || (h == 24 && mi != 0)) {
    throw InvalidArgumentsException(
      '„$field“ muss eine Uhrzeit wie 08:30 sein (war „$input“)',
    );
  }
  return h * 60 + mi;
}

/// [instant] as ISO 8601 with the offset valid in [location], e.g.
/// `2026-10-15T10:00:00+02:00`.
String isoInZone(DateTime instant, tz.Location location) {
  final l = tz.TZDateTime.from(instant, location);
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  return '${LocalDate(l.year, l.month, l.day).toIso()}'
      'T${_pad(l.hour, 2)}:${_pad(l.minute, 2)}:${_pad(l.second, 2)}'
      '$sign${_pad(abs.inHours, 2)}:${_pad(abs.inMinutes % 60, 2)}';
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// German short day, e.g. `Do 15.10.`.
String germanDay(LocalDate date) =>
    '${_weekdays[date.weekday - 1]} ${_pad(date.day, 2)}.${_pad(date.month, 2)}.';

/// German wall time of [instant] in [location], e.g. `10:00`.
String germanClock(DateTime instant, tz.Location location) {
  final l = tz.TZDateTime.from(instant, location);
  return '${_pad(l.hour, 2)}:${_pad(l.minute, 2)}';
}

/// German day and time of [instant], e.g. `Do 15.10. 10:00`.
String germanDateTime(DateTime instant, tz.Location location) =>
    '${germanDay(LocalDate.of(instant, location))} '
    '${germanClock(instant, location)}';

/// German span: `Do 15.10. 10:00–11:00`, across days
/// `Do 15.10. 22:00 – Fr 16.10. 01:00`.
String germanSpan(DateTime start, DateTime end, tz.Location location) {
  final sd = LocalDate.of(start, location);
  final ed = LocalDate.of(end, location);
  if (sd == ed) {
    return '${germanDay(sd)} ${germanClock(start, location)}–'
        '${germanClock(end, location)}';
  }
  return '${germanDateTime(start, location)} – '
      '${germanDateTime(end, location)}';
}

/// German span of all-day dates [first]..[last] (inclusive).
String germanAllDaySpan(LocalDate first, LocalDate last) => first == last
    ? '${germanDay(first)} (ganztägig)'
    : '${germanDay(first)}–${germanDay(last)} (ganztägig)';

String _pad(int v, int width) => v.toString().padLeft(width, '0');
