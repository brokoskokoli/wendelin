import '../design/icons.dart';

/// „Heute · 08:12“, „Gestern · 21:05“ or „12.10. · 08:12“.
String sessionLabel(DateTime at, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final date = switch (diff) {
    0 => 'Heute',
    1 => 'Gestern',
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
  'lists' => WIcons.cart,
  'web' => WIcons.globe,
  'obsidian' => WIcons.note,
  'bring' => WIcons.cart,
  'spotify' => WIcons.music,
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
({String title, String yes, String no}) confirmationTexts(String toolName) {
  final action = toolName.contains('__')
      ? toolName.substring(toolName.indexOf('__') + 2)
      : toolName;
  if (toolName == 'calendar__delete_event') {
    return (title: 'Termin löschen?', yes: 'Ja, löschen', no: 'Nein, behalten');
  }
  if (RegExp('delete|remove|clear|forget').hasMatch(action)) {
    return (
      title: 'Wirklich löschen?',
      yes: 'Ja, löschen',
      no: 'Nein, behalten',
    );
  }
  return (title: 'Soll ich das tun?', yes: 'Ja, ausführen', no: 'Nein');
}
