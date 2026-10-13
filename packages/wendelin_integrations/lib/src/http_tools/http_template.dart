// Vorlagen-Engine der HTTP-Tools: Platzhalter `{arg}` in Pfad, Query,
// Headern und Body. Host, Schema und Port kommen nur aus der Vorlage.

import 'dart:convert';

import 'package:meta/meta.dart';

import '../common/tool_args.dart';
import 'http_tool_definition.dart';

final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');
final _exactPlaceholder = RegExp(r'^\{([A-Za-z_][A-Za-z0-9_]*)\}$');
final _start = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://([^/?#]*)(.*)$');

/// Placeholder names in [template]; throws [FormatException] for stray or
/// malformed braces (e.g. `{a-b}` or `{`).
Set<String> templatePlaceholders(String template) {
  final rest = template.replaceAll(_placeholder, '');
  if (rest.contains('{') || rest.contains('}')) {
    throw FormatException(
      'ungültiger Platzhalter in „$template“ (erlaubt: {name} aus '
      'Buchstaben, Ziffern und „_“)',
    );
  }
  return {for (final m in _placeholder.allMatches(template)) m[1]!};
}

/// Name of the placeholder if [template] is exactly one placeholder.
String? exactPlaceholder(String template) =>
    _exactPlaceholder.firstMatch(template)?[1];

/// A parsed URL template: fixed origin plus path and query templates.
///
/// Placeholders are only allowed in the path and the query values – never
/// in scheme, host, port, user info, query keys or fragment. Path values are
/// inserted as one encoded segment (no `/`, `\`, `.` or `..` segments),
/// query values URL-encoded. The expanded URL always has [origin].
@immutable
final class UrlTemplate {
  const UrlTemplate._(this.origin, this._segments, this._query);

