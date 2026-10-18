import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/obsidian_index.dart';
import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/saf_vault_port.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Choosing the vault folder (overridden in tests).
final vaultAccessProvider = Provider<VaultAccess>((ref) => const VaultAccess());

/// Whether the persisted grant of the chosen vault is still held (`true`
/// without a vault or on platforms without SAF).
final vaultAccessOkProvider = FutureProvider<bool>((ref) async {
  final uri = ref.watch(obsidianPrefsProvider.select((p) => p.vaultUri));
  if (uri == null) return true;
  try {
    return await ref.watch(vaultAccessProvider).hasAccess(uri);
  } on PortException catch (e) {
    return e.kind == PortErrorKind.unsupported;
  }
});

/// Settings → Obsidian: vault folder (SAF), daily notes (folder, date
/// format, template) and the search index (build with progress).
class ObsidianScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ObsidianScreen({super.key});

  @override
  ConsumerState<ObsidianScreen> createState() => _ObsidianState();
}

class _ObsidianState extends ConsumerState<ObsidianScreen> {
  final _folder = TextEditingController();
  final _format = TextEditingController();
  final _template = TextEditingController();

  @override
  void initState() {
    super.initState();
    final daily = ref.read(obsidianPrefsProvider).dailyNotes;
    _folder.text = daily.folder;
    _format.text = daily.format;
    _template.text = daily.template ?? '';
    for (final c in [_folder, _format, _template]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _folder.dispose();
    _format.dispose();
    _template.dispose();
    super.dispose();
  }

  DailyNoteSettings get _daily => DailyNoteSettings(
    folder: _folder.text.trim(),
    format: _format.text.trim().isEmpty
        ? const DailyNoteSettings().format
        : _format.text.trim(),
    template: _template.text.trim().isEmpty ? null : _template.text.trim(),
  );

  /// Path of today's daily note with the entered settings, or the reason
  /// why the settings are not usable.
  String _preview() {
    final now = ref.read(clockProvider).now();
    try {
      final path = _daily.pathFor(
        LocalDate(now.year, now.month, now.day),
        locale: ref.read(languageProvider),
      );
      final template = _daily.template;
      if (template != null) VaultPath.note(template);
      return context.l10n.obsidianToday(path);
    } on PortException catch (e) {
      return context.l10n.obsidianUnusable(e.message);
    } on FormatException catch (e) {
      return context.l10n.obsidianUnusable2(e.message);
    }
  }

  Future<void> _pick() async {
    final access = ref.read(vaultAccessProvider);
    final prefs = ref.read(obsidianPrefsProvider.notifier);
    final old = ref.read(obsidianPrefsProvider);
    final PickedVault? picked;
    try {
      picked = await access.pick();
    } on PortException catch (e) {
      if (mounted) showHint(context, e.message);
      return;
    }
    if (picked == null) return;
    await prefs.set(old.withVault(picked.uri, picked.name));
    final previous = old.vaultUri;
    if (previous != null && previous != picked.uri) {
      await access.release(previous);
    }
    // Der Einrichtungsschritt „Vault wählen“ ist erledigt; wer den ersten
    // Vault wählt, schaltet die Integration damit ein.
    await _refreshIntegration();
    if (!old.hasVault) {
      await ref
          .read(integrationActivatorProvider)
          .setEnabled('obsidian', enabled: true);
    }
    ref.invalidate(vaultAccessOkProvider);
    unawaited(ref.read(obsidianIndexProvider.notifier).sync());
  }

  Future<void> _remove() async {
    final ok = await confirm(
      context,
      title: context.l10n.obsidianRemoveTitle,
      message: context.l10n.obsidianRemoveBody,
      yes: context.l10n.remove,
    );
    if (!ok) return;
    final prefs = ref.read(obsidianPrefsProvider);
    final uri = prefs.vaultUri;
    await ref
        .read(integrationActivatorProvider)
        .setEnabled('obsidian', enabled: false);
    await ref
        .read(obsidianPrefsProvider.notifier)
        .set(prefs.withVault(null, null));
    await _refreshIntegration();
    if (uri != null) await ref.read(vaultAccessProvider).release(uri);
  }

  Future<void> _refreshIntegration() async {
    final registry = ref.read(toolRegistryProvider);
    if (registry.integrations.any((i) => i.id == 'obsidian')) {
      await registry.refresh('obsidian');
    }
  }

  Future<void> _saveDaily() async {
    final prefs = ref.read(obsidianPrefsProvider);
    await ref
        .read(obsidianPrefsProvider.notifier)
        .set(prefs.withDailyNotes(_daily));
    if (mounted) showHint(context, context.l10n.obsidianDailySaved);
  }

  Widget _vaultSection(ObsidianPrefs prefs, bool accessOk) => SettingsSection(
    title: context.l10n.obsidianVault,
    children: [
      SectionCard(
        children: [
          SettingsRow(
            title: prefs.vaultName ?? context.l10n.obsidianNoVault,
            detail: !prefs.hasVault
                ? context.l10n.obsidianChooseFolder
                : accessOk
                ? context.l10n.obsidianAccessGranted
                : context.l10n.obsidianAccessLost,
            trailing: prefs.hasVault
                ? CheckStatusIcon(
                    accessOk ? CheckStatus.ok : CheckStatus.failed,
                    semanticLabel: accessOk
                        ? context.l10n.obsidianAccessGranted2
                        : context.l10n.obsidianNoAccess,
                  )
                : null,
          ),
        ],
      ),
      PrimaryButton(
        prefs.hasVault
            ? context.l10n.obsidianChooseOther
            : context.l10n.obsidianChooseVaultFolder,
        onPressed: () => unawaited(_pick()),
      ),
      if (prefs.hasVault)
        WideButton(
          context.l10n.obsidianRemoveVault,
          onPressed: () => unawaited(_remove()),
        ),
    ],
  );

  Widget _dailySection() => SettingsSection(
    title: context.l10n.obsidianDailyNotes,
    children: [
      TextField(
        controller: _folder,
        style: WText.body,
        decoration: InputDecoration(
          labelText: context.l10n.obsidianFolder,
          hintText: ObsidianPrefs.defaultDailyFolder,
          helperText: context.l10n.obsidianFolderHint,
          helperMaxLines: 2,
        ),
      ),
      TextField(
        controller: _format,
        style: WText.body,
        decoration: InputDecoration(
          labelText: context.l10n.obsidianDateFormat,
          hintText: 'YYYY-MM-DD',
        ),
      ),
      TextField(
        controller: _template,
        style: WText.body,
        decoration: InputDecoration(
          labelText: context.l10n.obsidianTemplate,
          hintText: context.l10n.obsidianTemplateHint,
        ),
      ),
      Text(_preview(), style: WText.mono),
      WideButton(
        context.l10n.obsidianSaveDaily,
        onPressed: () => unawaited(_saveDaily()),
      ),
    ],
  );

  Widget _indexSection(ObsidianPrefs prefs, IndexProgress index) =>
      SettingsSection(
        title: context.l10n.obsidianSearchIndex,
        children: [
          Text(index.labelOf(context.l10n), style: WText.detail),
          if (index.running)
            LinearProgressIndicator(
              value: index.fraction,
              semanticsLabel: context.l10n.obsidianIndexBuilding,
            ),
          Text(context.l10n.obsidianIndexHint, style: WText.caption),
          WideButton(
            context.l10n.obsidianBuildIndex,
            onPressed: !prefs.hasVault || index.running
                ? null
                : () => unawaited(
                    ref.read(obsidianIndexProvider.notifier).sync(),
                  ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(obsidianPrefsProvider);
    final accessOk = ref.watch(vaultAccessOkProvider).value ?? true;
    final index = ref.watch(obsidianIndexProvider);
    return SettingsPage(
      title: 'Obsidian',
      intro: context.l10n.obsidianIntro,
      children: [
        _vaultSection(prefs, accessOk),
        _dailySection(),
        _indexSection(prefs, index),
      ],
    );
  }
}
