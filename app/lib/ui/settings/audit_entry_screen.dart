import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/attestation_log_view.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'attestation_log_detail.dart';
import 'attestation_log_screen.dart'
    show AttestationLogRow, recordStatus, recordSummary, recordTitle;
import 'privacy_screen.dart' show auditKindLabel;
import 'settings_page.dart';

/// One entry of the audit log with all its fields (on the device only; the
/// export leaves out contents).
class AuditEntryScreen extends ConsumerWidget {
  /// Creates the page for [entry].
  const AuditEntryScreen({super.key, required this.entry});

  /// The entry shown.
  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    final sessionId = entry.sessionId;
    final checks = sessionId == null
        ? const <AttestationRecord>[]
        : ref.watch(attestationSessionProvider(sessionId)).value ?? const [];
    final config = ref.watch(providerConfigProvider).value;
    return SettingsPage(
      title: auditKindLabel(context.l10n, entry.kind),
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: context.l10n.attLogTime,
              detail: sessionLabel(context.l10n, entry.at, now),
            ),
            if (entry.sessionId != null)
              SettingsRow(
                title: context.l10n.auditEntrySession,
                detail: entry.sessionId,
              ),
            for (final e in entry.payload.entries)
              SettingsRow(title: e.key, detail: '${e.value}'),
          ],
        ),
        if (checks.isNotEmpty)
          SettingsSection(
            title: context.l10n.auditEntryVerifications,
            children: [
              for (final r in checks)
                AttestationLogRow(
                  key: ValueKey('check-${r.logId}'),
                  title: recordTitle(
                    context.l10n,
                    r,
                    config?.nameOf(r.profileId) ?? r.profileId,
                  ),
                  detail: recordSummary(context.l10n, r, now),
                  status: recordStatus(r),
                  onTap: () => unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AttestationLogDetailScreen(logId: r.logId),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
