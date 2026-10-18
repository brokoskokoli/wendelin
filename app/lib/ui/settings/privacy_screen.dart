import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/wake_providers.dart';
import '../../l10n/l10n.dart';
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
String auditKindLabel(AppLocalizations l, AuditKind k) => switch (k) {
  AuditKind.request => l.privacyScreenKindRequest,
  AuditKind.routing => l.areaRouting,
  AuditKind.toolCall => l.privacyScreenKindTool,
  AuditKind.confirmation => l.privacyScreenKindConfirmation,
  AuditKind.escalation => l.privacyScreenKindEscalation,
  AuditKind.usage => l.areaCosts,
  AuditKind.verification => l.privacyScreenKindVerification,
  AuditKind.error => l.error,
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
    title: context.l10n.privacyScreenRetention,
    children: [
      for (final d in RetentionDays.choices)
        SettingsRow(
          title: d == 365
              ? context.l10n.privacyScreenOneYear
              : context.l10n.privacyScreenDays(d),
          onTap: () => unawaited(
            ref
                .read(retentionDaysProvider.notifier)
                .set(d)
                .then((_) => ref.invalidate(auditViewProvider)),
          ),
          trailing: d == days
              ? CheckStatusIcon(
                  CheckStatus.ok,
                  semanticLabel: context.l10n.selected,
                )
              : null,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(retentionDaysProvider);
    final entries = ref.watch(auditViewProvider(null)).value ?? const [];
    return SettingsPage(
      title: context.l10n.areaPrivacy,
      intro: context.l10n.privacyScreenIntro,
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: context.l10n.privacyScreenProtectScreen,
              detail: context.l10n.privacyScreenProtectScreenHint,
              trailing: WSwitch(
                value: ref.watch(secureScreenProvider),
                semanticLabel: context.l10n.privacyScreenProtectScreen,
                onChanged: (on) => unawaited(
                  ref.read(secureScreenProvider.notifier).set(secure: on),
                ),
              ),
            ),
          ],
        ),
        _retention(days),
        SettingsSection(
          title: context.l10n.attLogTitle,
          children: [
            SettingsRow(
              key: const ValueKey('auditLogRow'),
              title: context.l10n.privacyScreenGeneralLog,
              detail: entries.isEmpty
                  ? context.l10n.attLogScreenNoEntries
                  : switch (entries.length) {
                      1 => context.l10n.privacyScreenOneEntry,
                      >= 200 => context.l10n.privacyScreenManyEntries,
                      final n => context.l10n.privacyScreenEntries(n),
                    },
              onTap: () => unawaited(
                Navigator.of(context).pushNamed(AppRoutes.auditLog),
              ),
            ),
            SettingsRow(
              title: context.l10n.privacyScreenTeeLog,
              detail: context.l10n.privacyScreenTeeLogHint,
              onTap: () => unawaited(
                Navigator.of(context).pushNamed(AppRoutes.attestationLog),
              ),
            ),
          ],
        ),
        WideButton(
          context.l10n.privacyScreenDeleteHistory,
          onPressed: () => unawaited(_deleteAll()),
        ),
      ],
    );
  }

  Future<void> _deleteAll() async {
    final ok = await confirm(
      context,
      title: context.l10n.privacyScreenDeleteAllTitle,
      message: context.l10n.privacyScreenDeleteAllBody,
      yes: context.l10n.privacyScreenDeleteAll,
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
    if (mounted) showHint(context, context.l10n.attLogScreenDeleted);
  }
}

/// One line about an audit entry (no secrets: the repository redacts).
String auditSummary(AppLocalizations l, AuditEntry e) {
  final p = e.payload;
  return switch (e.kind) {
    AuditKind.request => '${p['text'] ?? ''}',
    AuditKind.routing => '${p['profileId']} · ${p['modelId']}',
    // Undo is logged as its own tool entry; without the marker it would
    // read like a second call.
    AuditKind.toolCall when p['undo'] == true => l.privacyScreenUndone(
      '${p['tool']}',
      '${p['status']}',
    ),
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
