import '../ha_words.dart';

/// German words for smart-home devices and actions (WP135). Types are word
/// stems (prefix of a word), actions whole words or phrases. See README.md.
const _lightDe = <String>[
  'lampe', 'leuchte', 'licht', 'birne', 'stehlampe', 'deckenlampe', //
  'deckenlicht', 'deckenleuchte', 'tischlampe', 'nachttischlampe',
  'wandlampe', 'wandleuchte', 'spots', 'lichterkette',
];
const _coverDe = <String>[
  'rollo', 'rolladen', 'rollladen', 'jalousie', 'markise', 'raffstore', //
  'store', 'beschattung', 'sonnenschutz', 'vorhang', 'gardine', 'plissee',
  'fensterladen',
];
const _switchDe = <String>[
  'steckdose',
  'stecker',
  'zwischenstecker',
  'schalter',
];
const _climateDe = <String>[
  'heizung', 'thermostat', 'heizkorper', 'heizkoerper', 'klimaanlage', //
  'klima', 'heizlufter',
];

/// All device type stems of de (for the topic words of `ha`).
const haTypeStemsDe = <String>[
  ..._lightDe,
  ..._coverDe,
  ..._switchDe,
  ..._climateDe,
];

/// Words for de (see above).
const haWordsDe = HaWords(
  types: {
    'light': _lightDe,
    'cover': _coverDe,
    'switch': _switchDe,
    'climate': _climateDe,
  },
  // Speech-recognition slips: „Rolle“/„Rollo“, „Rollos“ heard as „Rollers“.
  recognitionErrors: {
    'cover': ['rolle', 'rolo', 'rollu', 'roller', 'rollad'],
  },
  actions: {
    HaAction.on: [
      'an', 'ein', 'anmachen', 'einschalten', 'anschalten', 'anknipsen', //
      'anwerfen', 'aktivieren', 'anlassen', 'einmachen', 'andrehen',
      'mach an', 'schalt an', 'schalte an', 'schalt ein', 'schalte ein',
    ],
    HaAction.off: [
      'aus', 'ab', 'ausmachen', 'ausschalten', 'abschalten', 'ausknipsen', //
      'deaktivieren', 'abdrehen', 'ausstellen', 'abstellen', 'mach aus',
      'schalt aus', 'schalte aus', 'schalt ab', 'schalte ab',
    ],
    HaAction.open: [
      'rauf', 'hoch', 'auf', 'aufmachen', 'offnen', 'oeffnen', 'hochfahren', //
      'hochlassen', 'hochziehen', 'raufziehen', 'raufmachen', 'raufdrehen',
      'rauffahren', 'hinauf', 'herauf', 'aufrollen', 'aufziehen', 'ausfahren',
      'oben', 'mach auf', 'mach hoch',
    ],
    HaAction.close: [
      'runter', 'herunter', 'hinunter', 'zu', 'zumachen', 'schliessen', //
      'runterlassen', 'runterfahren', 'runtermachen',
      'herunterlassen', 'herunterfahren', 'runterziehen', 'zufahren',
      'zuziehen', 'einfahren', 'unten', 'mach zu', 'mach runter',
    ],
    HaAction.stop: [
      'stopp', 'stop', 'stoppen', 'anhalten', 'halt', 'halte an', 'haltet', //
      'stehenbleiben', 'aufhoren', 'aufhoeren', 'nicht weiter',
    ],
    HaAction.brighter: [
      'heller', 'aufhellen', 'mehr licht', 'heller machen', 'hochdimmen', //
      'aufdimmen',
    ],
    HaAction.dimmer: [
      'dunkler', 'abdunkeln', 'dimmen', 'dimm', 'weniger licht', //
      'runterdimmen', 'gedimmt',
    ],
    HaAction.half: ['halb', 'halbe', 'halbhoch', 'zur halfte', 'mittig'],
  },
  percent: ['prozent', 'prozentig'],
  fillers: [
    'der',
    'die',
    'das',
    'den',
    'dem',
    'im',
    'in',
    'am',
    'ein',
    'eine',
    'meine',
    'mein',
    'bitte',
  ],
  degrees: ['grad'],
  neutral: [
    'mach', 'mache', 'machen', 'schalte', 'schalt', 'schalten', 'stell', //
    'stelle', 'fahr', 'fahre', 'lass', 'lasse', 'mal', 'bitte', 'doch',
    'jetzt', 'kannst', 'du', 'mir', 'wendelin', 'wendeln', 'hey', 'hallo',
    'okay', 'ok',
  ],
  // Never on the fast path, any domain (garage, gate, door, lock, alarm).
  blockers: [
    'garage', 'tor', 'tur', 'tuer', 'pforte', 'offner', 'oeffner', //
    'schloss', 'alarm', 'tresor', 'klingel', 'riegel',
  ],
  // Harmless words with a stem inside (tor, tur).
  blockerExceptions: [
    'ventilator', 'monitor', 'radiator', 'generator', 'motor', 'doktor', //
    'traktor', 'faktor', 'sektor', 'reflektor', 'projektor', 'detektor',
    'operator', 'indikator', 'kondensator', 'temperatur', 'natur', 'kultur',
    'tastatur', 'armatur', 'struktur', 'signatur', 'garnitur',
  ],
);

/// Extra topic words for the preloading of the `ha` tools (on top of the
/// device types): recognition slips only together with an action, so that
/// „meine Rolle“ alone does not unlock the tools.
const haTopicWordsDe = <String>[
  'rolle runter', 'rolle rauf', 'rolle hoch', 'rolle zu', 'rolle auf', //
  'rolle herunter', 'rolle hinunter', 'rolo runter', 'rolo rauf',
  'rolo hoch', 'rolo zu', 'rolo auf',
  'dimm', 'heller', 'dunkler',
];
