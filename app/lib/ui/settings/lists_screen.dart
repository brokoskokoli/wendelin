import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/list_access.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/saf_list_file_port.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Settings → Listen (K6): lists with their Markdown file.
class ListsScreen extends ConsumerWidget {
  /// Creates the screen.
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listDefinitionsProvider);
    final noAccess = ref.watch(listsWithoutAccessProvider).value ?? const {};
    return SettingsPage(
      title: 'Listen',
      intro: context.l10n.listsIntro,
      children: [
        if (lists.isNotEmpty)
          SectionCard(
            children: [
              for (final l in lists)
                SettingsRow(
                  title: l.name,
                  detail: noAccess.contains(l.id)
                      ? context.l10n.listsAccessLost
                      : [
                          if (l.aliases.isNotEmpty)
                            context.l10n.listsAlso(l.aliases.join(', ')),
                          if (l.section != null)
                            context.l10n.listsSection(l.section!),
                        ].join(' · ').ifEmpty(context.l10n.listsNoAliases),
                  trailing: noAccess.contains(l.id)
                      ? CheckStatusIcon(
                          CheckStatus.failed,
                          semanticLabel: context.l10n.obsidianNoAccess,
                        )
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ListEditScreen(existing: l),
                    ),
                  ),
                ),
            ],
          ),
        WideButton(
          context.l10n.listsAdd,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ListEditScreen()),
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Creates or edits one list: name, aliases, optional section and the
/// target file (picked or newly created with the Android file picker).
class ListEditScreen extends ConsumerStatefulWidget {
  /// Creates the page; without [existing] a new list is created.
  const ListEditScreen({super.key, this.existing});

  /// The list being edited.
  final ListDefinition? existing;

  @override
  ConsumerState<ListEditScreen> createState() => _ListEditState();
}

class _ListEditState extends ConsumerState<ListEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _aliases = TextEditingController(
    text: widget.existing?.aliases.join(', '),
  );
  late final _section = TextEditingController(text: widget.existing?.section);
  late String? _target = widget.existing?.target;
  String? _fileName;
  String? _error;
  bool _saved = false;

  /// Files picked in this dialog (their grants are released again unless
  /// a saved list uses them).
  final _picked = <String>{};

  /// Targets of the saved lists (kept current in [build]).
  Set<String> _usedTargets = const {};

  late final DocumentPicker _picker;

  @override
  void initState() {
    super.initState();
    _picker = ref.read(documentPickerProvider);
    final target = _target;
    if (target != null) unawaited(_loadName(target));
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final uri in _picked) {
        unawaited(_release(uri));
      }
    }
    _name.dispose();
    _aliases.dispose();
    _section.dispose();
    super.dispose();
  }

  /// Gives up the grant of [uri] unless a saved list still uses it.
  Future<void> _release(String uri) async {
    if (_usedTargets.contains(uri)) return;
    try {
      await _picker.release(uri);
    } on PortException {
      // The grant is gone already; nothing left to release.
    }
  }

  Future<void> _loadName(String uri) async {
    try {
      final name = await ref.read(documentPickerProvider).displayName(uri);
      if (mounted) setState(() => _fileName = name);
    } on PortException catch (e) {
      if (mounted) setState(() => _fileName = e.message);
    }
  }

  Future<void> _pick({required bool create}) async {
    final picker = ref.read(documentPickerProvider);
    try {
      final name = _name.text.trim().isEmpty
          ? context.l10n.listsListFallback
          : _name.text.trim();
      final uri = create
          ? await picker.create('$name.md')
          : await picker.open();
      if (uri == null) return;
      final previous = _target;
      if (previous != null && _picked.remove(previous) && previous != uri) {
        await _release(previous);
      }
      _picked.add(uri);
      setState(() {
        _target = uri;
        _error = null;
      });
      await _loadName(uri);
    } on PortException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final target = _target;
    if (name.isEmpty || target == null) {
      setState(() => _error = context.l10n.listsNeedNameFile);
      return;
    }
    final section = _section.text.trim();
    final list = ListDefinition(
      id: widget.existing?.id ?? ref.read(idGeneratorProvider).next(),
      name: name,
      target: target,
      aliases: [
        for (final a in _aliases.text.split(','))
          if (a.trim().isNotEmpty) a.trim(),
      ],
      section: section.isEmpty ? null : section,
    );
    await ref.read(listDefinitionsProvider.notifier).save(list);
    _saved = true;
    _usedTargets = {
      for (final l in ref.read(listDefinitionsProvider)) l.target,
    };
    final old = widget.existing?.target;
    if (old != null && old != target) await _release(old);
    await checkListAccess(ref);
    // Creating a list is a clear wish to use lists: switch them on.
    if (!ref.read(enabledIntegrationsProvider).contains('lists')) {
      await ref
          .read(integrationActivatorProvider)
          .setEnabled('lists', enabled: true);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final ok = await confirm(
      context,
      title: context.l10n.listsDeleteTitle(existing.name),
      message: context.l10n.listsDeleteBody,
      yes: context.l10n.delete,
    );
    if (!ok) return;
    await ref.read(listDefinitionsProvider.notifier).remove(existing.id);
    _usedTargets = {
      for (final l in ref.read(listDefinitionsProvider)) l.target,
    };
    await _release(existing.target);
    await checkListAccess(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    _usedTargets = {
      for (final l in ref.watch(listDefinitionsProvider)) l.target,
    };
    return _page();
  }

  Widget _page() => SettingsPage(
    title: widget.existing == null
        ? context.l10n.listsNewList
        : context.l10n.listsEditList,
    children: [
      TextField(
        controller: _name,
        style: WText.body,
        decoration: InputDecoration(labelText: context.l10n.listsNameHint),
      ),
      TextField(
        controller: _aliases,
        style: WText.body,
        decoration: InputDecoration(labelText: context.l10n.listsAliases),
      ),
      TextField(
        controller: _section,
        style: WText.body,
        decoration: InputDecoration(labelText: context.l10n.listsSectionLabel),
      ),
      SettingsSection(
        title: context.l10n.listsFile,
        children: [
          SettingsRow(
            title: _target == null
                ? context.l10n.listsNoFile
                : (_fileName ?? '…'),
            detail: _target,
          ),
        ],
      ),
      Row(
        spacing: WSpace.m,
        children: [
          Expanded(
            child: WideButton(
              context.l10n.listsChooseFile,
              onPressed: () => unawaited(_pick(create: false)),
            ),
          ),
          Expanded(
            child: WideButton(
              context.l10n.listsNewFile,
              onPressed: () => unawaited(_pick(create: true)),
            ),
          ),
        ],
      ),
      if (_error != null) Text(_error!, style: WText.caption),
      PrimaryButton(context.l10n.save, onPressed: () => unawaited(_save())),
      if (widget.existing != null)
        WideButton(
          context.l10n.listsDeleteList,
          onPressed: () => unawaited(_delete()),
        ),
    ],
  );
}
