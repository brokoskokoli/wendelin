import 'language.dart';

/// French confirmation sentences (WP122). See `README.md`.
const confirmationFr = _Fr();

final class _Fr extends ConfirmationLanguage {
  const _Fr();

  static const _dayNames = [
    'le lundi',
    'le mardi',
    'le mercredi',
    'le jeudi',
    'le vendredi',
    'le samedi',
    'le dimanche',
  ];
  static const _shortDays = [
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];
  static const _months = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  @override
  Map<String, String> get templates => const {
    'alarm.set': 'Le réveil est réglé à {time} ({days}).',
    'call.started': 'L’appel vers {name} est lancé.',
    'event.created': 'Le rendez-vous « {title} » est ajouté : {when}.',
    'flashlight.off': 'La lampe de poche est éteinte.',
    'flashlight.on': 'La lampe de poche est allumée.',
    'ha.off': 'J’ai éteint {device}.',
    'ha.on': 'J’ai allumé {device}.',
    'list.added': 'J’ai ajouté {items} à la liste {list}.',
    'list.done': 'J’ai coché {item} sur la liste {list}.',
    'list.present': 'J’ai déjà trouvé {items} sur la liste {list}.',
    'list.added.default': 'J’ai ajouté {items} à la liste de courses.',
    'list.done.default': 'J’ai coché {item}.',
    'list.present.default': 'J’ai déjà trouvé {items} sur la liste de courses.',
    'media.next': 'Je suis passé au titre suivant.',
    'media.pause': 'La lecture est en pause.',
    'media.play': 'La lecture est en cours.',
    'media.previous': 'Je suis revenu au titre précédent.',
    'memory.saved': 'Je l’ai noté.',
    'note.appended': 'Le texte figure maintenant dans la note « {note} ».',
    'note.created': 'La note « {note} » est créée.',
    'sms.sent': 'Le SMS à {name} a été envoyé.',
    'station.started': 'Le mode station est activé.',
    'task.added': 'La tâche « {title} » est maintenant sur la liste {list}.',
    'task.addedPlain': 'La tâche « {title} » est ajoutée.',
    'task.done': 'La tâche « {title} » est terminée.',
    'timer.set': 'Le minuteur est lancé : {duration}.',
  };

  @override
  String joinList(List<String> items) => switch (items.length) {
    0 => '',
    1 => items.first,
    _ => '${items.sublist(0, items.length - 1).join(', ')} et ${items.last}',
  };

  @override
  String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return joinList([
      if (h > 0) '$h ${h == 1 ? 'heure' : 'heures'}',
      if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
      if (s > 0 || d == Duration.zero) '$s ${s == 1 ? 'seconde' : 'secondes'}',
    ]);
  }

  @override
  String days(Set<int> days) {
    final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
    if (sorted.isEmpty) return 'une seule fois';
    if (sorted.length == 7) return 'tous les jours';
    if (sorted.length == 5 && sorted.last == 5) return 'du lundi au vendredi';
    return joinList([for (final d in sorted) _dayNames[d - 1]]);
  }

  @override
  String dateTime(DateTime t) =>
      '${_shortDays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, '
      '${clock(t)}';
}
