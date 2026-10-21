import 'dart:io';

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import 'predicates.dart';

/// One acceptable tool call: a tool (one of [tools]) whose arguments pass
/// all [args] predicates.
@immutable
final class CallOption {
  /// Creates an option.
  const CallOption({
    required this.tools,
    this.args = const {},
    this.succeeded = true,
  });

  /// Accepted tool names.
  final List<String> tools;

  /// Predicates per argument name (dotted paths reach into objects).
  final Map<String, ValuePredicate> args;

  /// Whether only calls the tool executed without error count (default).
  /// `false` also accepts failed calls (e.g. when the failure is expected).
  final bool succeeded;

  /// Short description for reports.
  String describe() {
    final name = tools.join('|');
    if (args.isEmpty) return name;
    final a = args.entries.map((e) => '${e.key} ${e.value.describe()}');
    return '$name(${a.join(', ')})';
  }
}

/// An expected tool call; satisfied if any of [options] matches one of the
/// observed calls.
@immutable
final class CallExpectation {
  /// Creates the expectation.
  const CallExpectation(this.options);

  /// Alternatives.
  final List<CallOption> options;

  /// All tool names mentioned.
  Iterable<String> get toolNames => options.expand((o) => o.tools);

  /// Short description for reports.
  String describe() => options.map((o) => o.describe()).join(' oder ');
}

/// What a case expects from the agent.
@immutable
final class Expectation {
  /// Creates the expectation.
  const Expectation({
    this.calls = const [],
    this.noTools = false,
    this.forbid = const [],
    this.text,
    this.confirmed,
    this.exact = false,
  });

  /// Calls that must appear (any order, extra calls allowed unless
  /// [exact]).
  final List<CallExpectation> calls;

  /// No tool may be called at all (small talk, pure questions).
  final bool noTools;

  /// Tools that must not be called.
  final List<String> forbid;

  /// Predicate on the final answer text.
  final ValuePredicate? text;

  /// `true`: at least one confirmation was requested (external tools);
  /// `false`: none; `null`: not checked.
  final bool? confirmed;

  /// No calls besides the expected ones (by tool name).
  final bool exact;
}

/// A calendar event present before the case runs.
@immutable
final class SeedEvent {
  /// Creates a seed; [start]/[end] are relative specs (`+1d 15:00`).
  const SeedEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
  });

  /// Event id.
  final String id;

  /// Title.
  final String title;

  /// Start spec.
  final String start;

  /// End spec; `null` = one hour.
  final String? end;
}

/// A memory entry present before the case runs.
@immutable
final class SeedMemory {
  /// Creates a seed.
  const SeedMemory(this.text, this.category);

  /// The fact.
  final String text;

  /// Category name (`person`, `preference`, `fact`, `project`).
  final String category;
}

/// A web search hit returned by the fake search backend.
@immutable
final class SeedSearchResult {
  /// Creates a seed.
  const SeedSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  /// Title.
  final String title;

  /// URL.
  final String url;

  /// Excerpt.
  final String snippet;
}

/// State of the fake ports before a case runs.
@immutable
final class CaseSetup {
  /// Creates a setup.
  const CaseSetup({
    this.clipboard,
    this.events = const [],
    this.memory = const [],
    this.searchResults,
    this.backends = const {},
  });

  /// Clipboard text.
  final String? clipboard;

  /// Calendar events.
  final List<SeedEvent> events;

  /// Memory entries.
  final List<SeedMemory> memory;

  /// Search hits; `null` = the default hits.
  final List<SeedSearchResult>? searchResults;

  /// Extra integrations with fake backends (WP29): `bring` (Bring! account
  /// with two lists), `http` (Home-Assistant-like HTTP tools, fake
  /// responses), `mcp` (in-process `FakeMcpServer`, server name „Home“),
  /// and (WP112) `gtasks`, `spotify`, `weather`, `station`, `notes`
  /// (Obsidian vault), see `case_backends_m5.dart`.
  final Set<String> backends;
}

/// Backends a case may ask for in `setup.backends`.
const caseBackends = {
  'bring',
  'http',
  'mcp',
  'gtasks',
  'spotify',
  'weather',
  'station',
  'notes',
};

/// One eval case: a user request and what should happen.
@immutable
final class EvalCase {
  /// Creates a case.
  const EvalCase({
    required this.id,
    required this.language,
    required this.prompt,
    required this.expect,
    this.category = 'misc',
    this.setup = const CaseSetup(),
    this.pending = false,
    this.note,
  });

  /// Unique id, e.g. `de-cal-tauchen`.
  final String id;

  /// Language code (`de`, `fr`, `en`).
  final String language;

