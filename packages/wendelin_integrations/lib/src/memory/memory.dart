import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'sensitive_content.dart';

/// Kind of a memory entry (concept: person, vorliebe, fakt, projekt).
enum MemoryCategory {
  /// A person in the user's life.
  person,

  /// A preference („mag keinen Koriander“).
  preference,

  /// A fact („wohnt in Hamburg“).
  fact,

  /// A project the user works on.
  project,
}

/// A stored memory entry.
@immutable
final class MemoryEntry {
  /// Creates an entry.
  const MemoryEntry({
    required this.id,
    required this.text,
    required this.category,
    required this.source,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Id.
  final String id;

  /// The remembered text.
  final String text;

  /// Category.
  final MemoryCategory category;

  /// Where it came from, e.g. `session:<id>`.
  final String source;

  /// When it was saved.
  final DateTime createdAt;

  /// When it was last returned by a search, if ever.
  final DateTime? lastUsedAt;

  @override
  bool operator ==(Object other) =>
      other is MemoryEntry &&
      other.id == id &&
      other.text == text &&
      other.category == category &&
      other.source == source &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(id, text, category, source, createdAt, lastUsedAt);

  @override
  String toString() => 'MemoryEntry($id, ${category.name}, $text)';
}

/// Long-term memory store. The app wires it to `MemoryRepository`
/// (`wendelin_storage`); must pass `memoryStoreContract`.
abstract interface class MemoryStorePort {
  /// Saves [text]. Throws `PortException(rejected)` for sensitive content
  /// (see [sensitiveContentReason]) and [ArgumentError] for blank text.
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
  });

  /// The [limit] most relevant entries for [query] (empty if none); marks
  /// them as used.
  Future<List<MemoryEntry>> search(String query, {int limit = 5});

  /// Deletes the entry [id] and returns it. Throws `PortException(notFound)`
  /// for unknown ids.
  Future<MemoryEntry> forget(String id);

  /// All entries, newest first.
  Future<List<MemoryEntry>> list();
}

/// Memory: `memory__save`, `memory__search`, `memory__forget`.
final class MemoryIntegration implements Integration {
  /// Creates the integration on [store].
  MemoryIntegration(this.store);

  /// Memory store.
  final MemoryStorePort store;

  @override
  String get id => 'memory';

  @override
  String get displayName => 'Gedächtnis';

  @override
  String get iconId => 'memory';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState();

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    MemorySaveTool(store),
    MemorySearchTool(store),
    MemoryForgetTool(store),
  ]);
}

Map<String, Object?> _entryJson(MemoryEntry e) => {
  'id': e.id,
  'text': e.text,
  'category': e.category.name,
};

/// `memory__save` (write, undo forgets the entry).
final class MemorySaveTool extends IntegrationTool {
  /// Creates the tool.
  const MemorySaveTool(this.store);

  /// Memory store.
  final MemoryStorePort store;

  /// Longest text accepted.
  static const maxChars = 500;

  @override
  String get name => 'memory__save';

  @override
  String get description =>
      'Remember a fact about the user for later conversations. Use ONLY '
      'when the user explicitly asks ("merk dir …", "remember …"). Never '
      'save passwords, PINs, card or bank numbers. Example: text "Mag keinen '
      'Koriander", category "preference".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'text': {
        'type': 'string',
        'description': 'One short sentence, in the user\'s words.',
      },
      'category': {
        'type': 'string',
        'enum': ['person', 'preference', 'fact', 'project'],
        'description': 'Kind of memory.',
      },
    },
    'required': ['text', 'category'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  ({String text, MemoryCategory category}) _read(ToolArgs args) {
    final text = args.requireString('text');
    if (text.length > maxChars) {
      throw const InvalidArgumentsException(
        '„text“ ist zu lang (höchstens $maxChars Zeichen)',
      );
    }
    final raw = args.requireString('category');
    final category = MemoryCategory.values
        .where((c) => c.name == raw)
        .firstOrNull;
    if (category == null) {
      throw InvalidArgumentsException(
        '„category“ muss person, preference, fact oder project sein '
        '(war „$raw“)',
      );
    }
    return (text: text, category: category);
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final a = _read(args);
    final reason = sensitiveContentReason(a.text);
    if (reason != null) {
      throw PortException(PortErrorKind.rejected, reason);
    }
    final entry = await store.save(
      a.text,
      category: a.category,
      source: 'session:${ctx.sessionId}',
    );
    return jsonOutcome(
      {'saved': _entryJson(entry)},
      summary: 'Gemerkt: ${ellipsize(entry.text, 50)}',
      undo: UndoAction(
        label: 'Vergessen',
        run: () async => store.forget(entry.id),
      ),
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Merken: ${ellipsize(_read(args).text, 60)}';

  @override
  String get fallbackDescription => 'Etwas merken';
}

/// `memory__search` (read).
final class MemorySearchTool extends IntegrationTool {
  /// Creates the tool.
  const MemorySearchTool(this.store);

  /// Memory store.
  final MemoryStorePort store;

  @override
  String get name => 'memory__search';

  @override
  String get description =>
      'Search what you remembered about the user. Example: query '
      '"Koriander". Returns ids needed for memory__forget.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search words.'},
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': 'Most results (default 5).',
      },
    },
    'required': ['query'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('query');
    final limit = args.optInt('limit', min: 1, max: 20) ?? 5;
    final found = await store.search(query, limit: limit);
    return jsonOutcome(
      {
        'memories': [for (final e in found.take(limit)) _entryJson(e)],
      },
      summary: found.isEmpty
          ? 'Nichts gefunden'
          : '${found.length} Erinnerungen gefunden',
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Gedächtnis durchsuchen: ${args.requireString('query')}';

  @override
  String get fallbackDescription => 'Gedächtnis durchsuchen';
}

/// `memory__forget` (write, undo saves the entry again).
final class MemoryForgetTool extends IntegrationTool {
  /// Creates the tool.
  const MemoryForgetTool(this.store);

  /// Memory store.
  final MemoryStorePort store;

  @override
  String get name => 'memory__forget';

  @override
  String get description =>
      'Delete a remembered fact by id (from memory__search) when the user '
      'asks you to forget it.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'Id of the memory.'},
    },
    'required': ['id'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final removed = await store.forget(args.requireString('id'));
    return jsonOutcome(
      {'forgotten': removed.id},
      summary: 'Vergessen: ${ellipsize(removed.text, 50)}',
      undo: UndoAction(
        label: 'Wiederherstellen',
        run: () async => store.save(
          removed.text,
          category: removed.category,
          source: removed.source,
        ),
      ),
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Erinnerung ${args.requireString('id')} vergessen';

  @override
  String get fallbackDescription => 'Erinnerung vergessen';
}
