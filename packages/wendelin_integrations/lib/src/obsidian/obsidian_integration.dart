import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/file_queue.dart';
import '../common/matching.dart';
import '../common/port_exception.dart';
import '../markdown/markdown_doc.dart';
import 'daily_notes.dart';
import 'note_indexer.dart';
import 'obsidian_tools.dart';
import 'ports.dart';
import 'vault_path.dart';

/// Opens an `obsidian://` link (the app: `url_launcher` or an intent).
typedef OpenUri = Future<void> Function(Uri uri);

/// Settings of the Obsidian integration (from the app settings).
@immutable
final class ObsidianSettings {
  /// Creates the settings.
  const ObsidianSettings({
    this.vaultName,
    this.dailyNotes = const DailyNoteSettings(),
    this.locale = 'de',
  });

  /// Vault name as Obsidian knows it (for `obsidian://open`); `null` while
  /// no vault folder is chosen.
  final String? vaultName;

  /// Daily-note location, format and template.
  final DailyNoteSettings dailyNotes;

  /// Language of month and weekday names in daily-note names (`de`, `en`,
  /// `fr`), like the Obsidian app language.
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is ObsidianSettings &&
      other.vaultName == vaultName &&
      other.dailyNotes == dailyNotes &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(vaultName, dailyNotes, locale);
}

/// Obsidian: notes in the user's vault (`obsidian__…` tools).
final class ObsidianIntegration implements Integration {
  /// Creates the integration on [vault] and [index]. [settings] is read on
  /// every tool call; [openUri] opens `obsidian://` links (without it,
  /// `obsidian__open_note` only returns the link).
  ObsidianIntegration(
    VaultPort vault,
    NoteIndexPort index, {
    required ObsidianSettings Function() settings,
    OpenUri? openUri,
    NoteIndexer? indexer,
  }) : env = ObsidianEnv(
         vault: vault,
         index: index,
         settings: settings,
         openUri: openUri,
         indexer: indexer,
       );

  /// Id of the setup step „choose the vault folder“.
  static const vaultStep = 'vault_folder';

  /// Shared tool state.
  final ObsidianEnv env;

  @override
  String get id => 'obsidian';

  @override
  String get displayName => 'Obsidian';

  @override
  String get iconId => 'note';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  /// Notes are personal (journal, projects): sensitive by default (the
  /// user can switch it, K9).
  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: vaultStep,
      kind: SetupStepKind.folder,
      label: 'Obsidian-Vault-Ordner wählen',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (env.settings().vaultName == null) vaultStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    SearchNotesTool(env),
    ReadNoteTool(env),
    ListFolderTool(env),
    CreateNoteTool(env),
    AppendToNoteTool(env),
    AppendDailyNoteTool(env),
    ReplaceSectionTool(env),
    OpenNoteTool(env),
  ]);
}

/// A note read from the vault.
final class LoadedNote {
  /// Creates a loaded note.
  LoadedNote(this.path, this.doc);

  /// Vault path.
  final String path;

  /// Parsed content (ATX and setext headings).
  final MarkdownDoc doc;
}

/// Shared state of the Obsidian tools.
final class ObsidianEnv {
  /// Creates the environment.
  ObsidianEnv({
    required this.vault,
    required this.index,
    required this.settings,
    this.openUri,
    NoteIndexer? indexer,
    this.minSyncInterval = const Duration(seconds: 30),
  }) : indexer = indexer ?? NoteIndexer(vault, index);

  /// Vault access.
  final VaultPort vault;

  /// Search index.
  final NoteIndexPort index;

  /// Current settings.
  final ObsidianSettings Function() settings;

  /// Opens `obsidian://` links, if the app supports it.
  final OpenUri? openUri;

  /// Index synchronization.
  final NoteIndexer indexer;

  /// Shortest time between two index syncs without own writes in between.
  final Duration minSyncInterval;

  /// Largest note the tools read or change.
  static const maxNoteBytes = 2 * 1024 * 1024;

  DateTime? _lastSync;
  bool _dirty = true;

