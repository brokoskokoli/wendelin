import 'eval_time.dart';

/// A check on one value (a tool argument or the answer text).
///
/// [check] returns `null` if the value passes, otherwise a short German
/// reason. Built from YAML with [ValuePredicate.parse]:
///
/// | YAML | Bedeutung |
/// | --- | --- |
/// | `Tauchen`, `600`, `true`, `[1, 2]` | gleich (Text ohne Groß/Klein, Listen ohne Reihenfolge) |
/// | `{eq: x}` | gleich |
/// | `{contains: Tauchen}` / `{contains: [a, b]}` | Text enthält alle; Liste hat für jeden ein passendes Element |
/// | `{contains_any: [a, b]}` | enthält mindestens einen |
/// | `{matches: "^\\d+$"}` | regulärer Ausdruck (ohne Groß/Klein) |
/// | `{at: "+1d 10:00", tol_min: 0}` | Datum/Uhrzeit relativ zu „heute“ |
/// | `{date: "+1d"}` | Datum (Uhrzeit egal) |
/// | `{clock: "07:30"}` | Uhrzeit `H:MM` |
/// | `{min: 1, max: 5}` | Zahl im Bereich |
/// | `{one_of: [a, b]}` | gleich einem der Werte |
/// | `{present: false}` | Feld fehlt (bzw. `true`: ist da) |
/// | `{any_of: [p1, p2]}` | mindestens ein Prädikat passt |
/// | `{not: p}` | Prädikat passt nicht |
///
/// Several keys in one map must all hold.
sealed class ValuePredicate {
  const ValuePredicate();

  /// Parses a YAML/JSON spec (see class docs). Throws [FormatException].
  factory ValuePredicate.parse(Object? spec) {
    if (spec is! Map) return Equals(_plain(spec));
    final map = {for (final e in spec.entries) '${e.key}': e.value};
    if (map.isEmpty) throw const FormatException('Leeres Prädikat');
    final parts = <ValuePredicate>[];
    final used = <String>{};
    void take(String key, ValuePredicate Function(Object? v) build) {
      if (!map.containsKey(key)) return;
      used.add(key);
      parts.add(build(map[key]));
    }

    take('eq', (v) => Equals(_plain(v)));
    take('contains', (v) => Contains(_strings(v, 'contains')));
    take(
      'contains_any',
      (v) => Contains(_strings(v, 'contains_any'), any: true),
    );
    take('matches', (v) => Matches(_string(v, 'matches')));
    if (map.containsKey('at')) {
      used.addAll(['at', 'tol_min']);
      final tol = map['tol_min'] ?? 0;
      if (tol is! int || tol < 0) {
        throw const FormatException('tol_min muss eine Zahl ≥ 0 sein');
      }
      parts.add(At(_string(map['at'], 'at'), toleranceMinutes: tol));
    }
    take('date', (v) => OnDate(_string(v, 'date')));
    take('clock', (v) => ClockTime.parse(_string(v, 'clock')));
    if (map.containsKey('min') || map.containsKey('max')) {
      used.addAll(['min', 'max']);
      parts.add(
        Range(min: _num(map['min'], 'min'), max: _num(map['max'], 'max')),
      );
    }
    take('one_of', (v) {
      if (v is! List) throw const FormatException('one_of braucht eine Liste');
      return AnyOf([for (final x in v) Equals(_plain(x))]);
    });
    take('present', (v) {
      if (v is! bool) throw const FormatException('present braucht true/false');
      return Present(expected: v);
    });
    take('any_of', (v) {
      if (v is! List || v.isEmpty) {
        throw const FormatException('any_of braucht eine nicht leere Liste');
      }
      return AnyOf([for (final x in v) ValuePredicate.parse(x)]);
    });
    take('not', (v) => Not(ValuePredicate.parse(v)));

    final unknown = map.keys.where((k) => !used.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unbekannte Prädikat-Schlüssel: $unknown');
    }
    return parts.length == 1 ? parts.single : AllOf(parts);
  }

  /// `null` if [value] passes; otherwise why not. [present] tells whether
  /// the field exists at all (a missing field has value `null`).
  String? check(Object? value, EvalTime time, {bool present = true});

  /// Short description for reports.
  String describe();

  @override
  String toString() => describe();
}

/// Equality: strings trimmed and case-insensitive, numbers numerically
/// (also numeric strings), lists as multisets, maps by key.
final class Equals extends ValuePredicate {
  /// Creates the predicate.
  const Equals(this.expected);

