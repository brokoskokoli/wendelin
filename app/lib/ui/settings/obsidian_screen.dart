import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/obsidian_index.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
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
      return 'Heute: $path';
    } on PortException catch (e) {
      return 'Nicht verwendbar: ${e.message}';
    } on FormatException catch (e) {
      return 'Nicht verwendbar: ${e.message}';
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
      title: 'Vault entfernen?',
      message:
          'Wendelin verliert den Zugriff auf den Ordner. Die Notizen selbst '
          'bleiben unverändert.',
      yes: 'Entfernen',
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
    if (mounted) showHint(context, 'Tagesnotizen gespeichert.');
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(obsidianPrefsProvider);
    final accessOk = ref.watch(vaultAccessOkProvider).value ?? true;
    final index = ref.watch(obsidianIndexProvider);
    return SettingsPage(
      title: 'Obsidian',
      intro:
          'Wendelin liest und ergänzt Notizen direkt im Vault-Ordner. Sync '
          'bleibt bei Obsidian Sync, Syncthing oder Git.',
      children: [
        SettingsSection(
          title: 'Vault',
          children: [
            SectionCard(
              children: [
                SettingsRow(
                  title: prefs.vaultName ?? 'Kein Vault gewählt',
                  detail: !prefs.hasVault
                      ? 'Wähle den Ordner deines Obsidian-Vaults'
                      : accessOk
                      ? 'Zugriff erteilt'
                      : 'Kein Zugriff mehr – Ordner neu wählen',
                  trailing: prefs.hasVault
                      ? CheckStatusIcon(
                          accessOk ? CheckStatus.ok : CheckStatus.failed,
                          semanticLabel: accessOk
                              ? 'Zugriff erteilt'
                              : 'kein Zugriff',
                        )
                      : null,
                ),
              ],
            ),
            PrimaryButton(
              prefs.hasVault ? 'Anderen Ordner wählen' : 'Vault-Ordner wählen',
              onPressed: () => unawaited(_pick()),
            ),
            if (prefs.hasVault)
              WideButton(
                'Vault entfernen',
                onPressed: () => unawaited(_remove()),
              ),
          ],
        ),
        SettingsSection(
          title: 'Tagesnotizen',
          children: [
            TextField(
              controller: _folder,
              style: WText.body,
              decoration: const InputDecoration(
                labelText: 'Ordner (leer = Vault-Wurzel)',
                hintText: 'Journal',
              ),
            ),
            TextField(
              controller: _format,
              style: WText.body,
              decoration: const InputDecoration(
                labelText: 'Datumsformat wie in Obsidian',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextField(
              controller: _template,
              style: WText.body,
              decoration: const InputDecoration(
                labelText: 'Vorlage (optional)',
                hintText: 'Vorlagen/Tagesnotiz',
              ),
            ),
            Text(_preview(), style: WText.mono),
            WideButton(
              'Tagesnotizen speichern',
              onPressed: () => unawaited(_saveDaily()),
            ),
          ],
        ),
        SettingsSection(
          title: 'Suchindex',
          children: [
            Text(index.label, style: WText.detail),
            if (index.running)
              LinearProgressIndicator(
                value: index.fraction,
                semanticsLabel: 'Index wird aufgebaut',
              ),
            WideButton(
              'Index aufbauen',
              onPressed: !prefs.hasVault || index.running
                  ? null
                  : () => unawaited(
                      ref.read(obsidianIndexProvider.notifier).sync(),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
