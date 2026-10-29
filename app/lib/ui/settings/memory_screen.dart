import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'export.dart';
import 'settings_page.dart';

/// The entries of one memory namespace (`''` = default memory), newest first
/// (refresh with `ref.invalidate`). Never mixes namespaces (WP92b).
final memoryEntriesProvider = FutureProvider.autoDispose
    .family<List<StoredMemory>, String>(
      (ref, owner) => ref.watch(storageProvider).memory.list(owner: owner),
    );

/// German name of a memory category.
String categoryLabel(AppLocalizations l, StoredMemoryCategory c) => switch (c) {
  StoredMemoryCategory.person => l.memoryCatPerson,
  StoredMemoryCategory.preference => l.memoryCatPreference,
  StoredMemoryCategory.fact => l.memoryCatFact,
  StoredMemoryCategory.project => l.memoryCatProject,
};

/// Second line of a memory entry: category and, for entries of private
/// runs, their privacy floor („Fakt · privat, nur ab TEE“).
String memoryDetail(AppLocalizations l, StoredMemory e) =>
    switch (e.privacyFloor) {
      final floor? => l.memoryPrivateFrom(
        categoryLabel(l, e.category),
        floor.labelOf(l),
      ),
      null => categoryLabel(l, e.category),
    };

/// Settings → Gedächtnis: read, edit, delete entries; export as Markdown.
/// Entries saved by private runs show their privacy floor; the user can
/// lift it (with confirmation) in the edit dialog.
class MemoryScreen extends ConsumerWidget {
  /// Creates the screen for the namespace [owner] (`''` = default memory,
  /// otherwise the memory of one person, opened from the person's page).
  const MemoryScreen({super.key, this.owner = ''});

  /// Shown memory namespace.
  final String owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(memoryEntriesProvider(owner));
    final list = entries.value ?? const <StoredMemory>[];
    return SettingsPage(
      title: context.l10n.memoryTitle,
      intro: context.l10n.memoryIntro,
      children: [
        if (entries.isLoading && list.isEmpty)
          Text('…', style: WText.caption)
        else if (list.isEmpty)
          InfoBox(context.l10n.memoryNone)
        else
          SectionCard(
            children: [
              for (final e in list)
                SettingsRow(
                  title: e.text,
                  detail: memoryDetail(context.l10n, e),
                  onTap: () => unawaited(_edit(context, ref, e)),
                  trailing: WIconButton(
                    icon: WIcons.close,
                    tooltip: context.l10n.memoryDeleteTooltip(e.text),
                    shape: WIconButtonShape.round,
                    iconSize: WSize.iconSmall,
                    onPressed: () => unawaited(_delete(context, ref, e)),
                  ),
                ),
            ],
          ),
        WideButton(
          context.l10n.memoryExportMd,
          onPressed: list.isEmpty
              ? null
              : () async => ref.read(exporterProvider)(
                  'wendelin-gedaechtnis.md',
                  'text/markdown',
                  await ref
                      .read(storageProvider)
                      .memory
                      .exportMarkdown(owner: owner),
                ),
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StoredMemory e,
  ) async {
    final ok = await confirm(
      context,
      title: context.l10n.memoryForgetTitle,
      message: context.l10n.quotedText(e.text),
      yes: context.l10n.memoryForget,
    );
    if (!ok) return;
    await ref.read(storageProvider).memory.forget(e.id, owner: owner);
    ref.invalidate(memoryEntriesProvider(owner));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    StoredMemory e,
  ) async {
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
          .update(
            e.id,
            text: result.text,
            category: result.category,
            owner: owner,
          );
    } on SensitiveContentException catch (error) {
      if (context.mounted) showHint(context, error.message);
    }
    ref.invalidate(memoryEntriesProvider(owner));
  }

  Future<void> _liftFloor(
    BuildContext context,
    WidgetRef ref,
    StoredMemory e,
  ) async {
    final level = e.privacyFloor?.labelOf(context.l10n) ?? '';
    final ok = await confirm(
      context,
      title: context.l10n.memoryLiftTitle,
      message: context.l10n.memoryLiftBody(e.text, level),
      yes: context.l10n.memoryLift,
    );
    if (!ok) return;
    await ref
        .read(storageProvider)
        .memory
        .clearPrivacyFloor(e.id, owner: owner);
    ref.invalidate(memoryEntriesProvider(owner));
  }
}

/// Result of the edit dialog: new text and category, or [liftFloor].
final class _EditResult {
  const _EditResult(this.text, this.category);

  /// The user wants to lift the privacy floor.
  static const liftFloor = _EditResult('', StoredMemoryCategory.fact);

  final String text;
  final StoredMemoryCategory category;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog(this.entry);

  final StoredMemory entry;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _text = TextEditingController(text: widget.entry.text)
    ..addListener(() => setState(() {}));
  late StoredMemoryCategory _category = widget.entry.category;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: WColors.surface,
    title: Text(context.l10n.memoryEditTitle, style: WText.label),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: WSpace.m,
      children: [
        TextField(controller: _text, style: WText.body, maxLines: null),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final c in StoredMemoryCategory.values)
              ChoiceChip(
                label: Text(categoryLabel(context.l10n, c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        if (widget.entry.privacyFloor case final floor?) ...[
          Text(
            context.l10n.memoryFromPrivate(floor.labelOf(context.l10n)),
            style: WText.detail,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_EditResult.liftFloor),
              child: Text(context.l10n.memoryLiftLimit),
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty
            ? null
            : () =>
                  Navigator.of(context)
                      .pop(_EditResult(_text.text.trim(), _category)),
        child: Text(context.l10n.save),
      ),
    ],
  );
}
