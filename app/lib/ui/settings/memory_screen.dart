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

/// Settings → Gedächtnis: read, edit, delete entries; export as Markdown.
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
                  detail: categoryLabel(e.category),
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
    final result = await showDialog<(String, MemoryCategory)>(
      context: context,
      builder: (_) => _EditDialog(e),
    );
    if (result == null) return;
    try {
      await ref
          .read(storageProvider)
          .memory
          .update(e.id, text: result.$1, category: result.$2);
    } on SensitiveContentException catch (error) {
      if (context.mounted) showHint(context, error.message);
    }
    ref.invalidate(memoryEntriesProvider);
  }
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
            : () => Navigator.of(context).pop((_text.text.trim(), _category)),
        child: const Text('Speichern'),
      ),
    ],
  );
}
