/// The confirmation templates and formats of one language (WP122).
abstract class ConfirmationLanguage {
  /// Const base constructor.
  const ConfirmationLanguage();

  /// Template per key; `{name}` is a placeholder. Number-neutral wording: no
  /// verb agrees with a user word. Every language has the same keys (test).
  Map<String, String> get templates;

  /// „A, B und C“.
  String joinList(List<String> items);

  /// Spoken length, e.g. „10 Minuten“.
  String duration(Duration d);

  /// Repeat days (1 = Monday), e.g. „montags bis freitags“; empty = once.
  String days(Set<int> days);

  /// Wall-clock date and time, e.g. „Di., 21.10. um 10:00“.
  String dateTime(DateTime t);

  /// Decimal separator for numbers with a fraction (`21,5` / `21.5`).
  String get decimalSeparator => '.';

  /// [value] as text: strings as they are, other types per language.
  String format(Object value) => switch (value) {
    final String s => s,
    final int n => '$n',
    final double d => _decimal(d),
    final List<String> l => joinList(l),
    final Duration d => duration(d),
    final Set<int> d => days(d),
    final DateTime t => dateTime(t),
    _ => '$value',
  };
}

/// [d] without a trailing `.0`, with this language's decimal separator.
extension on ConfirmationLanguage {
  String _decimal(double d) {
    final t = d == d.roundToDouble() ? '${d.round()}' : '$d';
    return t.replaceAll('.', decimalSeparator);
  }
}

/// `HH:MM` with leading zeros.
String clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
