import 'package:meta/meta.dart';

import '../common/time.dart';
import 'vault_path.dart';

/// Daily-note settings, as in Obsidian's core plugin „Daily notes“.
@immutable
final class DailyNoteSettings {
  /// Creates the settings.
  const DailyNoteSettings({
    this.folder = '',
    this.format = 'YYYY-MM-DD',
    this.template,
  });

  /// Folder for new daily notes (vault-relative, `''` = root).
  final String folder;

  /// File name as Moment.js date format; may contain `/` for sub-folders
  /// (`YYYY/MM/YYYY-MM-DD`).
  final String format;

  /// Template note (vault-relative), or `null`.
  final String? template;

  /// Vault path of the daily note for [date] (with `.md`).
  String pathFor(LocalDate date, {String locale = 'de'}) {
    final name = formatMomentDate(format, date, locale: locale);
    return VaultPath.newNote(VaultPath.join(folder.trim(), name));
  }

  @override
  bool operator ==(Object other) =>
      other is DailyNoteSettings &&
      other.folder == folder &&
      other.format == format &&
      other.template == template;

  @override
  int get hashCode => Object.hash(folder, format, template);
}

const _months = {
  'de': [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', //
    'August', 'September', 'Oktober', 'November', 'Dezember',
  ],
  'en': [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ],
  'fr': [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', //
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ],
};

const _monthsShort = {
  'de': [
    'Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', //
    'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.',
  ],
  'en': [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', //
    'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ],
  'fr': [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', //
    'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ],
};

// Montag zuerst (ISO-Wochentag 1).
const _days = {
  'de': [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', //
    'Samstag', 'Sonntag',
  ],
  'en': [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', //
    'Saturday', 'Sunday',
  ],
  'fr': [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ],
};

const _daysShort = {
  'de': ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'],
  'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  'fr': ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
};

const _daysMin = {
  'de': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  'en': ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
  'fr': ['lu', 'ma', 'me', 'je', 've', 'sa', 'di'],
};

final _token = RegExp(
  r'\[[^\]]*\]|YYYY|YY|GGGG|gggg|Q|MMMM|MMM|MM|M|DDDD|DDD|DD|Do|D|'
  r'dddd|ddd|dd|d|E|WW|W|ww|w|HH|H|hh|h|mm|m|ss|s|A|a',
);

String _pad(int v, int width) => v.toString().padLeft(width, '0');

/// ISO week number and week-based year of [d].
({int week, int year}) isoWeek(LocalDate d) {
  final thursday = d.addDays(4 - d.weekday);
  final jan1 = LocalDate(thursday.year, 1, 1);
  final days = thursday.utcMidnight.difference(jan1.utcMidnight);
  return (week: days.inDays ~/ 7 + 1, year: thursday.year);
}

String _ordinal(int day, String locale) => switch (locale) {
  'en' =>
    '$day${switch (day) {
      1 || 21 || 31 => 'st',
      2 || 22 => 'nd',
      3 || 23 => 'rd',
      _ => 'th',
    }}',
  'fr' => day == 1 ? '1er' : '$day',
  _ => '$day.',
};

/// Formats [date] (and optionally the wall time [minutes] after midnight)
/// with the Moment.js tokens Obsidian uses: `YYYY YY Q MMMM MMM MM M DDDD
/// DDD DD Do D dddd ddd dd d E W WW w ww GGGG gggg HH H hh h mm m ss s A a`
/// and `[literal]`. Week tokens are ISO weeks. [locale] (`de`, `en`, `fr`)
/// picks month and weekday names; others fall back to `de`.
String formatMomentDate(
  String format,
  LocalDate date, {
  String locale = 'de',
  int minutes = 0,
}) {
  final lang = _months.containsKey(locale) ? locale : 'de';
  final week = isoWeek(date);
  final dayOfYear =
      date.utcMidnight
          .difference(LocalDate(date.year, 1, 1).utcMidnight)
          .inDays +
      1;
  final hour = minutes ~/ 60;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return format.replaceAllMapped(_token, (m) {
    final t = m[0]!;
    if (t.startsWith('[')) return t.substring(1, t.length - 1);
    return switch (t) {
      'YYYY' => _pad(date.year, 4),
      'YY' => _pad(date.year % 100, 2),
      'GGGG' || 'gggg' => _pad(week.year, 4),
      'Q' => '${(date.month - 1) ~/ 3 + 1}',
      'MMMM' => _months[lang]![date.month - 1],
      'MMM' => _monthsShort[lang]![date.month - 1],
      'MM' => _pad(date.month, 2),
      'M' => '${date.month}',
      'DDDD' => _pad(dayOfYear, 3),
      'DDD' => '$dayOfYear',
      'DD' => _pad(date.day, 2),
      'Do' => _ordinal(date.day, lang),
      'D' => '${date.day}',
      'dddd' => _days[lang]![date.weekday - 1],
      'ddd' => _daysShort[lang]![date.weekday - 1],
      'dd' => _daysMin[lang]![date.weekday - 1],
      'd' => '${date.weekday % 7}',
      'E' => '${date.weekday}',
      'WW' || 'ww' => _pad(week.week, 2),
      'W' || 'w' => '${week.week}',
      'HH' => _pad(hour, 2),
      'H' => '$hour',
      'hh' => _pad(h12, 2),
      'h' => '$h12',
      'mm' => _pad(minutes % 60, 2),
      'm' => '${minutes % 60}',
      'ss' => '00',
      's' => '0',
      'A' => hour < 12 ? 'AM' : 'PM',
      _ => hour < 12 ? 'am' : 'pm',
    };
  });
}

/// Fills an Obsidian template: `{{title}}`, `{{date}}` (`YYYY-MM-DD`),
/// `{{time}}` (`HH:mm`) and `{{date:FORMAT}}` / `{{time:FORMAT}}` (also
/// with spaces inside the braces). Unknown placeholders stay unchanged.
String fillTemplate(
  String template, {
  required String title,
  required LocalDate date,
  required int minutes,
  String locale = 'de',
}) => template.replaceAllMapped(
  RegExp(r'\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}', caseSensitive: false),
  (m) {
    final kind = m[1]!.toLowerCase();
    if (kind == 'title') return title;
    final fmt = m[2]?.trim();
    final format = fmt == null || fmt.isEmpty
        ? (kind == 'date' ? 'YYYY-MM-DD' : 'HH:mm')
        : fmt;
    return formatMomentDate(format, date, locale: locale, minutes: minutes);
  },
);