  /// Parses [template]; throws [FormatException] with a German message.
  factory UrlTemplate.parse(String template) {
    final t = template.trim();
    if (t.isEmpty) throw const FormatException('URL fehlt');
    if (t.length > 2048) throw const FormatException('URL zu lang');
    if (t.codeUnits.any((c) => c <= 0x20 || c == 0x7f)) {
      throw const FormatException('URL enthält Leer- oder Steuerzeichen');
    }
    if (t.contains('#')) {
      throw const FormatException('URL darf keinen Anker (#) enthalten');
    }
    final m = _start.firstMatch(t);
    if (m == null) {
      throw const FormatException(
        'URL muss mit „https://“ oder „http://“ und einem festen Host beginnen',
      );
    }
    final scheme = m[1]!.toLowerCase();
    final authority = m[2]!;
    if (scheme != 'http' && scheme != 'https') {
      throw const FormatException('nur http- und https-Adressen');
    }
    if (authority.contains('{') || authority.contains('}')) {
      throw const FormatException(
        'Platzhalter sind nur in Pfad und Query erlaubt, nicht in Schema, '
        'Host oder Port',
      );
    }
    if (authority.contains('@')) {
      throw const FormatException('keine Zugangsdaten in der URL');
    }
    final Uri origin;
    try {
      origin = Uri.parse('$scheme://$authority');
    } on FormatException {
      throw FormatException('ungültiger Host „$authority“');
    }
    if (origin.host.isEmpty) throw const FormatException('Host fehlt');
    final rest = m[3]!;
    final q = rest.indexOf('?');
    final path = q < 0 ? rest : rest.substring(0, q);
    final query = q < 0 ? '' : rest.substring(q + 1);
    final segments = path.isEmpty ? <String>[] : path.substring(1).split('/');
    for (final s in segments) {
      templatePlaceholders(s);
    }
    final params = <(String, String?)>[];
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final key = eq < 0 ? part : part.substring(0, eq);
      final value = eq < 0 ? null : part.substring(eq + 1);
      if (key.contains('{') || key.contains('}')) {
        throw const FormatException(
          'Platzhalter nur in Query-Werten, nicht in Query-Namen',
        );
      }
      if (value != null) templatePlaceholders(value);
      params.add((key, value));
    }
    // Literale Teile müssen schon eine gültige URL ergeben.
    final probe = UrlTemplate._(origin, segments, params);
    try {
      probe._build(
        [for (final s in segments) s.replaceAll(_placeholder, 'x')],
        [
          for (final (k, v) in params)
            v == null ? k : '$k=${v.replaceAll(_placeholder, 'x')}',
        ],
      );
    } on FormatException {
      throw FormatException('ungültige URL „$t“');
    }
    return probe;
  }

  /// `scheme://host:port` – the only target this template can reach.
  final Uri origin;

  final List<String> _segments;
  final List<(String, String?)> _query;

  /// All placeholder names in path and query.
  Set<String> get placeholders => {
    for (final s in _segments) ...templatePlaceholders(s),
    for (final (_, v) in _query)
      if (v != null) ...templatePlaceholders(v),
  };

  /// The URL with [args] inserted; throws [InvalidArgumentsException] for
  /// missing or unsafe values. A query parameter whose value is exactly one
  /// placeholder is left out when the argument is absent.
  Uri expand(Map<String, Object?> args) {
    final segments = <String>[];
    for (final s in _segments) {
      final encoded = s.replaceAllMapped(_placeholder, (m) {
        final name = m[1]!;
        final value = scalarArg(args, name, 'Pfad');
        if (value.isEmpty) {
          throw InvalidArgumentsException('„$name“ darf nicht leer sein');
        }
        if (value.contains('/') || value.contains(r'\')) {
          throw InvalidArgumentsException(
            '„$name“ darf im Pfad kein „/“ oder „\\“ enthalten',
          );
        }
        return Uri.encodeComponent(value);
      });
      if (_isDotSegment(s, args)) {
        throw const InvalidArgumentsException(
          '„.“ und „..“ sind als Pfadteil nicht erlaubt',
        );
      }
      segments.add(encoded);
    }
    final query = <String>[];
    for (final (key, value) in _query) {
      if (value == null) {
        query.add(key);
        continue;
      }
      final only = exactPlaceholder(value);
      if (only != null && args[only] == null) continue;
      final v = value.replaceAllMapped(
        _placeholder,
        (m) => Uri.encodeQueryComponent(scalarArg(args, m[1]!, 'Query')),
      );
      query.add('$key=$v');
    }
    return _build(segments, query);
  }

  bool _isDotSegment(String segment, Map<String, Object?> args) {
    final filled = segment.replaceAllMapped(
      _placeholder,
      (m) => args[m[1]!]?.toString() ?? '',
    );
    return filled == '.' || filled == '..';
  }

  Uri _build(List<String> segments, List<String> query) {
    final b = StringBuffer(origin.toString());
    if (segments.isNotEmpty) b.write('/${segments.join('/')}');
    if (query.isNotEmpty) b.write('?${query.join('&')}');
    final uri = Uri.parse(b.toString());
    if (uri.scheme != origin.scheme ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty) {
      // Kann durch die Kodierung nicht passieren; zweite Verteidigungslinie.
      throw const FormatException('Ziel weicht von der Vorlage ab');
    }
    return uri;
  }
}

/// The argument [name] as text for a [where] position (path, query,
/// header). Numbers, booleans and strings are allowed; integral doubles
/// lose their `.0`. Throws [InvalidArgumentsException].
String scalarArg(Map<String, Object?> args, String name, String where) {
  final v = args[name];
  return switch (v) {
    null => throw InvalidArgumentsException('„$name“ fehlt'),
    String() => v,
    bool() || int() => '$v',
    double() when v.isFinite && v == v.roundToDouble() => '${v.toInt()}',
    double() when v.isFinite => '$v',
    _ => throw InvalidArgumentsException(
      '„$name“ muss im $where ein einzelner Wert (Text, Zahl, Ja/Nein) sein',
    ),
  };
}

