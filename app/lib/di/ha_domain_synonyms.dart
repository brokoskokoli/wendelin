/// Generic words per Home Assistant domain and language (WP191), handed to
/// the recognizer as hint terms next to the entity names, so „Schalte die
/// Lampe ein“ works for a light that is called „Deckenlicht“. One table,
/// extend it here: key = HA domain (`light`), value = words per language.
const haDomainSynonyms = <String, Map<String, List<String>>>{
  'light': {
    'de': ['Lampe', 'Licht'],
    'en': ['lamp', 'light'],
    'fr': ['lampe', 'lumière'],
  },
  'cover': {
    'de': ['Rollo', 'Rollladen', 'Jalousie'],
    'en': ['blind', 'shutter', 'curtain'],
    'fr': ['volet', 'store', 'rideau'],
  },
  'switch': {
    'de': ['Schalter', 'Steckdose'],
    'en': ['switch', 'socket', 'plug'],
    'fr': ['interrupteur', 'prise'],
  },
  'climate': {
    'de': ['Heizung', 'Thermostat'],
    'en': ['heating', 'thermostat'],
    'fr': ['chauffage', 'thermostat'],
  },
  'fan': {
    'de': ['Ventilator'],
    'en': ['fan'],
    'fr': ['ventilateur'],
  },
  'media_player': {
    'de': ['Fernseher', 'Lautsprecher'],
    'en': ['television', 'speaker'],
    'fr': ['télévision', 'haut-parleur'],
  },
  'lock': {
    'de': ['Schloss'],
    'en': ['lock'],
    'fr': ['serrure'],
  },
};

/// The language of the table used for [language] (`de`, `en`, `fr`); an
/// unsupported language falls back to `en`.
String haSynonymLanguage(String language) {
  final code = language.split(RegExp('[-_]')).first.toLowerCase();
  return const {'de', 'en', 'fr'}.contains(code) ? code : 'en';
}

/// The synonyms for the [domains] that occur (each word once, in table
/// order) in [language].
List<String> haSynonymsFor(Iterable<String> domains, String language) {
  final lang = haSynonymLanguage(language);
  final present = domains.toSet();
  return [
    for (final e in haDomainSynonyms.entries)
      if (present.contains(e.key)) ...?e.value[lang],
  ];
}
