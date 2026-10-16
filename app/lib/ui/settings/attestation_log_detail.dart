import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../di/attestation_log_view.dart';
import '../../di/attestation_providers.dart';
import '../../di/providers.dart';
import '../../di/tee_restrictions.dart';
import '../attestation/attestation_texts.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'attestation_explain_screen.dart';
import 'attestation_log_screen.dart';
import 'settings_page.dart';

/// One entry of the TEE verification log: result per stage, ids and hashes,
/// and the reason in words. „Neu prüfen“ while the provider is locked.
class AttestationLogDetailScreen extends ConsumerWidget {
  /// Creates the page for the entry [logId].
  const AttestationLogDetailScreen({super.key, required this.logId});

  /// Id of the entry (`AttestationStatusChanged.logId`).
  final String logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(attestationRecordProvider(logId));
    final r = record.value;
    if (r == null) {
      return SettingsPage(
        title: 'Prüfprotokoll',
        children: [
          Text(
            record.isLoading
                ? 'Lädt …'
                : 'Zu dieser Antwort gibt es noch keinen Eintrag.',
            style: WText.caption,
          ),
        ],
      );
    }
    final config = ref.watch(providerConfigProvider).value;
    final now = ref.watch(clockProvider).now();
    final message = attestationMessage(r.status, reasonCode: r.reasonCode);
    final locked = ref.watch(attestationHubProvider).isLocked(r.profileId);
    return SettingsPage(
      title: 'Prüfprotokoll',
      children: [
        StatusCard(
          status: message.status,
          title:
              message.title ??
              recordTitle(r, config?.nameOf(r.profileId) ?? r.profileId),
          detail: message.text ?? recordSummary(r, now),
        ),
        if (ref.watch(openRestrictionsProvider(logId)).value case final open?
            when open.isNotEmpty)
          StatusCard(
            key: const ValueKey('openRestrictions'),
            status: CheckStatus.info,
            title: 'Neue Einschränkung',
            detail:
                '${open.map(stageLabel).join(', ')}: nur protokolliert und '
                'noch nicht von dir akzeptiert. Unter „Details“ kannst du das '
                'ansehen und akzeptieren.',
          ),
        SettingsSection(title: 'Ergebnis je Stufe', children: stageRows(r)),
        WideButton(
          'Details',
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AttestationExplainScreen(
                  profileId: r.profileId,
                  stages: [
                    for (final s in r.stages)
                      (stage: s.stage, result: s.result, detail: s.detail),
                  ],
                ),
              ),
            ),
          ),
        ),
        ToolTlsHint(encrypted: config?.toolsEncryptedFor(r.profileId) ?? false),
        SettingsSection(
          title: 'Angaben',
          children: [
            for (final (k, v) in [
              ('Zeit', sessionLabel(r.at, now)),
              ('Anbieter', config?.nameOf(r.profileId) ?? r.profileId),
              ('Modell', r.model),
              ('Quittungs-ID', r.receiptId),
              ('Keyset-Digest', r.workloadKeysetDigest),
              ('Commit', r.repoCommit),
              ('Compose-Hash', r.composeHash),
              ('Grundcode', r.reasonCode),
            ])
              if (v != null) SettingsRow(title: k, detail: v, mono: false),
          ],
        ),
        if (locked)
          PrimaryButton(
            'Neu prüfen',
            onPressed: () => unawaited(_recheck(context, ref, r.profileId)),
          ),
      ],
    );
  }

  Future<void> _recheck(
    BuildContext context,
    WidgetRef ref,
    String profileId,
  ) async {
    final report = await ref.read(attestationHubProvider).reattest(profileId);
    ref
      ..invalidate(attestationRecordsProvider)
      ..invalidate(attestationRecordProvider(logId));
    if (!context.mounted) return;
    showHint(
      context,
      report?.status == AttestationStatus.green
          ? 'Anbieter neu geprüft, die Sperre ist aufgehoben.'
          : 'Die neue Prüfung ist nicht bestanden.',
    );
  }
}