  /// Expected value.
  final Object? expected;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    if (!present) return 'fehlt (erwartet ${_show(expected)})';
    return looseEquals(value, expected)
        ? null
        : 'ist ${_show(value)}, erwartet ${_show(expected)}';
  }

  @override
  String describe() => '= ${_show(expected)}';
}

/// Text contains the [needles] (all, or with [any] at least one); for lists
/// every needle must match an element (substring for texts). Ignores case
/// and accents („plongee“ finds „Plongée“, „Uber“ finds „Über“).
final class Contains extends ValuePredicate {
  /// Creates the predicate.
  const Contains(this.needles, {this.any = false});

  /// Searched texts.
  final List<String> needles;

  /// Whether one hit suffices.
  final bool any;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    if (!present) return 'fehlt';
    bool hit(String needle) {
      final n = foldAccents(_fold(needle));
      bool inText(Object? v) => foldAccents(_fold(_text(v))).contains(n);
      if (value is List) return value.any(inText);
      return value != null && inText(value);
    }

    final ok = any ? needles.any(hit) : needles.every(hit);
    if (ok) return null;
    final missing = needles.where((n) => !hit(n)).toList();
    return '${_show(value)} enthält nicht '
        '${any ? 'eines von ' : ''}${_show(missing)}';
  }

  @override
  String describe() =>
      '${any ? 'enthält eines von' : 'enthält'} '
      '${_show(needles)}';
}

/// Regular expression (case-insensitive) on the text form.
final class Matches extends ValuePredicate {
  /// Creates the predicate; throws [FormatException] for a bad pattern.
  Matches(this.pattern) : _re = RegExp(pattern, caseSensitive: false);

  /// The pattern.
  final String pattern;
  final RegExp _re;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    if (!present || value == null) return 'fehlt';
    return _re.hasMatch(_text(value))
        ? null
        : '${_show(value)} passt nicht zu /$pattern/';
  }

  @override
  String describe() => '~ /$pattern/';
}

/// A date-time relative to the run's „now“ (see [EvalTime.resolve]) with
/// [toleranceMinutes].
final class At extends ValuePredicate {
  /// Creates the predicate.
  const At(this.spec, {this.toleranceMinutes = 0});

  /// Relative spec, e.g. `+1d 10:00`.
  final String spec;

  /// Allowed deviation in minutes.
  final int toleranceMinutes;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    final expected = time.resolve(spec);
    if (!present || value is! String) return 'fehlt (erwartet $expected)';
    final got = time.read(value);
    if (got == null) return '„$value“ ist kein ISO-Datum';
    if (!expected.hasTime) {
      return got.sameDate(expected) ? null : 'ist $got, erwartet $expected';
    }
    if (!got.hasTime) return 'ist $got ohne Uhrzeit, erwartet $expected';
    final diff = got.minutesSince(expected).abs();
    return diff <= toleranceMinutes
        ? null
        : 'ist $got, erwartet $expected'
              '${toleranceMinutes > 0 ? ' ±$toleranceMinutes min' : ''}';
  }

  @override
  String describe() =>
      '@ $spec${toleranceMinutes > 0 ? ' ±$toleranceMinutes min' : ''}';
}

/// The date part of an ISO value equals a relative date.
final class OnDate extends ValuePredicate {
  /// Creates the predicate.
  const OnDate(this.spec);

  /// Relative spec, e.g. `+1d`.
  final String spec;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    final expected = time.resolve(spec).date;
    if (!present || value is! String) return 'fehlt (erwartet $expected)';
    final got = time.read(value);
    if (got == null) return '„$value“ ist kein ISO-Datum';
    return got.sameDate(expected)
        ? null
        : 'Datum ${got.date}, erwartet $expected';
  }

  @override
  String describe() => 'Datum $spec';
}

/// A time of day `H:MM` / `HH:MM`.
final class ClockTime extends ValuePredicate {
  /// Creates the predicate.
  const ClockTime(this.hour, this.minute);

  /// Parses `07:30`; throws [FormatException].
  factory ClockTime.parse(String spec) {
    final m = _clock(spec);
    if (m == null) throw FormatException('Ungültige Uhrzeit „$spec“');
    return ClockTime(m.$1, m.$2);
  }

  /// Expected hour.
  final int hour;

  /// Expected minute.
  final int minute;

  static (int, int)? _clock(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!);
    final mi = int.parse(m[2]!);
    if (h > 23 || mi > 59) return null;
    return (h, mi);
  }

  String get _expected =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    if (!present || value is! String) return 'fehlt (erwartet $_expected)';
    final got = _clock(value);
    if (got == null) return '„$value“ ist keine Uhrzeit';
    return got == (hour, minute) ? null : 'ist $value, erwartet $_expected';
  }

  @override
  String describe() => 'Uhrzeit $_expected';
}

