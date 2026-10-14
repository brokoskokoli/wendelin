import 'conditions.dart';
import 'routing_context.dart';
import 'rule_set.dart';

/// JSON of a [RuleSet] cannot be read; [message] is German and names the
/// place (`rules[2].condition`).
final class RuleSetFormatException extends FormatException {
  /// Creates the exception.
  const RuleSetFormatException(super.message);
}

/// Decodes the JSON fields of one condition type; [child] decodes nested
/// conditions, [at] is the JSON path for error messages.
typedef ConditionDecoder = Condition Function(
  JsonReader json,
  Condition Function(Object? json, String at) child,
);

/// Encodes the fields of one condition type (without `type`); [child]
/// encodes nested conditions.
typedef ConditionEncoder = Map<String, Object?> Function(
  Condition condition,
  Map<String, Object?> Function(Condition) child,
);

/// A condition type: JSON name plus decoder and encoder.
final class ConditionType {
  /// Creates a type.
  const ConditionType(this.name, this.decode, this.encode);

  /// Value of the JSON field `type`.
  final String name;

  /// Reads the type's fields.
  final ConditionDecoder decode;

  /// Writes the type's fields.
  final ConditionEncoder encode;
}

/// Name → [ConditionType]. [ConditionRegistry.standard] knows every
/// built-in condition; new types are added with [ConditionRegistry.new].
final class ConditionRegistry {
  /// Creates a registry from [types] (later entries replace earlier ones
  /// with the same name).
  ConditionRegistry(Iterable<ConditionType> types)
    : _types = {for (final t in types) t.name: t};

  /// All built-in condition types.
  static final standard = ConditionRegistry(standardConditionTypes);

  final Map<String, ConditionType> _types;

  /// Known type names.
  Iterable<String> get names => _types.keys;

  /// Decodes a condition at JSON path [at].
  Condition decode(Object? json, [String at = 'condition']) {
    final r = JsonReader(json, at);
    final name = r.string('type');
    final type = _types[name];
    if (type == null) {
      throw RuleSetFormatException(
        'Unbekannter Bedingungstyp „$name“ ($at). Bekannt sind: '
        '${names.join(', ')}.',
      );
    }
    return type.decode(r, decode);
  }

  /// Encodes [condition].
  Map<String, Object?> encode(Condition condition) {
    final type = _types[condition.type];
    if (type == null) {
      throw ArgumentError.value(
        condition.type,
        'condition',
        'Bedingungstyp nicht registriert',
      );
    }
    return {'type': condition.type, ...type.encode(condition, encode)};
  }
}

/// The built-in condition types.
final standardConditionTypes = <ConditionType>[
  ConditionType(
    'and',
    (r, child) => AndCondition(r.list('conditions', child)),
    (c, child) => {
      'conditions': (c as AndCondition).conditions.map(child).toList(),
    },
  ),
  ConditionType(
    'or',
    (r, child) => OrCondition(r.list('conditions', child)),
    (c, child) => {
      'conditions': (c as OrCondition).conditions.map(child).toList(),
    },
  ),
  ConditionType(
    'not',
    (r, child) =>
        NotCondition(child(r.field('condition'), r.path('condition'))),
    (c, child) => {'condition': child((c as NotCondition).condition)},
  ),
  ConditionType(
    'keyword',
    (r, _) => KeywordCondition(r.strings('words')),
    (c, _) => {'words': (c as KeywordCondition).words},
  ),
  ConditionType(
    'prefix',
    (r, _) => PrefixCondition(r.strings('words')),
    (c, _) => {'words': (c as PrefixCondition).words},
  ),
  ConditionType(
    'regex',
    (r, _) => RegexCondition(r.string('pattern')),
    (c, _) => {'pattern': (c as RegexCondition).pattern},
  ),
  ConditionType(
    'language',
    (r, _) => LanguageCondition(r.strings('languages')),
    (c, _) => {'languages': (c as LanguageCondition).languages},
  ),
  ConditionType(
    'sttConfidence',
    (r, _) => SttConfidenceCondition(r.number('below').toDouble()),
    (c, _) => {'below': (c as SttConfidenceCondition).below},
  ),
  ConditionType(
    'inputLength',
    (r, _) => InputLengthCondition(r.integer('above')),
    (c, _) => {'above': (c as InputLengthCondition).above},
  ),
  ConditionType(
    'hasImage',
    (_, _) => const HasImageCondition(),
    (_, _) => const {},
  ),
  ConditionType(
    'network',
    (r, _) => NetworkCondition(r.enumValue('state', NetworkState.values)),
    (c, _) => {'state': (c as NetworkCondition).state.name},
  ),
  ConditionType(
    'timeWindow',
    (r, _) => TimeWindowCondition(
      days: {...r.optionalList('days', JsonReader.asInt)},
      start: r.time('start'),
      end: r.time('end'),
    ),
    (c, _) {
      final t = c as TimeWindowCondition;
      return {
        'days': (t.days.toList()..sort()),
        'start': _formatTime(t.start),
        'end': _formatTime(t.end),
      };
    },
  ),
  ConditionType(
    'needsTool',
    (r, _) => NeedsToolCondition(r.string('category')),
    (c, _) => {'category': (c as NeedsToolCondition).category},
  ),
  ConditionType(
    'privacy',
    (r, _) => r.has('words')
        ? PrivacyCondition(r.strings('words'))
        : PrivacyCondition(),
    (c, _) => {'words': (c as PrivacyCondition).words},
  ),
];

String _formatTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// Import and export of a [RuleSet] as JSON (concept: „Speicherung als
/// JSON, import- und exportierbar“). Contains only profile and model ids,
/// no secrets.
final class RuleSetJson {
  /// Creates a codec using [registry] for conditions.
  RuleSetJson({ConditionRegistry? registry})
    : registry = registry ?? ConditionRegistry.standard;

