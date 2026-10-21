/// The confirmation templates and formats of one language (WP122).
abstract class ConfirmationLanguage {
  /// Const base constructor.
  const ConfirmationLanguage();

  /// Template per key; `{name}` is a placeholder. A key with `#one` is the
  /// singular variant. Every language has the same keys (test).
  Map<String, String> get templates;

  /// „A, B und C“.
  String joinList(List<String> items);

  /// Spoken length, e.g. „10 Minuten“.
  String duration(Duration d);

  /// Repeat days (1 = Monday), e.g. „montags bis freitags“; empty = once.
  String days(Set<int> days);

  /// Wall-clock date and time, e.g. „Di., 21.10. um 10:00“.
  String dateTime(DateTime t);

  /// [value] as text: strings as they are, other types per language.
  String format(Object value) => switch (value) {
    final String s => s,
    final int n => '$n',
    final List<String> l => joinList(l),
    final Duration d => duration(d),
    final Set<int> d => days(d),
    final DateTime t => dateTime(t),
    _ => '$value',
  };
}

/// `HH:MM` with leading zeros.
String clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
