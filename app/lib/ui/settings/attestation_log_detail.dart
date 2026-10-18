import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../di/attestation_log_view.dart';
import '../../di/attestation_providers.dart';
import '../../di/providers.dart';
import '../../di/tee_restrictions.dart';
import '../../l10n/l10n.dart';
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
        title: context.l10n.attLogTitle,
        children: [
          Text(
            record.isLoading
                ? context.l10n.voiceDownloadLoading
                : context.l10n.attLogNoEntry,
            style: WText.caption,
          ),
        ],
      );
    }
    final config = ref.watch(providerConfigProvider).value;
    final now = ref.watch(clockProvider).now();
    final message = attestationMessage(
      context.l10n,
      r.status,
      reasonCode: r.reasonCode,
      detail: r.stages
          .where((s) => s.stage == 'gpu' && s.result == 'fail')
          .map((s) => s.detail)
          .firstOrNull,
    );
    final locked = ref.watch(attestationHubProvider).isLocked(r.profileId);
    return SettingsPage(
      title: context.l10n.attLogTitle2,
      children: [
        StatusCard(
          status: message.status,
          title:
              message.title ??
              recordTitle(
                context.l10n,
                r,
                config?.nameOf(r.profileId) ?? r.profileId,
              ),
          detail: message.text ?? recordSummary(context.l10n, r, now),
        ),
        if (ref.watch(openRestrictionsProvider(logId)).value case final open?
            when open.isNotEmpty)
          StatusCard(
            key: const ValueKey('openRestrictions'),
            status: CheckStatus.info,
            title: context.l10n.attLogNewRestriction,
            detail: context.l10n.attLogNewRestrictionDetail(
              open.map((st) => stageLabel(context.l10n, st)).join(', '),
            ),
          ),
        SettingsSection(
          title: context.l10n.attLogResultPerStep,
          children: stageRows(context.l10n, r),
        ),
        WideButton(
          context.l10n.details,
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AttestationExplainScreen(
                  profileId: r.profileId,
                  model: r.model,
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
          title: context.l10n.attLogParticulars,
          children: [
            for (final (k, v) in [
              (context.l10n.attLogTime, sessionLabel(context.l10n, r.at, now)),
              (
                context.l10n.attLogProvider,
                config?.nameOf(r.profileId) ?? r.profileId,
              ),
              (context.l10n.attLogModel, r.model),
              (context.l10n.attLogReceiptId, r.receiptId),
              (context.l10n.attLogKeysetDigest, r.workloadKeysetDigest),
              (context.l10n.attLogCommit, r.repoCommit),
              (context.l10n.attSCompose, r.composeHash),
              (context.l10n.attLogReasonCode, r.reasonCode),
            ])
              if (v != null) SettingsRow(title: k, detail: v, mono: false),
          ],
        ),
        if (locked)
          PrimaryButton(
            context.l10n.attLogRecheck,
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
          ? context.l10n.attLogRechecked
          : context.l10n.attLogRecheckFailed,
    );
  }
}
