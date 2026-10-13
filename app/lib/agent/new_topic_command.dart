/// Whether [text] consists only of a „new conversation“ phrase (de/fr/en),
/// optionally with filler words („bitte“, „okay“). Longer sentences such as
/// „vergiss, dass ich morgen …“ are normal requests.
bool isNewTopicPhrase(String text) {
  final words = _normalize(text);
  if (words.isEmpty) return false;
  final core = [
    for (final w in words)
      if (!_fillers.contains(w)) w,
  ].join(' ');
  return _phrases.contains(core);
}

List<String> _normalize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[’\'-]'), ' ')
    .replaceAll(RegExp(r'[^a-zäöüßéèêàâçîïôùûœ ]'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .toList();

const _fillers = {
  // de
  'bitte', 'okay', 'ok', 'ähm', 'also', 'mal', 'hey', 'jetzt', 'wendelin',
  // fr
  'stp', 'svp', 's', 'il', 'te', 'vous', 'plaît', 'plait', 'alors',
  // en
  'please', 'now', 'just',
};

const _phrases = {
  // de
  'neues thema', 'neues gespräch', 'neue unterhaltung', 'vergiss das',
  'fang neu an', 'fange neu an',
  // fr
  'nouveau sujet', 'nouvelle conversation', 'oublie ça', 'oublie ca',
  // en
  'new topic', 'new conversation', 'forget that', 'start over',
};
