import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'lists.dart';

/// `lists__list_lists` (read).
final class ListListsTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const ListListsTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'lists__list_lists';

  @override
  String get description =>
      'Show the user\'s lists (e.g. shopping, projects) with the number of '
      'open items.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final defs = env.definitions();
    final result = <Map<String, Object?>>[];
    for (final d in defs) {
      try {
        final l = await env.load(d);
        result.add({
          'name': d.name,
          if (d.aliases.isNotEmpty) 'aliases': d.aliases,
          'open': l.items.where((i) => !i.done).length,
          if (!l.existed) 'missing_file': true,
        });
      } on PortException catch (e) {
        result.add({'name': d.name, 'error': e.message});
      }
    }
    return jsonOutcome({'lists': result}, summary: '${defs.length} Listen');
  }

  @override
  String describe(ToolArgs args) => 'Listen anzeigen';

  @override
  String get fallbackDescription => 'Listen anzeigen';
}

/// `lists__get_items` (read).
final class GetItemsTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const GetItemsTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'lists__get_items';

  @override
  String get description =>
      'Show the items of a list. Example: list "Einkaufen". Done items only '
      'with include_done true.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'list': listProp,
      'include_done': {
        'type': 'boolean',
        'description': 'Also show checked items (default false).',
      },
    },
    'required': ['list'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final def = env.resolve(args.requireString('list'), write: false);
    final withDone = args.optBool('include_done') ?? false;
    final l = await env.load(def);
    final items = l.items;
    final open = items.where((i) => !i.done).length;
    return ToolOutcome.text(
      '$listDataNotice\n${jsonEncode({
        'list': def.name,
        'items': [
          for (final i in items)
            if (withDone || !i.done) {'text': i.text, if (i.done) 'done': true},
        ],
        if (!withDone && items.length > open) 'done_hidden': items.length - open,
        if (!l.existed) 'missing_file': true,
      })}',
      summary: '${def.name}: $open offen',
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Liste ${args.requireString('list')} anzeigen';

  @override
  String get fallbackDescription => 'Liste anzeigen';
}