/// Header values with [args] inserted. A header whose value is exactly one
/// absent placeholder is left out. Values with CR, LF or other control
/// characters are rejected (header injection).
Map<String, String> expandHeaders(
  Map<String, String> templates,
  Map<String, Object?> args,
) {
  final out = <String, String>{};
  for (final e in templates.entries) {
    final only = exactPlaceholder(e.value);
    if (only != null && args[only] == null) continue;
    final value = e.value.replaceAllMapped(_placeholder, (m) {
      final v = scalarArg(args, m[1]!, 'Header');
      if (hasHeaderControlChars(v)) {
        throw InvalidArgumentsException(
          '„${m[1]}“ enthält Zeilenumbrüche oder Steuerzeichen '
          '(im Header nicht erlaubt)',
        );
      }
      if (v.codeUnits.any((c) => c > 0x7e)) {
        throw InvalidArgumentsException(
          '„${m[1]}“: im Header sind nur ASCII-Zeichen erlaubt',
        );
      }
      return v;
    });
    out[e.key] = value;
  }
  return out;
}

/// Placeholder names in a body template; throws [FormatException] for a
/// structure the [format] cannot encode.
Set<String> bodyPlaceholders(Object? template, HttpBodyFormat format) {
  if (format == HttpBodyFormat.form) {
    if (template is! Map<String, Object?>) {
      throw const FormatException('Formular-Body muss ein Objekt sein');
    }
    return {
      for (final v in template.values)
        if (v is String)
          ...templatePlaceholders(v)
        else if (v is! num && v is! bool)
          throw const FormatException(
            'Formular-Body: nur Texte, Zahlen und Ja/Nein als Werte',
          ),
    };
  }
  return switch (template) {
    String() => templatePlaceholders(template),
    Map<String, Object?>() => {
      for (final v in template.values) ...bodyPlaceholders(v, format),
    },
    List<Object?>() => {
      for (final v in template) ...bodyPlaceholders(v, format),
    },
    null || num() || bool() => const <String>{},
    _ => throw FormatException('unerwarteter Wert ${template.runtimeType}'),
  };
}

/// Marker for a value left out because its placeholder argument is absent.
const Object _omit = Object();

/// The JSON body for [template] with [args] inserted type-correctly: a
/// string that is exactly `{name}` becomes the argument value (number,
/// boolean, list, object or text); placeholders inside longer strings are
/// replaced textually by scalar arguments. Object members and list elements
/// whose sole placeholder is absent are left out. Never builds JSON by
/// string concatenation.
Object? expandJsonBody(Object? template, Map<String, Object?> args) {
  final v = _expandJson(template, args);
  if (identical(v, _omit)) {
    throw InvalidArgumentsException(
      '„${exactPlaceholder(template! as String)}“ fehlt',
    );
  }
  return v;
}

Object? _expandJson(Object? template, Map<String, Object?> args) {
  switch (template) {
    case String():
      final only = exactPlaceholder(template);
      if (only != null) {
        final value = args[only];
        if (value == null) return _omit;
        return _jsonValue(value, only);
      }
      return template.replaceAllMapped(
        _placeholder,
        (m) => scalarArg(args, m[1]!, 'Text'),
      );
    case Map<String, Object?>():
      return {
        for (final e in template.entries)
          if (_expandJson(e.value, args) case final v when !identical(v, _omit))
            e.key: v,
      };
    case List<Object?>():
      return [
        for (final e in template)
          if (_expandJson(e, args) case final v when !identical(v, _omit)) v,
      ];
    default:
      return template;
  }
}

Object? _jsonValue(Object? value, String name) {
  try {
    // Rundreise: stellt sicher, dass nur JSON-Werte eingesetzt werden.
    return jsonDecode(jsonEncode(value));
  } on JsonUnsupportedObjectError {
    throw InvalidArgumentsException('„$name“ ist kein JSON-Wert');
  }
}

/// The form body (`a=1&b=x`) for [template] with [args] inserted;
/// members whose sole placeholder is absent are left out.
String expandFormBody(
  Map<String, Object?> template,
  Map<String, Object?> args,
) {
  final parts = <String>[];
  for (final e in template.entries) {
    final raw = e.value;
    final String value;
    if (raw is String) {
      final only = exactPlaceholder(raw);
      if (only != null && args[only] == null) continue;
      value = raw.replaceAllMapped(
        _placeholder,
        (m) => scalarArg(args, m[1]!, 'Formular'),
      );
    } else {
      value = '$raw';
    }
    parts.add(
      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(value)}',
    );
  }
  return parts.join('&');
}
