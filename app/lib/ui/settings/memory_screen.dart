import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/providers.dart';
import '../design/design.dart';
import 'export.dart';
import 'settings_page.dart';

/// All memory entries, newest first (refresh with `ref.invalidate`).
final memoryEntriesProvider = FutureProvider.autoDispose<List<MemoryEntry>>(
  (ref) => ref.watch(storageProvider).memory.list(),
);

/// German name of a memory category.
String categoryLabel(MemoryCategory c) => switch (c) {
  MemoryCategory.person => 'Person',
  MemoryCategory.preference => 'Vorliebe',
  MemoryCategory.fact => 'Fakt',
  MemoryCategory.project => 'Projekt',
};

/// Second line of a memory entry: category and, for entries of private
/// runs, their privacy floor („Fakt · privat, nur ab TEE“).
String memoryDetail(MemoryEntry e) => switch (e.privacyFloor) {
  final floor? =>
    '${categoryLabel(e.category)} · privat, nur ab ${floor.label}',
  null => categoryLabel(e.category),
};

/// Settings → Gedächtnis: read, edit, delete entries; export as Markdown.
/// Entries saved by private runs show their privacy floor; the user can
/// lift it (with confirmation) in the edit dialog.
class MemoryScreen extends ConsumerWidget {
  /// Creates the screen.
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(memoryEntriesProvider);
    final list = entries.value ?? const <MemoryEntry>[];
    return SettingsPage(
      title: 'Gedächtnis',
      intro:
          'Wendelin merkt sich nur, worum du ausdrücklich bittest. Passwörter, '
          'PINs, Karten- und Kontonummern werden nie gespeichert.',
      children: [
        if (entries.isLoading && list.isEmpty)
          Text('…', style: WText.caption)
        else if (list.isEmpty)
          Text('Noch keine Einträge.', style: WText.intro)
        else
          SectionCard(
            children: [
              for (final e in list)
                SettingsRow(
                  title: e.text,
                  detail: memoryDetail(e),
                  onTap: () => unawaited(_edit(context, ref, e)),
                  trailing: WIconButton(
                    icon: WIcons.close,
                    tooltip: 'Löschen: ${e.text}',
                    shape: WIconButtonShape.round,
                    iconSize: WSize.iconSmall,
                    onPressed: () => unawaited(_delete(context, ref, e)),
                  ),
                ),
            ],
          ),
        WideButton(
          'Als Markdown exportieren',
          onPressed: list.isEmpty
              ? null
              : () async => ref.read(exporterProvider)(
                  'wendelin-gedaechtnis.md',
                  'text/markdown',
                  await ref.read(storageProvider).memory.exportMarkdown(),
                ),
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MemoryEntry e,
  ) async {
    final ok = await confirm(
      context,
      title: 'Eintrag vergessen?',
      message: '„${e.text}“',
      yes: 'Vergessen',
    );
    if (!ok) return;
    await ref.read(storageProvider).memory.forget(e.id);
    ref.invalidate(memoryEntriesProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, MemoryEntry e) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(e),
    );
    if (result == null || !context.mounted) return;
    if (result == _EditResult.liftFloor) {
      await _liftFloor(context, ref, e);
      return;
    }
    try {
      await ref
          .read(storageProvider)
          .memory
          .update(e.id, text: result.text, category: result.category);
    } on SensitiveContentException catch (error) {
      if (context.mounted) showHint(context, error.message);
    }
    ref.invalidate(memoryEntriesProvider);
  }

  Future<void> _liftFloor(
    BuildContext context,
    WidgetRef ref,
    MemoryEntry e,
  ) async {
    final level = e.privacyFloor?.label ?? '';
    final ok = await confirm(
      context,
      title: 'Untergrenze aufheben?',
      message:
          '„${e.text}“ stammt aus einer privaten Anfrage und geht bisher nur '
          'an Provider ab $level. Danach können ihn alle Provider sehen.',
      yes: 'Aufheben',
    );
    if (!ok) return;
    await ref.read(storageProvider).memory.clearPrivacyFloor(e.id);
    ref.invalidate(memoryEntriesProvider);
  }
}

/// Result of the edit dialog: new text and category, or [liftFloor].
final class _EditResult {
  const _EditResult(this.text, this.category);

  /// The user wants to lift the privacy floor.
  static const liftFloor = _EditResult('', MemoryCategory.fact);

  final String text;
  final MemoryCategory category;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog(this.entry);

  final MemoryEntry entry;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _text = TextEditingController(text: widget.entry.text)
    ..addListener(() => setState(() {}));
  late MemoryCategory _category = widget.entry.category;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: WColors.surface,
    title: Text('Eintrag ändern', style: WText.label),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: WSpace.m,
      children: [
        TextField(controller: _text, style: WText.body, maxLines: null),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final c in MemoryCategory.values)
              ChoiceChip(
                label: Text(categoryLabel(c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        if (widget.entry.privacyFloor case final floor?) ...[
          Text(
            'Aus einer privaten Anfrage: geht nur an Provider ab '
            '${floor.label}.',
            style: WText.detail,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_EditResult.liftFloor),
              child: const Text('Untergrenze aufheben'),
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty
            ? null
            : () =>
                  Navigator.of(context)
                      .pop(_EditResult(_text.text.trim(), _category)),
        child: const Text('Speichern'),
      ),
    ],
  );
}
