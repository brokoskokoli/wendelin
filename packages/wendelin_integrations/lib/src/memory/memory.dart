import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';

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
    this.privacyFloor,
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

  /// Set when saved by a private (or tainted) run: only targets with at
  /// least this privacy level may see the entry (ADR 0009).
  final PrivacyLevel? privacyFloor;

  /// Whether a target with [level] may see this entry (`null` = unknown
  /// level: only entries without floor).
  bool visibleTo(PrivacyLevel? level) =>
      privacyFloor == null || (level != null && level.isAtLeast(privacyFloor!));

  @override
  bool operator ==(Object other) =>
      other is MemoryEntry &&
      other.id == id &&
      other.text == text &&
      other.category == category &&
      other.source == source &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt &&
      other.privacyFloor == privacyFloor;

  @override
  int get hashCode => Object.hash(
    id,
    text,
    category,
    source,
    createdAt,
    lastUsedAt,
    privacyFloor,
  );

  @override
  String toString() => 'MemoryEntry($id, ${category.name}, $text)';
}

/// Long-term memory store. The app wires it to `MemoryRepository`
/// (`wendelin_storage`); must pass `memoryStoreContract`.
abstract interface class MemoryStorePort {
  /// Memory namespace [owner] (WP92b): `''` is the default memory, another
  /// value one person's. Every method sees and changes only its own
  /// namespace; an id of another namespace is `notFound`.
  ///
  /// Saves [text] (with [privacyFloor], kept as given). Throws
  /// `PortException(rejected)` for sensitive content (see core's
  /// [detectSensitiveContent]) and [ArgumentError] for blank text.
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
    String owner = '',
  });

  /// The [limit] most relevant entries for [query] (empty if none); marks
  /// them as used.
  Future<List<MemoryEntry>> search(
    String query, {
    int limit = 5,
    String owner = '',
  });

  /// Deletes the entry [id] and returns it. Throws `PortException(notFound)`
  /// for unknown ids.
  Future<MemoryEntry> forget(String id, {String owner = ''});

  /// All entries, newest first.
  Future<List<MemoryEntry>> list({String owner = ''});
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
final class MemorySaveTool extends IntegrationTool
    implements TrustedContentSource, FixedConfirmationTool, NoNetworkTarget {
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

  @override
  Set<String> get confirmationKeys => const {'memory.saved'};

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
    final finding = detectSensitiveContent(a.text);
    if (finding != null) {
      throw PortException(PortErrorKind.rejected, finding.reason);
    }
    final owner = ctx.memoryOwner;
    final entry = await store.save(
      a.text,
      category: a.category,
      source: 'session:${ctx.sessionId}',
      privacyFloor: ctx.privacyFloor,
      owner: ctx.memoryOwner,
    );
    return jsonOutcome(
      {'saved': _entryJson(entry)},
      summary: 'Gemerkt: ${ellipsize(entry.text, 50)}',
      fixed: const ConfirmationSentence('memory.saved'),
      undo: UndoAction(
        label: 'Vergessen',
        run: () async => store.forget(entry.id, owner: owner),
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
final class MemorySearchTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
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
    // Entries of private runs only for targets of their level.
    final found = [
      for (final e in await store.search(
        query,
        limit: limit,
        owner: ctx.memoryOwner,
      ))
        if (e.visibleTo(ctx.privacyLevel)) e,
    ];
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
///
/// Undo re-saves text, category and source; the entry gets a new id and new
/// timestamps (`createdAt` = now, `lastUsedAt` empty).
final class MemoryForgetTool extends IntegrationTool
    implements TrustedContentSource, NoNetworkTarget {
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
    final id = args.requireString('id');
    // Entries of private runs do not exist for weaker targets.
    final owner = ctx.memoryOwner;
    final hidden = (await store.list(owner: owner))
        .any((e) => e.id == id && !e.visibleTo(ctx.privacyLevel));
    if (hidden) {
      throw PortException(
        PortErrorKind.notFound,
        'Eintrag „$id“ gibt es nicht',
      );
    }
    final removed = await store.forget(id, owner: owner);
    return jsonOutcome(
      {'forgotten': removed.id},
      summary: 'Vergessen: ${ellipsize(removed.text, 50)}',
      undo: UndoAction(
        label: 'Wiederherstellen',
        run: () async => store.save(
          removed.text,
          category: removed.category,
          source: removed.source,
          privacyFloor: removed.privacyFloor,
          owner: owner,
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
