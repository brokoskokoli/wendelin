import 'language.dart';

/// German confirmation sentences (WP122). See `README.md`.
const confirmationDe = _De();

final class _De extends ConfirmationLanguage {
  const _De();

  static const _dayNames = [
    'montags',
    'dienstags',
    'mittwochs',
    'donnerstags',
    'freitags',
    'samstags',
    'sonntags',
  ];
  static const _shortDays = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];

  @override
  Map<String, String> get templates => const {
    'alarm.set': 'Der Wecker ist auf {time} Uhr gestellt ({days}).',
    'call.started': 'Der Anruf bei {name} wurde gestartet.',
    'event.created': 'Der Termin „{title}“ ist eingetragen: {when}.',
    'flashlight.off': 'Die Taschenlampe ist aus.',
    'flashlight.on': 'Die Taschenlampe ist an.',
    'ha.off': '{device} ist aus.',
    'ha.on': '{device} ist an.',
    'list.added': '{items} stehen jetzt auf der Liste {list}.',
    'list.added#one': '{items} steht jetzt auf der Liste {list}.',
    'list.done': '{item} ist auf der Liste {list} abgehakt.',
    'list.present': '{items} stehen schon auf der Liste {list}.',
    'list.present#one': '{items} steht schon auf der Liste {list}.',
    'media.next': 'Ich habe zum nächsten Titel weitergeschaltet.',
    'media.pause': 'Die Wiedergabe ist pausiert.',
    'media.play': 'Die Wiedergabe läuft.',
    'media.previous': 'Ich habe zum vorherigen Titel zurückgeschaltet.',
    'memory.saved': 'Ich habe es mir gemerkt.',
    'note.appended': 'Der Text steht jetzt in der Notiz „{note}“.',
    'note.created': 'Die Notiz „{note}“ ist angelegt.',
    'sms.sent': 'Die SMS an {name} wurde gesendet.',
    'spotify.playing': 'Es spielt jetzt {label}.',
    'station.started': 'Der Stationsmodus ist an.',
    'task.added': 'Die Aufgabe „{title}“ steht jetzt auf der Liste {list}.',
    'task.done': 'Die Aufgabe „{title}“ ist erledigt.',
    'timer.set': 'Der Timer läuft: {duration}.',
  };

  @override
  String joinList(List<String> items) => switch (items.length) {
    0 => '',
    1 => items.first,
    _ => '${items.sublist(0, items.length - 1).join(', ')} und ${items.last}',
  };

  @override
  String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return joinList([
      if (h > 0) '$h ${h == 1 ? 'Stunde' : 'Stunden'}',
      if (m > 0) '$m ${m == 1 ? 'Minute' : 'Minuten'}',
      if (s > 0 || d == Duration.zero) '$s ${s == 1 ? 'Sekunde' : 'Sekunden'}',
    ]);
  }

  @override
  String days(Set<int> days) {
    final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
    if (sorted.isEmpty) return 'einmalig';
    if (sorted.length == 7) return 'täglich';
    if (sorted.length == 5 && sorted.last == 5) return 'montags bis freitags';
    return joinList([for (final d in sorted) _dayNames[d - 1]]);
  }

  @override
  String dateTime(DateTime t) =>
      '${_shortDays[t.weekday - 1]} ${t.day}.${t.month}., ${clock(t)} Uhr';
}