  /// Category (`calendar`, `alarms`, `smalltalk` …).
  final String category;

  /// What the user says.
  final String prompt;

  /// Expected behaviour.
  final Expectation expect;

  /// Port state before the run.
  final CaseSetup setup;

  /// Not run yet (e.g. the integration does not exist yet).
  final bool pending;

  /// Free-form comment.
  final String? note;

  /// Whether [filter] selects this case: a term matches the language, the
  /// category or – if longer than two characters – part of the id (so
  /// `en` selects English cases, not `de-cal-tauchen`); terms are
  /// comma-separated, any term suffices. An empty filter selects
  /// everything.
  bool matches(String? filter) {
    if (filter == null || filter.trim().isEmpty) return true;
    for (final raw in filter.split(',')) {
      final term = raw.trim().toLowerCase();
      if (term.isEmpty) continue;
      if (language == term ||
          category.toLowerCase() == term ||
          (term.length > 2 && id.toLowerCase().contains(term))) {
        return true;
      }
    }
    return false;
  }
}

/// Parses one case file (YAML): `{language: de, cases: [...]}`. Throws
/// [FormatException] naming [source] and the case.
List<EvalCase> parseCaseFile(String yaml, {String source = 'cases'}) {
  final Object? doc;
  try {
    doc = _plain(loadYaml(yaml));
  } on YamlException catch (e) {
    throw FormatException('$source: ${e.message}');
  }
  if (doc is! Map<String, Object?>) {
    throw FormatException('$source: Objekt mit "cases" erwartet');
  }
  final fileLang = doc['language'];
  final cases = doc['cases'];
  if (cases is! List) throw FormatException('$source: "cases" fehlt');
  return [
    for (final (i, raw) in cases.indexed)
      _wrap('$source#${i + 1}', () => _case(raw, fileLang)),
  ];
}

