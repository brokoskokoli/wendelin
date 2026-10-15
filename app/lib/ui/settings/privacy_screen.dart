import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/wake_providers.dart';
import '../design/design.dart';
import '../routes.dart';
import 'settings_page.dart';

/// Audit entries shown (newest first), filtered by kind.
final auditViewProvider = FutureProvider.autoDispose
    .family<List<AuditEntry>, AuditKind?>(
      (ref, kind) => ref
          .watch(storageProvider)
          .audit
          .query(AuditFilter(kinds: kind == null ? null : {kind}, limit: 200)),
    );

/// German name of an audit kind.
String auditKindLabel(AuditKind k) => switch (k) {
  AuditKind.request => 'Anfrage',
  AuditKind.routing => 'Routing',
  AuditKind.toolCall => 'Tool',
  AuditKind.confirmation => 'Bestätigung',
  AuditKind.escalation => 'Eskalation',
  AuditKind.usage => 'Kosten',
  AuditKind.verification => 'Prüfung',
  AuditKind.error => 'Fehler',
};

/// Settings → Datenschutz und Logs: retention, audit log with filter,
/// export as JSON, delete everything.
class PrivacyScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacyScreen> {
  Widget _retention(int days) => SettingsSection(
    title: 'Aufbewahrung',
    children: [
      for (final d in RetentionDays.choices)
        SettingsRow(
          title: d == 365 ? '1 Jahr' : '$d Tage',
          onTap: () => unawaited(
            ref
                .read(retentionDaysProvider.notifier)
                .set(d)
                .then((_) => ref.invalidate(auditViewProvider)),
          ),
          trailing: d == days
              ? const CheckStatusIcon(CheckStatus.ok, semanticLabel: 'gewählt')
              : null,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(retentionDaysProvider);
    final entries = ref.watch(auditViewProvider(null)).value ?? const [];
    return SettingsPage(
      title: 'Datenschutz und Logs',
      intro:
          'Verläufe und Prüfprotokoll bleiben auf dem Gerät. Ältere Einträge '
          'löscht Wendelin automatisch.',
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: 'Bildschirminhalt schützen',
              detail:
                  'Keine Screenshots, im App-Wechsler verdeckt. Das '
                  'Assistenten-Overlay ist immer geschützt.',
              trailing: WSwitch(
                value: ref.watch(secureScreenProvider),
                semanticLabel: 'Bildschirminhalt schützen',
                onChanged: (on) => unawaited(
                  ref.read(secureScreenProvider.notifier).set(secure: on),
                ),
              ),
            ),
          ],
        ),
        SectionCard(
          children: [
            SettingsRow(
              title: 'TEE-Prüfprotokoll',
              detail:
                  'Prüfung der Anbieter mit geschützter Umgebung, GPU-Prüfung '
                  'über NVIDIA',
              onTap: () => unawaited(
                Navigator.of(context).pushNamed(AppRoutes.attestationLog),
              ),
            ),
          ],
        ),
        _retention(days),
        SectionCard(
          children: [
            SettingsRow(
              key: const ValueKey('auditLogRow'),
              title: 'Prüfprotokoll',
              detail: entries.isEmpty
                  ? 'Keine Einträge.'
                  : switch (entries.length) {
                      1 => '1 Eintrag',
                      >= 200 => '200+ Einträge',
                      final n => '$n Einträge',
                    },
              onTap: () => unawaited(
                Navigator.of(context).pushNamed(AppRoutes.auditLog),
              ),
            ),
          ],
        ),
        WideButton(
          'Verläufe und Protokoll löschen',
          onPressed: () => unawaited(_deleteAll()),
        ),
      ],
    );
  }

  Future<void> _deleteAll() async {
    final ok = await confirm(
      context,
      title: 'Alles löschen?',
      message:
          'Alle Gesprächsverläufe, das Prüfprotokoll und die eingelernten '
          'Stimmen (Aktivierungswort) werden gelöscht. Das lässt sich nicht '
          'rückgängig machen. Gedächtnis und Einstellungen bleiben.',
      yes: 'Alles löschen',
    );
    if (!ok) return;
    final storage = ref.read(storageProvider);
    await storage.audit.clear();
    await storage.attestations.deleteAll();
    await ref.read(wakeSpeakersProvider.notifier).removeAll();
    for (final s in await storage.conversations.sessions()) {
      await storage.conversations.deleteSession(s.id);
    }
    ref.read(sessionManagerProvider).end();
    ref.invalidate(auditViewProvider);
    if (mounted) showHint(context, 'Gelöscht.');
  }
}

/// One line about an audit entry (no secrets: the repository redacts).
String auditSummary(AuditEntry e) {
  final p = e.payload;
  return switch (e.kind) {
    AuditKind.request => '${p['text'] ?? ''}',
    AuditKind.routing => '${p['profileId']} · ${p['modelId']}',
    // Undo is logged as its own tool entry; without the marker it would
    // read like a second call.
    AuditKind.toolCall when p['undo'] == true =>
      '${p['tool']} · rückgängig · ${p['status']}',
    AuditKind.toolCall => '${p['tool']} · ${p['status']}',
    AuditKind.confirmation =>
      '${p['tool'] ?? p['toProfile']} · '
          '${p['approved'] == true ? 'ja' : 'nein'}',
    AuditKind.escalation => '${p['fromProfile']} → ${p['toProfile']}',
    AuditKind.usage =>
      '${p['modelId'] ?? p['profileId']} · '
          '${p['inputTokens'] ?? '-'}/${p['outputTokens'] ?? '-'} Tokens',
    AuditKind.verification => '${p['profileId']} · ${p['status']}',
    AuditKind.error => '${p['message'] ?? p['error']}',
  };
}
