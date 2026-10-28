import 'language.dart';

/// English confirmation sentences (WP122). See `README.md`.
const confirmationEn = _En();

final class _En extends ConfirmationLanguage {
  const _En();

  static const _dayNames = [
    'Mondays',
    'Tuesdays',
    'Wednesdays',
    'Thursdays',
    'Fridays',
    'Saturdays',
    'Sundays',
  ];
  static const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Map<String, String> get templates => const {
    'alarm.set': 'The alarm is set for {time} ({days}).',
    'call.started': 'The call to {name} has been started.',
    'event.created': 'The event “{title}” is in your calendar: {when}.',
    'flashlight.off': 'The flashlight is off.',
    'flashlight.on': 'The flashlight is on.',
    'ha.brightness': 'I set {device} to {value} percent brightness.',
    'ha.cover.close': 'I closed {device}.',
    'ha.cover.open': 'I opened {device}.',
    'ha.cover.position': 'I set {device} to {value} percent.',
    'ha.cover.stop': 'I stopped {device}.',
    'ha.off': 'I turned off {device}.',
    'ha.on': 'I turned on {device}.',
    'ha.temperature': 'I set {device} to {value} degrees.',
    'list.added': 'I added {items} to the list {list}.',
    'list.done': 'I checked off {item} on the list {list}.',
    'list.present': 'I found {items} already on the list {list}.',
    'list.added.default': 'I added {items} to the shopping list.',
    'list.done.default': 'I checked off {item}.',
    'list.present.default': 'I found {items} already on the shopping list.',
    'media.next': 'I skipped to the next track.',
    'media.pause': 'Playback is paused.',
    'media.play': 'Playback is running.',
    'media.previous': 'I went back to the previous track.',
    'memory.saved': 'I have made a note of it.',
    'note.appended': 'The text is now in the note “{note}”.',
    'navigation.started': 'Navigation to {name} started.',
    'note.created': 'The note “{note}” has been created.',
    'sms.sent': 'The text message to {name} has been sent.',
    'station.started': 'Station mode is on.',
    'task.added': 'The task “{title}” is now on the list {list}.',
    'task.addedPlain': 'The task “{title}” is added.',
    'task.done': 'The task “{title}” is done.',
    'timer.set': 'The timer is running: {duration}.',
  };

  @override
  String joinList(List<String> items) => switch (items.length) {
    0 => '',
    1 => items.first,
    2 => '${items.first} and ${items.last}',
    _ => '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
  };

  @override
  String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return joinList([
      if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
      if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
      if (s > 0 || d == Duration.zero) '$s ${s == 1 ? 'second' : 'seconds'}',
    ]);
  }

  @override
  String days(Set<int> days) {
    final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
    if (sorted.isEmpty) return 'once';
    if (sorted.length == 7) return 'every day';
    if (sorted.length == 5 && sorted.last == 5) return 'Monday to Friday';
    return 'on ${joinList([for (final d in sorted) _dayNames[d - 1]])}';
  }

  @override
  String dateTime(DateTime t) =>
      '${_shortDays[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}, '
      '${clock(t)}';
}
