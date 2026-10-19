import '../../l10n/l10n.dart';
import '../design/icons.dart';

/// „Heute · 08:12“, „Gestern · 21:05“ or „12.10. · 08:12“.
String sessionLabel(AppLocalizations l, DateTime at, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final date = switch (diff) {
    0 => l.mainToday,
    1 => l.mainYesterday,
    _ => '${two(at.day)}.${two(at.month)}.',
  };
  return '$date · ${two(at.hour)}:${two(at.minute)}';
}

/// Icon of an integration id (fallback: task).
WIconData integrationIcon(String integrationId) => switch (integrationId) {
  'calendar' => WIcons.calendar,
  'memory' => WIcons.note,
  'clipboard' => WIcons.clipboard,
  'alarms' => WIcons.alarm,
  'flashlight' => WIcons.flashlight,
  'lists' => WIcons.cart,
  'web' => WIcons.globe,
  'weather' => WIcons.waves,
  'obsidian' => WIcons.note,
  'bring' => WIcons.cart,
  'http' => WIcons.globe,
  'spotify' => WIcons.music,
  'media' => WIcons.music,
  'location' || 'maps' => WIcons.globe,
  'ha' => WIcons.home,
  _ => WIcons.task,
};

/// Title and detail of a tool card from a summary like
/// „Termin angelegt: Tauchen, Di 10:00“ (split at the first „: “).
(String, String) splitSummary(String? summary, String fallback) {
  final s = summary ?? fallback;
  final i = s.indexOf(': ');
  return i < 0 ? (s, '') : (s.substring(0, i), s.substring(i + 2));
}

/// Texts of the confirmation card for [toolName].
({String title, String yes, String no}) confirmationTexts(
  AppLocalizations l,
  String toolName,
) {
  final action = toolName.contains('__')
      ? toolName.substring(toolName.indexOf('__') + 2)
      : toolName;
  if (toolName == 'calendar__delete_event') {
    return (
      title: l.mainDeleteEventTitle,
      yes: l.mainYesDelete,
      no: l.mainNoKeep,
    );
  }
  if (RegExp('delete|remove|clear|forget').hasMatch(action)) {
    return (
      title: l.mainReallyDeleteTitle,
      yes: l.mainYesDelete,
      no: l.mainNoKeep,
    );
  }
  return (title: l.mainShouldIDoThat, yes: l.mainYesDoIt, no: l.no);
}
