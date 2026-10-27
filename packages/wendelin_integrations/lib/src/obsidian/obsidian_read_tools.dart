import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/data_envelope.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import '../markdown/markdown_doc.dart';
import 'obsidian_integration.dart';
import 'obsidian_tool_support.dart';
import 'vault_path.dart';

/// `obsidian__search_notes` (read).
final class SearchNotesTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const SearchNotesTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__search_notes';

  @override
  String get description =>
      'Full-text search in the user\'s Obsidian notes. Returns path, title '
      'and a snippet per note. Example: query "Tauchurlaub Malta".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search words.'},
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': 'Number of notes (default 8).',
      },
    },
    'required': ['query'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('query');
    final limit = args.optInt('limit', min: 1, max: 20) ?? 8;
    final report = await env.syncIndex(ctx.clock.now());
    final hits = await env.index.search(query, limit: limit);
    return ToolOutcome.text(
      '$noteDataNotice\n<note_search_results>\n'
      '${escape(jsonEncode({
        'results': [
          for (final h in hits) {'path': h.path, 'title': h.title, 'snippet': h.snippet},
        ],
        if (report != null && (report.pending > 0 || !report.complete)) 'index_incomplete': true,
      }))}'
      '\n</note_search_results>',
      summary: hits.isEmpty
          ? 'Notizsuche: nichts gefunden'
          : 'Notizsuche: ${hits.length} Treffer',
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Notizen durchsuchen: ${args.requireString('query')}';

  @override
  String get fallbackDescription => 'Notizen durchsuchen';
}

/// `obsidian__read_note` (read): content marked as data, optionally one
/// section.
final class ReadNoteTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const ReadNoteTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  /// Default and maximum characters returned.
  static const defaultChars = 20000;

  /// Upper bound for `max_chars`.
  static const maxChars = 50000;

  @override
  String get name => 'obsidian__read_note';

  @override
  String get description =>
      'Read an Obsidian note. Optional heading returns only that section. '
      'Example: path "Projekte/Wendelin", heading "Ideen".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'path': pathProp,
      'heading': {
        'type': 'string',
        'description': 'Only the section below this heading.',
      },
      'max_chars': {
        'type': 'integer',
        'minimum': 500,
        'maximum': maxChars,
        'description': 'Longest text to return (default $defaultChars).',
      },
    },
    'required': ['path'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('path');
    final heading = args.optString('heading');
    final limit =
        args.optInt('max_chars', min: 500, max: maxChars) ?? defaultChars;
    final found = await env.resolveForRead(query, ctx.clock.now());
    final path = found.path;
    final note = await env.load(path);
    final doc = note.doc;
    var text = doc.toString();
    MdHeading? h;
    if (heading != null && heading.isNotEmpty) {
      h = env.pickHeading(doc, heading, path, write: false);
      if (h == null) {
        throw PortException(
          PortErrorKind.notFound,
          'Überschrift „$heading“ gibt es in ${vaultNames([path])} nicht. '
          'Vorhanden: ${vaultNames(doc.headings.map((x) => x.title).take(30))}',
        );
      }
      final r = doc.sectionOf(h);
      text = doc.lines.sublist(h.line, r.end).join();
    } else if (doc.bom.isNotEmpty) {
      text = text.substring(1);
    }
    final cut = truncateText(text, limit);
    return ToolOutcome.text(
      '$noteDataNotice\n${approximateNotice(query, found)}'
      '<note_content path="${escapeDataAttr(path)}"${matchAttribute(found)}'
      '${h == null ? '' : ' heading="${escapeDataAttr(h.title)}"'}'
      '${cut.truncated ? ' truncated="true"' : ''}>\n'
      '${escape(cut.text)}\n'
      '</note_content>',
      summary: 'Notiz gelesen: ${VaultPath.title(path)}',
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Notiz lesen: ${args.requireString('path')}';

  @override
  String get fallbackDescription => 'Notiz lesen';
}

/// `obsidian__list_folder` (read).
final class ListFolderTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const ListFolderTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  /// Most entries per kind returned.
  static const maxEntries = 200;

  @override
  String get name => 'obsidian__list_folder';

  @override
  String get description =>
      'List the sub-folders and notes of a vault folder. Example: folder '
      '"Projekte"; empty for the vault root.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'folder': {
        'type': 'string',
        'description': 'Vault folder, e.g. "Projekte"; empty = root.',
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final folder = VaultPath.normalize(
      args.optString('folder') ?? '',
      allowRoot: true,
    );
    final entries = [
      for (final e in await env.vault.list(folder))
        if (!VaultPath.isHidden(e.name)) e,
    ];
    final folders = [
      for (final e in entries)
        if (e.isFolder) e.name,
    ]..sort();
    final notes = [
      for (final e in entries)
        if (!e.isFolder && e.name.toLowerCase().endsWith('.md'))
          VaultPath.title(e.path),
    ]..sort();
    final others = entries.length - folders.length - notes.length;
    return ToolOutcome.text(
      '$noteDataNotice\n<folder_listing>\n'
      '${escape(jsonEncode({'folder': folder, 'folders': folders.take(maxEntries).toList(), 'notes': notes.take(maxEntries).toList(), if (folders.length > maxEntries) 'more_folders': folders.length - maxEntries, if (notes.length > maxEntries) 'more_notes': notes.length - maxEntries, if (others > 0) 'other_files': others}))}'
      '\n</folder_listing>',
      summary:
          '${folder.isEmpty ? 'Vault' : folder}: ${folders.length} Ordner, '
          '${notes.length} Notizen',
    );
  }

  @override
  String describe(ToolArgs args) {
    final f = args.optString('folder') ?? '';
    return 'Ordner anzeigen: ${f.isEmpty ? 'Vault' : f}';
  }

  @override
  String get fallbackDescription => 'Ordner anzeigen';
}

/// `obsidian__open_note` (write): opens the note in the Obsidian app via
/// an `obsidian://open` link.
final class OpenNoteTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource, WorksOnlyUnlocked {
  /// Creates the tool.
  const OpenNoteTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__open_note';

  @override
  String get description =>
      'Open a note in the Obsidian app on the device. Example: path '
      '"Projekte/Wendelin".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {'path': pathProp},
    'required': ['path'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  /// The `obsidian://open` link for [path] in [vault].
  static Uri link(String vault, String path) {
    final file = path.toLowerCase().endsWith('.md')
        ? path.substring(0, path.length - 3)
        : path;
    return Uri.parse(
      'obsidian://open?vault=${Uri.encodeComponent(vault)}'
      '&file=${Uri.encodeComponent(file)}',
    );
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final vault = env.settings().vaultName;
    if (vault == null) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Kein Vault eingerichtet (Einstellungen → Obsidian)',
      );
    }
    final path = await env.resolveNote(
      args.requireString('path'),
      write: false,
      now: ctx.clock.now(),
    );
    final uri = link(vault, path);
    final open = env.openUri;
    if (open != null) await open(uri);
    return jsonOutcome({
      'note': path,
      'uri': uri.toString(),
      'opened': open != null,
    }, summary: 'Obsidian: ${VaultPath.title(path)}');
  }

  @override
  String describe(ToolArgs args) =>
      'Notiz „${args.requireString('path')}“ in Obsidian öffnen';

  @override
  String get fallbackDescription => 'Notiz in Obsidian öffnen';
}
