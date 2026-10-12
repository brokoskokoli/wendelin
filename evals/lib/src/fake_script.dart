import 'dart:convert';

import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:yaml/yaml.dart';

import 'eval_case.dart';
import 'eval_time.dart';

/// Scripted answers for the offline eval run with [FakeLlmProvider].
///
/// YAML format:
///
/// ```yaml
/// default:            # for cases without own script
///   - text: "Das weiß ich nicht."
/// cases:
///   de-cal-tauchen:
///     - tool: calendar__create_event
///       args: {title: Tauchen, start: "{{+1d 10:00}}"}
///     - text: "Eingetragen."
/// ```
///
/// A turn is `text`, `tool` + `args`, or `tools: [{tool, args}, …]`
/// (parallel calls); optional `usage: {input, output}`. `{{spec}}` in
/// argument strings becomes the ISO wall time of a relative spec (see
/// [EvalTime.resolve]). If the last turn calls tools, a closing text turn
/// „Erledigt.“ is added.
final class FakeScript {
  FakeScript._(this._cases, this._default);

  /// Parses [yaml]; throws [FormatException].
  factory FakeScript.parse(String yaml) {
    final Object? doc;
    try {
      doc = jsonDecode(jsonEncode(loadYaml(yaml)));
    } on YamlException catch (e) {
      throw FormatException('Fake-Skript: ${e.message}');
    }
    if (doc is! Map<String, Object?>) {
      throw const FormatException('Fake-Skript: Objekt erwartet');
    }
    final cases = doc['cases'] ?? const <String, Object?>{};
    if (cases is! Map<String, Object?>) {
      throw const FormatException('Fake-Skript: "cases" muss ein Objekt sein');
    }
    List<Map<String, Object?>> turns(Object? v, String where) {
      if (v is! List || v.isEmpty) {
        throw FormatException('Fake-Skript $where: Liste von Zügen erwartet');
      }
      return [
        for (final t in v)
          if (t is Map<String, Object?>)
            t
          else
            throw FormatException('Fake-Skript $where: Zug ist kein Objekt'),
      ];
    }

    return FakeScript._(
      {for (final e in cases.entries) e.key: turns(e.value, e.key)},
      doc['default'] == null
          ? const [
              {'text': 'Das weiß ich leider nicht.'},
            ]
          : turns(doc['default'], 'default'),
    );
  }

  final Map<String, List<Map<String, Object?>>> _cases;
  final List<Map<String, Object?>> _default;

  /// Case ids with an own script.
  Iterable<String> get caseIds => _cases.keys;

  /// A fresh provider playing the script of [c] at [time].
  FakeLlmProvider providerFor(EvalCase c, EvalTime time) {
    final raw = _cases[c.id] ?? _default;
    final turns = [for (final (i, t) in raw.indexed) _turn(t, c.id, i, time)];
    final last = raw.last;
    if (last.containsKey('tool') || last.containsKey('tools')) {
      turns.add(ScriptedTurn.text('Erledigt.'));
    }
    return FakeLlmProvider(turns);
  }

  static ScriptedTurn _turn(
    Map<String, Object?> t,
    String caseId,
    int index,
    EvalTime time,
  ) {
    final usageMap = t['usage'];
    final usage = usageMap is Map<String, Object?>
        ? Usage(
            inputTokens: (usageMap['input'] as num?)?.toInt() ?? 0,
            outputTokens: (usageMap['output'] as num?)?.toInt() ?? 0,
          )
        : ScriptedTurn.defaultUsage;
    if (t['text'] case final String text) {
      return ScriptedTurn.text(text, usage: usage);
    }
    final specs = t.containsKey('tools')
        ? (t['tools'] is List
              ? t['tools']! as List<Object?>
              : const <Object?>[])
        : [t];
    final calls = <ToolCallBlock>[];
    for (final (j, s) in specs.indexed) {
      if (s is! Map<String, Object?> || s['tool'] is! String) {
        throw FormatException('Fake-Skript $caseId#${index + 1}: "tool" fehlt');
      }
      calls.add(
        ToolCallBlock(
          id: 'call_${index}_$j',
          name: s['tool']! as String,
          argumentsJson: jsonEncode(_fill(s['args'] ?? const {}, time)),
        ),
      );
    }
    if (calls.isEmpty) {
      throw FormatException(
        'Fake-Skript $caseId#${index + 1}: "text", "tool" oder "tools" fehlt',
      );
    }
    return ScriptedTurn.toolCalls(calls, usage: usage);
  }

  static final _placeholder = RegExp(r'\{\{([^}]*)\}\}');

  static Object? _fill(Object? v, EvalTime time) => switch (v) {
    final String s => s.replaceAllMapped(
      _placeholder,
      (m) => time.resolve(m[1]!).toIso(),
    ),
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _fill(e.value, time),
    },
    final List<Object?> l => [for (final x in l) _fill(x, time)],
    _ => v,
  };
}