/// Loads all `*.yaml` files in [dir] (sorted by name). Throws
/// [FormatException] for invalid files or duplicate ids.
List<EvalCase> loadCases(Directory dir) {
  if (!dir.existsSync()) {
    throw FormatException('Fall-Verzeichnis ${dir.path} fehlt');
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final all = <EvalCase>[];
  final ids = <String>{};
  for (final f in files) {
    for (final c in parseCaseFile(f.readAsStringSync(), source: f.path)) {
      if (!ids.add(c.id)) {
        throw FormatException('${f.path}: doppelte Fall-Id "${c.id}"');
      }
      all.add(c);
    }
  }
  return all;
}

T _wrap<T>(String where, T Function() body) {
  try {
    return body();
  } on FormatException catch (e) {
    throw FormatException('$where: ${e.message}');
  }
}

EvalCase _case(Object? raw, Object? fileLang) {
  final m = _map(raw, 'Fall');
  final id = _str(m, 'id');
  return _wrap(id, () {
    _only(m, const {
      'id',
      'language',
      'category',
      'prompt',
      'expect',
      'setup',
      'pending',
      'note',
    });
    final lang = m['language'] ?? fileLang;
    if (lang is! String || lang.isEmpty) {
      throw const FormatException('"language" fehlt');
    }
    final pending = m['pending'] ?? false;
    if (pending is! bool) {
      throw const FormatException('"pending" ist kein bool');
    }
    return EvalCase(
      id: id,
      language: lang,
      category: m['category'] as String? ?? 'misc',
      prompt: _str(m, 'prompt'),
      expect: _expect(_map(m['expect'], 'expect')),
      setup: m['setup'] == null
          ? const CaseSetup()
          : _setup(_map(m['setup'], 'setup')),
      pending: pending,
      note: m['note'] as String?,
    );
  });
}

Expectation _expect(Map<String, Object?> m) {
  _only(m, const {'calls', 'no_tools', 'forbid', 'text', 'confirmed', 'exact'});
  final calls = m['calls'] ?? const <Object?>[];
  if (calls is! List) throw const FormatException('"calls" ist keine Liste');
  final noTools = m['no_tools'] ?? false;
  final exact = m['exact'] ?? false;
  final confirmed = m['confirmed'];
  if (noTools is! bool || exact is! bool || confirmed is! bool?) {
    throw const FormatException('no_tools/exact/confirmed müssen bool sein');
  }
  final expectation = Expectation(
    calls: [for (final c in calls) _call(c)],
    noTools: noTools,
    forbid: _strList(m['forbid'], 'forbid'),
    text: m.containsKey('text') ? ValuePredicate.parse(m['text']) : null,
    confirmed: confirmed,
    exact: exact,
  );
  if (noTools && expectation.calls.isNotEmpty) {
    throw const FormatException('no_tools und calls schließen sich aus');
  }
  if (!noTools &&
      expectation.calls.isEmpty &&
      expectation.text == null &&
      expectation.forbid.isEmpty) {
    throw const FormatException(
      'expect braucht calls, no_tools, text oder forbid',
    );
  }
  return expectation;
}

CallExpectation _call(Object? raw) {
  final m = _map(raw, 'call');
  if (m.containsKey('any_of')) {
    _only(m, const {'any_of'});
    final list = m['any_of'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('any_of braucht eine nicht leere Liste');
    }
    return CallExpectation([for (final o in list) _option(_map(o, 'any_of'))]);
  }
  return CallExpectation([_option(m)]);
}

CallOption _option(Map<String, Object?> m) {
  _only(m, const {'tool', 'args', 'succeeded'});
  final succeeded = m['succeeded'] ?? true;
  if (succeeded is! bool) {
    throw const FormatException('"succeeded" muss bool sein');
  }
  final tool = m['tool'];
  final tools = tool is List ? _strList(tool, 'tool') : [_str(m, 'tool')];
  if (tools.isEmpty) throw const FormatException('"tool" fehlt');
  final args = m['args'] == null
      ? const <String, Object?>{}
      : _map(m['args'], 'args');
  return CallOption(
    tools: tools,
    succeeded: succeeded,
    args: {
      for (final e in args.entries)
        e.key: _wrap('args.${e.key}', () => ValuePredicate.parse(e.value)),
    },
  );
}

CaseSetup _setup(Map<String, Object?> m) {
  _only(m, const {
    'clipboard',
    'events',
    'memory',
    'search_results',
    'backends',
  });
  final backends = m['backends'] ?? const <Object?>[];
  if (backends is! List ||
      backends.any((b) => b is! String || !caseBackends.contains(b))) {
    throw FormatException(
      'backends: Liste aus ${caseBackends.join(', ')} erwartet',
    );
  }
  final events = m['events'] ?? const <Object?>[];
  final memory = m['memory'] ?? const <Object?>[];
  final results = m['search_results'];
  if (events is! List ||
      memory is! List ||
      (results != null && results is! List)) {
    throw const FormatException('events/memory/search_results: Liste erwartet');
  }
  return CaseSetup(
    clipboard: m['clipboard'] as String?,
    backends: {for (final b in backends) b as String},
    events: [
      for (final e in events)
        () {
          final em = _map(e, 'event');
          _only(em, const {'id', 'title', 'start', 'end'});
          return SeedEvent(
            id: _str(em, 'id'),
            title: _str(em, 'title'),
            start: _str(em, 'start'),
            end: em['end'] as String?,
          );
        }(),
    ],
    memory: [
      for (final e in memory)
        () {
          final mm = _map(e, 'memory');
          _only(mm, const {'text', 'category'});
          final category = _str(mm, 'category');
          if (!_memoryCategories.contains(category)) {
            throw FormatException(
              'Unbekannte Gedächtnis-Kategorie "$category" '
              '(erlaubt: ${_memoryCategories.join(', ')})',
            );
          }
          return SeedMemory(_str(mm, 'text'), category);
        }(),
    ],
    searchResults: results == null
        ? null
        : [
            for (final r in results as List)
              () {
                final rm = _map(r, 'search_result');
                _only(rm, const {'title', 'url', 'snippet'});
                return SeedSearchResult(
                  title: _str(rm, 'title'),
                  url: _str(rm, 'url'),
                  snippet: rm['snippet'] as String? ?? '',
                );
              }(),
          ],
  );
}

const _memoryCategories = ['person', 'preference', 'fact', 'project'];

Map<String, Object?> _map(Object? v, String what) {
  if (v is Map<String, Object?>) return v;
  throw FormatException('"$what" muss ein Objekt sein');
}

String _str(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is String && v.trim().isNotEmpty) return v;
  throw FormatException('"$key" fehlt oder ist kein Text');
}

List<String> _strList(Object? v, String key) {
  if (v == null) return const [];
  if (v is List && v.every((x) => x is String)) return v.cast<String>();
  throw FormatException('"$key" muss eine Liste von Texten sein');
}

void _only(Map<String, Object?> m, Set<String> allowed) {
  final unknown = m.keys.where((k) => !allowed.contains(k)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unbekannte Felder: $unknown');
  }
}

/// Converts YAML nodes into plain maps and lists.
Object? _plain(Object? v) => switch (v) {
  final YamlMap m => <String, Object?>{
    for (final e in m.entries) '${e.key}': _plain(e.value),
  },
  final YamlList l => [for (final x in l) _plain(x)],
  _ => v,
};