  /// Current schema version.
  static const schemaVersion = 1;

  /// Condition types.
  final ConditionRegistry registry;

  /// [rules] as a JSON object.
  Map<String, Object?> encode(RuleSet rules) => {
    'schemaVersion': schemaVersion,
    'rules': [
      for (final r in rules.rules)
        {
          'id': r.id,
          'name': r.name,
          'enabled': r.enabled,
          'condition': registry.encode(r.condition),
          'target': _target(r.target),
          'stripTrigger': r.stripTrigger,
          if (r.aliases.isNotEmpty) 'aliases': r.aliases,
        },
    ],
    'defaultTarget': _target(rules.defaultTarget),
  };

  static Map<String, Object?> _target(RouteTarget t) => {
    'profileId': t.profileId,
    'modelId': t.modelId,
  };

  /// Reads a JSON object; throws [RuleSetFormatException] with a German
  /// message on errors (unknown type, missing field, newer schema).
  RuleSet decode(Object? json) {
    final r = JsonReader(json, r'$');
    final version = r.integer('schemaVersion');
    if (version < 1 || version > schemaVersion) {
      throw RuleSetFormatException(
        'Schema-Version $version wird nicht unterstützt (erwartet: '
        '$schemaVersion).',
      );
    }
    // Older exports carry `chains` (escalation chains); they are ignored.
    return RuleSet(
      rules: r.optionalList('rules', _rule),
      defaultTarget: _readTarget(
        r.field('defaultTarget'),
        r.path('defaultTarget'),
      ),
    );
  }

  RoutingRule _rule(Object? json, String at) {
    final r = JsonReader(json, at);
    return RoutingRule(
      id: r.string('id'),
      name: r.string('name'),
      enabled: r.optionalBool('enabled', fallback: true),
      condition: registry.decode(r.field('condition'), r.path('condition')),
      target: _readTarget(r.field('target'), r.path('target')),
      stripTrigger: r.optionalBool('stripTrigger', fallback: false),
      aliases: r.has('aliases') ? r.strings('aliases') : const [],
    );
  }

  static RouteTarget _readTarget(Object? json, String at) {
    final r = JsonReader(json, at);
    return RouteTarget(
      profileId: r.string('profileId'),
      modelId: r.string('modelId'),
    );
  }
}

/// Typed access to a JSON object with German error messages naming the
/// path.
final class JsonReader {
  /// Wraps [json] found at [at]; throws if it is not an object.
  JsonReader(Object? json, this.at)
    : _map = json is Map<String, Object?>
          ? json
          : throw RuleSetFormatException('$at: Objekt erwartet.');

  /// JSON path of this object.
  final String at;
  final Map<String, Object?> _map;

  /// Path of [key] below this object.
  String path(String key) => '$at.$key';

  /// Whether [key] is present and not null.
  bool has(String key) => _map[key] != null;

  /// The raw value of a required [key].
  Object field(String key) =>
      _map[key] ?? (throw RuleSetFormatException('${path(key)}: fehlt.'));

  T _typed<T>(String key, String what) => switch (field(key)) {
    final T v => v,
    _ => throw RuleSetFormatException('${path(key)}: $what erwartet.'),
  };

  /// A required string.
  String string(String key) => _typed<String>(key, 'Text');

  /// A required number.
  num number(String key) => _typed<num>(key, 'Zahl');

  /// A required whole number.
  int integer(String key) => asInt(field(key), path(key));

  /// An optional bool.
  bool optionalBool(String key, {required bool fallback}) =>
      has(key) ? _typed<bool>(key, 'true/false') : fallback;

  /// A required list of strings.
  List<String> strings(String key) => asList(field(key), path(key), (v, at) {
    if (v is String) return v;
    throw RuleSetFormatException('$at: Text erwartet.');
  });

  /// A required list decoded with [item].
  List<T> list<T>(String key, T Function(Object? json, String at) item) =>
      asList(field(key), path(key), item);

  /// An optional list (empty if absent).
  List<T> optionalList<T>(
    String key,
    T Function(Object? json, String at) item,
  ) => has(key) ? list(key, item) : <T>[];

  /// An optional object (empty if absent).
  Map<String, Object?> optionalMap(String key) =>
      has(key) ? _typed<Map<String, Object?>>(key, 'Objekt') : const {};

  /// One of [values] by name.
  T enumValue<T extends Enum>(String key, List<T> values) {
    final name = string(key);
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw RuleSetFormatException(
      '${path(key)}: „$name“ unbekannt, erlaubt: '
      '${values.map((v) => v.name).join(', ')}.',
    );
  }

  /// A time `HH:MM` as minutes after midnight.
  int time(String key) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(string(key));
    final h = m == null ? 99 : int.parse(m[1]!);
    final min = m == null ? 99 : int.parse(m[2]!);
    if (h > 23 || min > 59) {
      throw RuleSetFormatException('${path(key)}: Uhrzeit HH:MM erwartet.');
    }
    return h * 60 + min;
  }

  /// [json] as a list decoded with [item].
  static List<T> asList<T>(
    Object? json,
    String at,
    T Function(Object? json, String at) item,
  ) {
    if (json is! List<Object?>) {
      throw RuleSetFormatException('$at: Liste erwartet.');
    }
    return [for (var i = 0; i < json.length; i++) item(json[i], '$at[$i]')];
  }

  /// [json] as a whole number.
  static int asInt(Object? json, String at) => switch (json) {
    final int v => v,
    final double v when v == v.roundToDouble() => v.toInt(),
    _ => throw RuleSetFormatException('$at: ganze Zahl erwartet.'),
  };
}