/// A number (or numeric string) within [min]..[max] (inclusive).
final class Range extends ValuePredicate {
  /// Creates the predicate; either bound may be `null`.
  const Range({this.min, this.max});

  /// Lower bound.
  final num? min;

  /// Upper bound.
  final num? max;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    final n = _number(value);
    if (!present || n == null) return '${_show(value)} ist keine Zahl';
    if (min != null && n < min!) return '$n < $min';
    if (max != null && n > max!) return '$n > $max';
    return null;
  }

  @override
  String describe() => 'in [${min ?? ''}..${max ?? ''}]';
}

/// Field presence.
final class Present extends ValuePredicate {
  /// Creates the predicate.
  const Present({required this.expected});

  /// `true` = must exist, `false` = must be absent (or `null`).
  final bool expected;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    final exists = present && value != null;
    if (exists == expected) return null;
    return expected ? 'fehlt' : 'sollte fehlen, ist ${_show(value)}';
  }

  @override
  String describe() => expected ? 'vorhanden' : 'nicht vorhanden';
}

/// All [parts] hold.
final class AllOf extends ValuePredicate {
  /// Creates the predicate.
  const AllOf(this.parts);

  /// Conjuncts.
  final List<ValuePredicate> parts;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    for (final p in parts) {
      final r = p.check(value, time, present: present);
      if (r != null) return r;
    }
    return null;
  }

  @override
  String describe() => parts.map((p) => p.describe()).join(' und ');
}

/// At least one of [options] holds.
final class AnyOf extends ValuePredicate {
  /// Creates the predicate.
  const AnyOf(this.options);

  /// Alternatives.
  final List<ValuePredicate> options;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) {
    final reasons = <String>[];
    for (final p in options) {
      final r = p.check(value, time, present: present);
      if (r == null) return null;
      reasons.add(r);
    }
    return 'keine Alternative passt (${reasons.join('; ')})';
  }

  @override
  String describe() => '(${options.map((p) => p.describe()).join(' oder ')})';
}

/// [inner] does not hold.
final class Not extends ValuePredicate {
  /// Creates the predicate.
  const Not(this.inner);

  /// Negated predicate.
  final ValuePredicate inner;

  @override
  String? check(Object? value, EvalTime time, {bool present = true}) =>
      inner.check(value, time, present: present) == null
      ? '${_show(value)} sollte nicht ${inner.describe()} sein'
      : null;

  @override
  String describe() => 'nicht ${inner.describe()}';
}

/// Loose equality used by [Equals] (see there).
bool looseEquals(Object? a, Object? b) {
  if (a == null || b == null) return a == b;
  final na = _number(a);
  final nb = _number(b);
  if (na != null && nb != null && (a is num || b is num)) return na == nb;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    final rest = List.of(b);
    for (final x in a) {
      final i = rest.indexWhere((y) => looseEquals(x, y));
      if (i < 0) return false;
      rest.removeAt(i);
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    return a.keys.every((k) => b.containsKey(k) && looseEquals(a[k], b[k]));
  }
  if (a is String && b is String) return _fold(a) == _fold(b);
  return a == b;
}

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// Lower-case [s] with the common Latin accents removed (`é` → `e`,
/// `œ` → `oe`, `ü` → `u`); `ß` stays.
String foldAccents(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

num? _number(Object? v) => switch (v) {
  final num n => n,
  final String s => num.tryParse(s.trim()),
  _ => null,
};

String _fold(String s) => s.trim().toLowerCase();

String _text(Object? v) => v is String ? v : '$v';

String _show(Object? v) => v is String ? '„$v“' : '$v';

Object? _plain(Object? v) => switch (v) {
  final Map<Object?, Object?> m => {
    for (final e in m.entries) '${e.key}': _plain(e.value),
  },
  final List<Object?> l => [for (final x in l) _plain(x)],
  _ => v,
};

String _string(Object? v, String key) {
  if (v is String && v.isNotEmpty) return v;
  if (v is num) return '$v';
  throw FormatException('$key braucht einen Text');
}

List<String> _strings(Object? v, String key) {
  if (v is List && v.isNotEmpty) return [for (final x in v) _string(x, key)];
  return [_string(v, key)];
}

num? _num(Object? v, String key) {
  if (v == null || v is num) return v as num?;
  throw FormatException('$key braucht eine Zahl');
}
