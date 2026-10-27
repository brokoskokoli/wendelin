import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../voice/dev_archive.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Size as text: `12 MB`, `3.4 GB` (decimal point as in the code, the unit
/// is the same in every language).
String devArchiveSizeText(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) {
    return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

/// The state of the archive (number of cases and size); read again on demand.
final devArchiveStatsProvider = FutureProvider.autoDispose(
  (ref) => devArchiveStats(),
);

/// Developer settings (WP155): size of the wake word archive and the button
/// to delete it (with a question first).
class DevArchiveSection extends ConsumerWidget {
  /// Creates the section.
  const DevArchiveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final stats = ref.watch(devArchiveStatsProvider).value;
    final summary = stats == null || stats.cases == 0
        ? l.devArchiveEmpty
        : l.devArchiveSummary(stats.cases, devArchiveSizeText(stats.bytes));
    return Padding(
      padding: const EdgeInsets.only(top: WSpace.m),
      child: SectionCard(
        children: [
          SettingsRow(
            title: l.devArchiveTitle,
            detail: summary,
            trailing: TextButton(
              onPressed: stats == null || stats.cases == 0
                  ? null
                  : () => unawaited(_delete(context, ref, stats)),
              child: Text(l.devArchiveDelete),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ({int cases, int bytes}) stats,
  ) async {
    final l = context.l10n;
    final yes = await confirm(
      context,
      title: l.devArchiveDeleteTitle,
      message: l.devArchiveDeleteMessage(
        stats.cases,
        devArchiveSizeText(stats.bytes),
      ),
      yes: l.devArchiveDelete,
    );
    if (!yes) return;
    await clearDevArchive();
    ref.invalidate(devArchiveStatsProvider);
    if (context.mounted) showHint(context, l.devArchiveDeleted);
  }
}
