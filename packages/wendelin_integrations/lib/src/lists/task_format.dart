// Obsidian-Tasks-compatible metadata in list item text: `Milch holen
// ⏰ 14:30 ⏫ 📅 2026-10-20`. Obsidian Tasks parses its markers only from the
// end of the line, so our own `⏰` goes before them (the parser reads both
// orders). Parsing never changes the stored line; the writer only appends
// tokens, so unknown tokens (🔁, ⏳, #tags …) survive.

import '../common/time.dart';

/// Task priority, mapped to the Obsidian Tasks emojis.
enum TaskPriority {
  /// 🔺
  highest('🔺', 'highest'),

  /// ⏫
  high('⏫', 'high'),

  /// 🔼
  medium('🔼', 'medium'),

  /// 🔽
  low('🔽', 'low'),

  /// ⏬
  lowest('⏬', 'lowest');

  const TaskPriority(this.emoji, this.id);

  /// Emoji written to the file.
  final String emoji;

  /// Name used in tool arguments.
  final String id;

  /// The priority named [id], or `null`.
  static TaskPriority? byId(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final _dueToken = RegExp(r'📅\s*(\d{4}-\d{2}-\d{2})');
final _timeToken = RegExp(r'⏰\s*(\d{2}):(\d{2})');
final _doneToken = RegExp(r'✅\s*(\d{4}-\d{2}-\d{2})');
final _prioTokens = RegExp('🔺|⏫|🔼|🔽|⏬');
final _spaces = RegExp(r'\s{2,}');

LocalDate? _date(String iso) {
  final y = int.parse(iso.substring(0, 4));
  final m = int.parse(iso.substring(5, 7));
  final d = int.parse(iso.substring(8, 10));
  final date = LocalDate(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

/// The recognised metadata of one item text.
final class TaskInfo {
  const TaskInfo._(
    this.title,
    this.due,
    this.minutes,
    this.priority,
    this.completed,
  );

  /// Parses [text] (the item text after the checkbox).
  factory TaskInfo.parse(String text) {
    final dueM = _dueToken.firstMatch(text);
    final timeM = _timeToken.firstMatch(text);
    final doneM = _doneToken.firstMatch(text);
    final prio = _prioTokens.firstMatch(text);
    final due = dueM == null ? null : _date(dueM[1]!);
    int? minutes;
    if (timeM != null) {
      final h = int.parse(timeM[1]!), mi = int.parse(timeM[2]!);
      if (h < 24 && mi < 60) minutes = h * 60 + mi;
    }
    final title = text
        .replaceAll(_dueToken, ' ')
        .replaceAll(_timeToken, ' ')
        .replaceAll(_doneToken, ' ')
        .replaceAll(_prioTokens, ' ')
        .replaceAll(_spaces, ' ')
        .trim();
    return TaskInfo._(
      title,
      due,
      due == null ? null : minutes,
      prio == null
          ? null
          : TaskPriority.values.firstWhere((p) => p.emoji == prio[0]),
      doneM == null ? null : _date(doneM[1]!),
    );
  }

  /// Text without the recognised tokens (what the user would say).
  final String title;

  /// Due date (`📅`), or `null`.
  final LocalDate? due;

  /// Due time as minutes after midnight (`⏰`, only with a due date).
  final int? minutes;

  /// Priority, or `null` (normal).
  final TaskPriority? priority;

  /// Completion date (`✅`), or `null`.
  final LocalDate? completed;
}

/// `HH:MM` for [minutes] after midnight.
String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// The item text for a new task: title, priority, due date, due time.
String composeTask(
  String title, {
  LocalDate? due,
  int? minutes,
  TaskPriority? priority,
}) => [
  title,
  if (due != null && minutes != null) '⏰ ${formatMinutes(minutes)}',
  ?priority?.emoji,
  if (due != null) '📅 ${due.toIso()}',
].join(' ');

/// Markers the tools must not accept inside a title (they would be read as
/// metadata or break the line's Obsidian Tasks parsing).
const taskMarkers = [
  '📅',
  '⏳',
  '🛫',
  '➕',
  '✅',
  '❌',
  '🔁',
  '⏰',
  '🔺',
  '⏫',
  '🔼',
  '🔽',
  '⏬',
];
