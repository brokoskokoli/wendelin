import 'dart:async';

import 'package:meta/meta.dart';

import '../common/port_exception.dart';
import 'ports.dart';
import 'vault_path.dart';

/// Result of one [NoteIndexer.sync] run.
@immutable
final class IndexSyncReport {
  /// Creates a report.
  const IndexSyncReport({
    required this.indexed,
    required this.removed,
    required this.pending,
    required this.failed,
    required this.complete,
  });

  /// Notes (re)indexed in this run.
  final int indexed;

  /// Notes removed from the index (deleted in the vault).
  final int removed;

  /// Changed notes left for later runs (limit per run reached).
  final int pending;

  /// Notes that could not be read (skipped, retried next run).
  final int failed;

  /// Whether the whole vault was walked (removals only happen then).
  final bool complete;

  @override
  String toString() =>
      'IndexSyncReport(indexed: $indexed, removed: $removed, '
      'pending: $pending, failed: $failed, complete: $complete)';
}

/// Keeps the [NoteIndexPort] in step with the [VaultPort], incrementally:
/// only `.md` files whose modification time differs from the indexed one
/// are read, at most [maxFilesPerRun] per run (newest first). Hidden
/// folders (`.obsidian/`, `.trash/`) and non-Markdown files (attachments)
/// are ignored.
final class NoteIndexer {
  /// Creates the indexer.
  NoteIndexer(
    this.vault,
    this.index, {
    this.maxFilesPerRun = 200,
    this.maxEntries = 20000,
    this.maxFileBytes = 1024 * 1024,
    this.maxIndexedChars = 100000,
  });

  /// Vault.
  final VaultPort vault;

  /// Index.
  final NoteIndexPort index;

  /// Most notes read per run.
  final int maxFilesPerRun;

  /// Most folder entries walked per run; beyond that the walk is
  /// incomplete and nothing is removed.
  final int maxEntries;

  /// Larger files are indexed by title only.
  final int maxFileBytes;

  /// Longest body text stored per note.
  final int maxIndexedChars;

  Future<IndexSyncReport>? _running;

  /// Runs one sync; a call while another runs joins that run.
  Future<IndexSyncReport> sync() => _running ??= _sync().whenComplete(() {
    _running = null;
  });

  Future<IndexSyncReport> _sync() async {
    final files = <String, VaultEntry>{};
    final folders = [VaultPath.root];
    var walked = 0;
    var complete = true;
    while (folders.isNotEmpty) {
      final folder = folders.removeLast();
      for (final e in await vault.list(folder)) {
        if (++walked > maxEntries) {
          complete = false;
          break;
        }
        if (VaultPath.isHidden(e.name)) continue;
        if (e.isFolder) {
          folders.add(e.path);
        } else if (e.path.toLowerCase().endsWith('.md')) {
          files[e.path] = e;
        }
      }
      if (!complete) break;
    }
    final known = await index.knownFiles();
    final changed = <(String, DateTime)>[];
    for (final MapEntry(key: path, value: e) in files.entries) {
      final modified = e.modifiedAt ?? await vault.modifiedAt(path);
      final had = known[path];
      if (had == null || !had.isAtSameMomentAs(modified)) {
        changed.add((path, modified));
      }
    }
    changed.sort((a, b) => b.$2.compareTo(a.$2));
    var indexed = 0;
    var failed = 0;
    for (final (path, modified) in changed.take(maxFilesPerRun)) {
      try {
        final size = files[path]!.size ?? await vault.size(path);
        final body = size > maxFileBytes ? '' : await vault.read(path);
        await index.upsert(
          path,
          title: VaultPath.title(path),
          body: body.length > maxIndexedChars
              ? body.substring(0, maxIndexedChars)
              : body,
          modifiedAt: modified,
        );
        indexed++;
      } on PortException {
        // Nicht lesbar (gerade gelöscht, Rechte): beim nächsten Lauf erneut.
        failed++;
      }
    }
    var removed = 0;
    if (complete) {
      for (final path in known.keys) {
        if (files.containsKey(path)) continue;
        await index.remove(path);
        removed++;
      }
    }
    return IndexSyncReport(
      indexed: indexed,
      removed: removed,
      pending: changed.length > maxFilesPerRun
          ? changed.length - maxFilesPerRun
          : 0,
      failed: failed,
      complete: complete,
    );
  }
}
