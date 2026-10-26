import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

/// A tool offered by an integration, with its integration (for search).
typedef CatalogEntry = ({Integration integration, Tool tool});

/// Meta tool `tools__search`, offered instead of all tools once many are
/// active. Finds tools by words and/or category (integration id), returns
/// their specs and unlocks them for the session via [unlock].
final class ToolSearchTool implements Tool, NoNetworkTarget, ResultTrustAware {
  /// Creates the meta tool over [candidates] (the active tools the current
  /// provider may see, sorted by name).
  ToolSearchTool({
    required List<CatalogEntry> candidates,
    required this.unlock,
    this.languageFor,
    this.maxResults = 10,
  }) : _candidates = candidates,
       categories = _categoriesOf(candidates);

  /// Reserved name of the meta tool.
  static const toolName = 'tools__search';

  final List<CatalogEntry> _candidates;

  /// Called with the session id and the names of the tools found.
  final void Function(String sessionId, List<String> names) unlock;

  /// Language of the current request of a session (as used for preloading);
  /// without it, or when it answers null, the device locale is used.
  final String? Function(String sessionId)? languageFor;

  /// At most this many tools per search.
  final int maxResults;

  /// Integration ids → display names of all candidates, sorted by id.
  final Map<String, String> categories;

  static Map<String, String> _categoriesOf(List<CatalogEntry> entries) {
    final byId = {
      for (final e in entries) e.integration.id: e.integration.displayName,
    };
    return {for (final id in byId.keys.toList()..sort()) id: byId[id]!};
  }

  /// Built-in network tools without a marker; their descriptions are ours.
  static const _builtInNetworkTools = {'web__search', 'web__fetch'};

  @override
  bool isResultTrusted(List<ContentBlock> content) {
    // The result only repeats descriptions. Foreign only if a hit comes from
    // an MCP server or HTTP tool ticked „may contain untrusted content“
    // (third parties write those descriptions). Fail-closed: unreadable
    // result, unknown name or unknown origin count as foreign.
    try {
      final text = content.whereType<TextBlock>().map((b) => b.text).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['tools'] is! List) return false;
      final byName = {for (final e in _candidates) e.tool.name: e.tool};
      for (final hit in decoded['tools'] as List) {
        final tool = hit is Map ? byName[hit['name']] : null;
        if (tool == null) return false;
        final safe = switch (tool) {
          ContentTrustAware(:final mayContainUntrustedContent) =>
            !mayContainUntrustedContent,
          TrustedContentSource() || NoNetworkTarget() => true,
          _ => _builtInNetworkTools.contains(tool.name),
        };
        if (!safe) return false;
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  String get name => toolName;

  @override
  String get description =>
      'Es gibt viele Tools; sie werden erst nach einer Suche freigeschaltet. '
      'Sucht passende Tools per Stichwort (query) und/oder Kategorie '
      '(category) und schaltet die Treffer frei; danach direkt aufrufen. '
      'Kategorien: '
      '${categories.entries.map((e) => '${e.key} (${e.value})').join(', ')}.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Stichworte, z. B. „Termin anlegen“',
        'maxLength': 200,
      },
      'category': {
        'type': 'string',
        'enum': categories.keys.toList(),
        'description': 'Nur Tools dieser Kategorie',
      },
    },
    'additionalProperties': false,
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  String describeForConfirmation(Map<String, Object?> args) => 'Tools suchen';

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final query = (args['query'] as String?)?.trim() ?? '';
    final category = args['category'] as String?;
    if (query.isEmpty && category == null) {
      return ToolOutcome.error('Bitte query oder category angeben.');
    }
    final found = search(
      query,
      category: category,
      languageTag: languageFor?.call(ctx.sessionId) ?? ctx.locale,
    );
    unlock(ctx.sessionId, [for (final t in found) t.name]);
    final json = jsonEncode({
      'tools': [
        for (final t in found)
          {
            'name': t.name,
            'description': t.description,
            'input_schema': t.inputSchema,
          },
      ],
      if (found.isEmpty)
        'hinweis':
            'Keine passenden Tools. Andere Stichworte oder eine '
            'Kategorie versuchen.',
    });
    return ToolOutcome.text(
      json,
      summary: found.isEmpty
          ? 'Keine Tools gefunden'
          : '${found.length} Tools freigeschaltet',
    );
  }

  /// Tools matching [query] (any word, case-insensitive, in name,
  /// description or integration name, or topic word of the language of
  /// [languageTag]) and [category], best first.
  List<Tool> search(String query, {String? category, String? languageTag}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length >= 2)
        .toSet();
    // German and French requests: the topic words of the integration count
    // as well (descriptions are English).
    final topical = topicIntegrationsIn(
      query,
      languageTag: languageTag,
    ).toSet();
    final scored = <(int, Tool)>[];
    for (final (:integration, :tool) in _candidates) {
      if (category != null && integration.id != category) continue;
      final haystack = [
        tool.name,
        tool.description,
        integration.id,
        integration.displayName,
      ].join(' ').toLowerCase();
      final score =
          words.where(haystack.contains).length +
          (topical.contains(integration.id) ? 2 : 0);
      if (score > 0 || words.isEmpty) scored.add((score, tool));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.name.compareTo(b.$2.name);
    });
    return [for (final (_, t) in scored.take(maxResults)) t];
  }
}
