import '../ha_words.dart';

/// English words for smart-home devices and actions (WP135). Types are word
/// stems (prefix of a word), actions whole words or phrases. See README.md.
const _lightEn = <String>[
  'light', 'lamp', 'bulb', 'lighting', 'spotlight', 'chandelier', //
  'sconce',
];
const _coverEn = <String>[
  'blind', 'shutter', 'shade', 'awning', 'curtain', 'drape', //
  'roller', 'sunshade', 'rollo', 'venetian',
];
const _switchEn = <String>['socket', 'plug', 'outlet'];
const _climateEn = <String>[
  'heating', 'heater', 'thermostat', 'radiator', 'air con', //
  'aircon', 'climate', 'hvac',
];

/// All device type stems of en (for the topic words of `ha`).
const haTypeStemsEn = <String>[
  ..._lightEn,
  ..._coverEn,
  ..._switchEn,
  ..._climateEn,
];

/// Words for en (see above).
const haWordsEn = HaWords(
  types: {
    'light': _lightEn,
    'cover': _coverEn,
    'switch': _switchEn,
    'climate': _climateEn,
  },
  recognitionErrors: {
    'cover': ['shudder', 'blynd'],
    'light': ['lite'],
  },
  actions: {
    HaAction.on: [
      'on', 'turn on', 'switch on', 'power on', 'put on', 'activate', //
      'enable',
    ],
    HaAction.off: [
      'off', 'turn off', 'switch off', 'power off', 'deactivate', //
      'disable',
    ],
    HaAction.open: [
      'open', 'up', 'raise', 'lift', 'roll up', 'pull up', 'extend', //
      'opened',
    ],
    HaAction.close: [
      'close', 'down', 'lower', 'shut', 'roll down', 'pull down', //
      'retract', 'closed',
    ],
    HaAction.stop: ['stop', 'halt', 'pause', 'freeze'],
    HaAction.brighter: [
      'brighter', 'brighten', 'more light', //
    ],
    HaAction.dimmer: [
      'dimmer', 'dim', 'darker', 'less light', //
    ],
    HaAction.half: ['half', 'halfway', 'half way', 'middle'],
  },
  percent: ['percent', 'per cent', 'pct'],
  fillers: ['the', 'my', 'in', 'of', 'a', 'please', 'room'],
  degrees: ['degree', 'degrees'],
  neutral: [
    'turn', 'switch', 'put', 'set', 'make', 'can', 'you', 'could', 'now', //
    'me', 'to', 'it', 'hey', 'hi', 'okay', 'ok', 'wendelin',
  ],
  // Never on the fast path, any domain (garage, gate, door, lock, alarm).
  blockers: ['garage', 'gate', 'door', 'lock', 'opener', 'alarm', 'latch'],
);

/// Extra topic words for the preloading of the `ha` tools.
const haTopicWordsEn = <String>['dim', 'brighter', 'dimmer', 'roller blind'];