  /// Replace-section confirmations shown to the user: key → section text
  /// the diff was built on (checked again before writing).
  final Map<String, String> prepared = {};

  /// Marks the index as outdated (after own writes); the next search
  /// syncs.
  void markDirty() => _dirty = true;

  /// Syncs the index if it is outdated or [minSyncInterval] has passed
  /// since the last sync at [now]; returns the report or `null` if
  /// skipped.
  Future<IndexSyncReport?> syncIndex(DateTime now) async {
    final last = _lastSync;
    if (!_dirty && last != null && now.difference(last) < minSyncInterval) {
      return null;
    }
    _dirty = false;
    var ok = false;
    try {
      final report = await indexer.sync();
      _lastSync = now;
      ok = report.pending == 0 && report.failed == 0;
      return report;
    } finally {
      if (!ok) _dirty = true;
    }
  }

  /// Runs [body] exclusively for the note [path], process-wide (see
  /// [FileQueue]).
  Future<T> exclusive<T>(String path, Future<T> Function() body) =>
      FileQueue.run('vault:$path', body);

  /// The note [query] names: the exact path (`.md` optional) if it
  /// exists, else the indexed note whose title matches best (case,
  /// umlauts, plural, whole words). Several equally good notes →
  /// „Mehrdeutig“; with [write] a match on whole words only is asked back.
  Future<String> resolveNote(
    String query, {
    required bool write,
    required DateTime now,
  }) async {
    final path = VaultPath.note(query);
    if (await vault.exists(path)) return path;
    await syncIndex(now);
    final known = (await index.knownFiles()).keys.toList()..sort();
    final folder = VaultPath.parent(path);
    final inFolder = folder.isEmpty
        ? known
        : [
            for (final k in known)
              if (foldText(VaultPath.parent(k)) == foldText(folder)) k,
          ];
    final m = bestMatches(
      VaultPath.title(path),
      inFolder,
      (k) => [VaultPath.title(k)],
    );
    if (m.best.isEmpty) {
      throw PortException(
        PortErrorKind.notFound,
        'Notiz „$query“ gibt es nicht. obsidian__search_notes hilft beim '
        'Finden.',
      );
    }
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: „$query“ passt zu ${m.best.take(5).join(', ')}. '
        'Bitte nachfragen, welche Notiz gemeint ist.',
      );
    }
    if (write && m.score == 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Meintest du die Notiz „${m.best.single}“? Bitte nachfragen.',
      );
    }
    return m.best.single;
  }

  /// Reads and parses the note [path]; refuses notes larger than
  /// [maxNoteBytes].
  Future<LoadedNote> load(String path) async {
    if (await vault.size(path) > maxNoteBytes) {
      throw PortException(
        PortErrorKind.rejected,
        'Notiz „$path“ ist größer als ${maxNoteBytes ~/ (1024 * 1024)} MB',
      );
    }
    final content = await vault.read(path);
    return LoadedNote(path, MarkdownDoc.parse(content, setext: true));
  }

  /// Writes [note] back and marks the index as outdated.
  Future<void> save(LoadedNote note) async {
    markDirty();
    await vault.write(note.path, note.doc.toString());
  }

  /// The heading of [doc] that [query] names (fuzzy, like list names), or
  /// `null` if none matches. Several headings → „Mehrdeutig“ (also for the
  /// same title twice); with [write] a match on whole words only is asked
  /// back.
  MdHeading? pickHeading(
    MarkdownDoc doc,
    String query,
    String path, {
    required bool write,
  }) {
    final m = bestMatches(query, doc.headings, (h) => [h.title]);
    if (m.best.isEmpty) return null;
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: Überschrift „$query“ passt in „$path“ zu '
        '${m.best.map((h) => '„${h.title}“ (Zeile ${h.line + 1})').join(', ')}. '
        'Bitte nachfragen.',
      );
    }
    if (write && m.score == 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Meintest du die Überschrift „${m.best.single.title}“? Bitte '
        'nachfragen.',
      );
    }
    return m.best.single;
  }
}
