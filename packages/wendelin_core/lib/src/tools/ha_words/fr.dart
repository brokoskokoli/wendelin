import '../ha_words.dart';

/// French words for smart-home devices and actions (WP135). Types are word
/// stems (prefix of a word), actions whole words or phrases. See README.md.
const _lightFr = <String>[
  'lumiere', 'lampe', 'ampoule', 'eclairage', 'luminaire', 'spot', //
  'plafonnier', 'lustre', 'applique',
];
const _coverFr = <String>[
  'volet', 'store', 'rideau', 'persienne', 'brise soleil', 'jalousie', //
  'marquise', 'pergola', 'banne',
];
const _switchFr = <String>['prise', 'interrupteur', 'multiprise'];
const _climateFr = <String>[
  'chauffage', 'thermostat', 'radiateur', 'clim', 'climatisation', //
  'convecteur',
];

/// All device type stems of fr (for the topic words of `ha`).
const haTypeStemsFr = <String>[
  ..._lightFr,
  ..._coverFr,
  ..._switchFr,
  ..._climateFr,
];

/// Words for fr (see above).
const haWordsFr = HaWords(
  types: {
    'light': _lightFr,
    'cover': _coverFr,
    'switch': _switchFr,
    'climate': _climateFr,
  },
  recognitionErrors: {
    'cover': ['vole', 'volais'],
    'light': ['lumiaire'],
  },
  actions: {
    HaAction.on: [
      'allume', 'allumer', 'allumes', 'mets', 'mettre', 'active', 'activer', //
      'demarre', 'demarrer', 'branche', 'brancher', 'enclenche',
    ],
    HaAction.off: [
      'eteins', 'eteindre', 'eteint', 'coupe', 'couper', 'desactive', //
      'desactiver', 'debranche', 'debrancher',
    ],
    HaAction.open: [
      'ouvre', 'ouvrir', 'ouvert', 'monte', 'monter', 'leve', 'lever', //
      'remonte', 'remonter', 'releve', 'relever', 'ouvres', 'haut',
    ],
    HaAction.close: [
      'ferme', 'fermer', 'descends', 'descendre', 'baisse', //
      'baisser', 'abaisse', 'abaisser', 'bas',
    ],
    HaAction.stop: [
      'stop', 'stoppe', 'stopper', 'arrete', 'arreter', 'arretes', 'pause', //
      'halte', 'ne bouge plus',
    ],
    HaAction.brighter: [
      'plus lumineux', 'eclaircis', 'eclaircir', 'plus de lumiere', //
      'augmente la luminosite', 'plus clair',
    ],
    HaAction.dimmer: [
      'plus sombre', 'assombris', 'assombrir', 'tamise', 'tamiser', //
      'moins de lumiere', 'baisse la lumiere', 'attenue',
    ],
    HaAction.half: ['moitie', 'a moitie', 'mi hauteur', 'demi'],
  },
  percent: ['pour cent', 'pourcent', 'pourcentage', 'pct'],
  fillers: [
    'le',
    'la',
    'les',
    'l',
    'du',
    'de',
    'des',
    'au',
    'aux',
    'mon',
    'ma',
    'dans',
    'sil',
    'plait',
  ],
  degrees: ['degre', 'degres'],
  neutral: [
    's', 'il', 'te', 'vous', 'plait', 'stp', 'svp', 'peux', 'tu', 'pouvez', //
    'maintenant', 'a', 'sil', 'hey', 'ok', 'okay', 'wendelin',
  ],
  // Never on the fast path, any domain (garage, gate, door, lock, alarm).
  blockers: [
    'garage', 'portail', 'porte', 'serrure', 'verrou', 'alarme', //
    'coffre', 'sonnette',
  ],
  // Harmless words with a stem inside.
  blockerExceptions: ['importe', 'apporte', 'transporte', 'supporte'],
);

/// Extra topic words for the preloading of the `ha` tools.
const haTopicWordsFr = <String>[
  'volet roulant', 'plus sombre', 'plus lumineux', 'tamise', //
];
