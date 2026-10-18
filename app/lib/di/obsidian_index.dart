import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../l10n/l10n.dart';
import 'providers.dart';

/// State of the Obsidian search index build.
@immutable
final class IndexProgress {
  /// Creates a state.
  const IndexProgress({
    this.running = false,
    this.indexed = 0,
    this.pending = 0,
    this.failed = 0,
    this.complete = false,
    this.total,
    this.error,
  });

  /// Whether a build runs.
  final bool running;

  /// Notes (re)indexed in this build.
  final int indexed;

  /// Changed notes still waiting.
  final int pending;

  /// Notes that could not be read in the last run.
  final int failed;

  /// Whether the last run walked the whole vault.
  final bool complete;

  /// Notes in the index after the build.
  final int? total;

  /// Why the build stopped.
  final String? error;

  /// Share done while running (`null` = unknown).
  double? get fraction =>
      indexed + pending == 0 ? null : indexed / (indexed + pending);

  /// Status line for the settings.
  String labelOf(AppLocalizations l) {
    if (error case final e?) return l.obsIndexIncomplete(e);
    if (running) {
      return pending == 0
          ? l.obsIndexBuilding
          : l.obsIndexBuildingProgress(indexed, pending);
    }
    final t = total;
    if (t == null) return l.obsIndexNotBuilt;
    final notes = l.obsIndexNotes(t);
    if (!complete) return l.obsIndexPartial(notes);
    if (failed > 0) return l.obsIndexUnreadable(notes, failed);
    return l.obsIndexCurrent(notes);
  }
}

/// Builds the Obsidian search index in the background.
final obsidianIndexProvider =
    NotifierProvider<ObsidianIndexController, IndexProgress>(
      ObsidianIndexController.new,
    );

/// Repeats `NoteIndexer.sync()` until nothing is pending (a large vault
/// needs several runs of at most 200 notes, see the Obsidian README),
/// reporting progress. Runs after the vault was chosen, on request in the
/// settings and at app start while the integration is on. Searches of the
/// integration share the same indexer and join a running sync.
final class ObsidianIndexController extends Notifier<IndexProgress> {
  /// Upper bound of runs per build (200 notes each).
  static const maxRuns = 500;

  Future<IndexProgress>? _running;

  @override
  IndexProgress build() => const IndexProgress();

  /// Builds the index until `pending == 0`; a call while a build runs
  /// joins it. Without a vault nothing happens.
  Future<IndexProgress> sync() => _running ??= _sync().whenComplete(() {
    _running = null;
  });

  Future<IndexProgress> _sync() async {
    final ports = ref.read(platformPortsProvider).obsidian;
    if (ports == null || !ports.hasVault()) return state;
    state = const IndexProgress(running: true);
    var indexed = 0;
    try {
      for (var run = 0; run < maxRuns; run++) {
        final r = await ports.indexer.sync();
        indexed += r.indexed;
        state = IndexProgress(
          running: true,
          indexed: indexed,
          pending: r.pending,
          failed: r.failed,
          complete: r.complete,
        );
        // Done, or a run made no progress (only unreadable notes left).
        if (r.pending == 0 || r.indexed == 0) break;
      }
      final total = (await ports.index.knownFiles()).length;
      return state = IndexProgress(
        indexed: indexed,
        failed: state.failed,
        complete: state.complete,
        total: total,
      );
    } on PortException catch (e) {
      return state = IndexProgress(
        indexed: indexed,
        pending: state.pending,
        error: e.message,
      );
    }
  }
}
