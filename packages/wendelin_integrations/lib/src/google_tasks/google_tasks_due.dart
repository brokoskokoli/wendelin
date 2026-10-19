import '../common/time.dart';
import '../common/tool_args.dart';

const _weekdays = <String, int>{
  'montag': 1,
  'monday': 1,
  'dienstag': 2,
  'tuesday': 2,
  'mittwoch': 3,
  'wednesday': 3,
  'donnerstag': 4,
  'thursday': 4,
  'freitag': 5,
  'friday': 5,
  'samstag': 6,
  'sonnabend': 6,
  'saturday': 6,
  'sonntag': 7,
  'sunday': 7,
};

/// Result of [resolveGoogleDue]: the date and whether a time was dropped.
typedef GoogleDue = ({LocalDate date, bool timeDropped});

/// Resolves the user's [input] to a date on the device, relative to
/// [today] (Google Tasks stores a date only, so there is no server-side
/// language). Understands ISO (`2026-10-20`, a time or zone is dropped),
/// `heute/today`, `morgen/tomorrow`, `übermorgen`, `in 3 Tagen/days`,
/// `in 2 Wochen/weeks`, `nächste Woche/next week`, weekdays (German or
/// English, with `am/on/nächsten/next`; the same weekday means next week)
/// and `20.10.` / `20.10.2026` (without year: the next such day).
///
/// Throws [InvalidArgumentsException] with a hint to use `2026-10-20`.
GoogleDue resolveGoogleDue(String input, LocalDate today) {
  final text = input.trim().toLowerCase();
  InvalidArgumentsException bad() => InvalidArgumentsException(
    '„due“ nicht verständlich (war „$input“); bitte als Datum 2026-10-20 '
    'angeben',
  );
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
    final iso = IsoInput.parse(input, 'due');
    return (date: iso.date, timeDropped: iso.minutes != null);
  }
  LocalDate day(int add) => today.addDays(add);
  // A trailing time („morgen 9 Uhr“) is dropped, the date part counts.
  final timeRe = RegExp(
    r'\s+(um|at|@)?\s*\d{1,2}([:.]\d{2})?\s*(uhr|am|pm|h)?$',
  );
  var core = text;
  var dropped = false;
  // Not for „20.10.“ style dates, which end in digits themselves.
  if (!RegExp(r'^\d{1,2}\.\d{1,2}\.?(\d{2,4})?$').hasMatch(core)) {
    final m = timeRe.firstMatch(core);
    if (m != null && core.substring(0, m.start).trim().isNotEmpty) {
      core = core.substring(0, m.start).trim();
      dropped = true;
    }
  }
  GoogleDue ok(LocalDate d) => (date: d, timeDropped: dropped);
  switch (core) {
    case 'heute' || 'today':
      return ok(day(0));
    case 'morgen' || 'tomorrow':
      return ok(day(1));
    case 'übermorgen' || 'uebermorgen' || 'day after tomorrow':
      return ok(day(2));
    case 'nächste woche' || 'naechste woche' || 'nächster woche' || 'next week':
      return ok(day(7));
  }
  final rel = RegExp(
    r'^(?:in )(\d{1,3}) (tag|tage|tagen|day|days|woche|wochen|week|weeks)$',
  ).firstMatch(core);
  if (rel != null) {
    final n = int.parse(rel[1]!);
    final weeks = rel[2]!.startsWith('w');
    return ok(day(weeks ? n * 7 : n));
  }
  final wd = RegExp(
    r'^(?:(?:am|on|next|nächsten|naechsten|nächster|kommenden) )?([a-zä]+)$',
  ).firstMatch(core);
  final weekday = wd == null ? null : _weekdays[wd[1]];
  if (weekday != null) {
    var add = (weekday - today.weekday) % 7;
    if (add == 0) add = 7;
    return ok(day(add));
  }
  final de = RegExp(r'^(\d{1,2})\.(\d{1,2})\.?(?:(\d{2}|\d{4}))?$')
      .firstMatch(core);
  if (de != null) {
    final d = int.parse(de[1]!);
    final mo = int.parse(de[2]!);
    var y = today.year;
    var explicit = false;
    if (de[3] != null) {
      y = int.parse(de[3]!);
      if (y < 100) y += 2000;
      explicit = true;
    }
    var date = LocalDate(y, mo, d);
    if (date.month != mo || date.day != d) throw bad();
    if (!explicit && date.compareTo(today) < 0) {
      date = LocalDate(y + 1, mo, d);
      if (date.month != mo || date.day != d) throw bad();
    }
    return ok(date);
  }
  throw bad();
}
