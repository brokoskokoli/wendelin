import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/attestation_log_view.dart';
import '../../di/attestation_providers.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../attestation/attestation_texts.dart';
import '../attestation/stage_line.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'attestation_log_detail.dart';
import 'export.dart';
import 'settings_page.dart';

/// Short line of a log entry: time, result and receipt id.
String recordSummary(AppLocalizations l, AttestationRecord r, DateTime now) {
  final parts = [
    sessionLabel(l, r.at, now),
    switch (r.status) {
      AttestationStatus.green => l.attSummaryGreen,
      AttestationStatus.yellow => l.attSummaryYellow,
      AttestationStatus.red => 'fehlgeschlagen',
      AttestationStatus.unconfirmed => l.attUnconfirmed,
    },
    ?r.receiptId,
  ];
  return parts.join(' · ');
}

/// Title of a log entry: what was checked.
String recordTitle(
  AppLocalizations l,
  AttestationRecord r,
  String providerName,
) => switch (r.kind) {
  AttestationRecordKind.session => l.attLogScreenSessionTitle(providerName),
  AttestationRecordKind.receipt => l.attLogScreenReceiptTitle(
    r.model ?? l.attResponseWord,
    providerName,
  ),
  AttestationRecordKind.gpu => l.attLogScreenGpuTitle(r.model ?? providerName),
};

/// Symbol of an entry's overall result.
CheckStatus recordStatus(AttestationRecord r) => switch (r.status) {
  AttestationStatus.green => CheckStatus.ok,
  AttestationStatus.yellow => CheckStatus.pending,
  AttestationStatus.red => CheckStatus.failed,
  AttestationStatus.unconfirmed => CheckStatus.neutral,
};

/// Settings → Datenschutz → Prüfprotokoll (TEE): GPU check setting, the list
/// of checks per request with filter by status, export as JSON (ids, hashes
/// and stage results only, no content) and delete.
class AttestationLogScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AttestationLogScreen({super.key});

  @override
  ConsumerState<AttestationLogScreen> createState() => _LogState();
}

class _LogState extends ConsumerState<AttestationLogScreen> {
  AttestationStatus? _filter;

  static String _filterLabel(AppLocalizations l, AttestationStatus? s) =>
      switch (s) {
        null => l.attLogScreenFilterAll,
        AttestationStatus.green => l.attLogScreenFilterGreen,
        AttestationStatus.yellow => l.attLogScreenFilterYellow,
        AttestationStatus.red => l.attLogScreenFilterRed,
        AttestationStatus.unconfirmed => l.attLogScreenFilterUnconfirmed,
      };

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(attestationRecordsProvider).value ?? const [];
    final shown = [
      for (final r in records)
        if (_filter == null || r.status == _filter) r,
    ];
    final now = ref.watch(clockProvider).now();
    // Newest session entry per provider (the list is newest first).
    final latest = <String, AttestationRecord>{};
    for (final r in records) {
      if (r.kind == AttestationRecordKind.session) {
        latest.putIfAbsent(r.profileId, () => r);
      }
    }
    final sessions = latest.values.toList();
    final config = ref.watch(providerConfigProvider).value;
    return SettingsPage(
      title: context.l10n.attLogTitle,
      intro: context.l10n.attLogScreenIntro,
      children: [
        for (final r in sessions)
          _SessionCard(
            record: r,
            name: config?.nameOf(r.profileId) ?? r.profileId,
            locked: ref.watch(attestationHubProvider).isLocked(r.profileId),
            toolsEncrypted: config?.toolsEncryptedFor(r.profileId) ?? false,
            now: now,
            onReattest: () => unawaited(_reattest(r.profileId)),
          ),
        WideButton(
          context.l10n.attLogScreenExportJson,
          onPressed: () async => ref.read(exporterProvider)(
            'wendelin-tee-pruefprotokoll.json',
            'application/json',
            await ref.read(storageProvider).attestations.exportJson(),
          ),
        ),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final s in <AttestationStatus?>[
              null,
              ...AttestationStatus.values,
            ])
              ChoiceChip(
                label: Text(_filterLabel(context.l10n, s)),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
              ),
          ],
        ),
        if (shown.isEmpty)
          Text(context.l10n.attLogScreenNoEntries, style: WText.caption)
        else
          SectionCard(
            children: [
              for (final r in shown)
                AttestationLogRow(
                  key: ValueKey(r.logId),
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
        WideButton(
          context.l10n.attLogScreenDeleteLog,
          onPressed: () => unawaited(_delete()),
        ),
      ],
    );
  }

  /// Attests only [profileId] again (lifts its lock when the check passes).
  Future<void> _reattest(String profileId) async {
    final report = await ref.read(attestationHubProvider).reattest(profileId);
    ref.invalidate(attestationRecordsProvider);
    if (!mounted) return;
    showHint(
      context,
      report?.status == AttestationStatus.green
          ? context.l10n.attLogScreenRechecked
          : context.l10n.attLogRecheckFailed,
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: context.l10n.attLogScreenDeleteTitle,
      message: context.l10n.attLogScreenDeleteBody,
      yes: context.l10n.delete,
    );
    if (!ok) return;
    await ref.read(storageProvider).attestations.deleteAll();
    ref.invalidate(attestationRecordsProvider);
    if (mounted) showHint(context, context.l10n.attLogScreenDeleted);
  }
}

/// Session of one provider: result, ids and the stage results in two
/// columns (design: `pruefprotokoll.html`).
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.record,
    required this.name,
    required this.locked,
    this.toolsEncrypted = false,
    required this.now,
    required this.onReattest,
  });

  final AttestationRecord record;
  final String name;
  final bool locked;

  /// Tools sind Ende-zu-Ende-verschlüsselt (NEAR AI).
  final bool toolsEncrypted;
  final DateTime now;
  final VoidCallback onReattest;

  @override
  Widget build(BuildContext context) {
    final status = recordStatus(record);
    final label = locked
        ? 'gesperrt'
        : switch (record.status) {
            AttestationStatus.green => context.l10n.attLogScreenSessionGreen,
            AttestationStatus.yellow => context.l10n.attLogScreenSessionYellow,
            AttestationStatus.red => context.l10n.attLogScreenSessionRed,
            AttestationStatus.unconfirmed =>
              context.l10n.attLogScreenSessionUnconfirmed,
          };
    final color = locked ? CheckStatus.failed.color : status.color;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(WSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WSpace.s,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(name, style: WText.label)),
                  Text(label, style: WText.mono.copyWith(color: color)),
                ],
              ),
              Text(
                [
                  ?record.workloadKeysetDigest,
                  if (record.repoCommit != null)
                    context.l10n.attLogScreenCommitLine(record.repoCommit!),
                  sessionLabel(context.l10n, record.at, now),
                ].join('\n'),
                style: WText.mono.copyWith(color: WColors.textMuted),
              ),
              Wrap(
                spacing: WSpace.l,
                runSpacing: WSpace.xs,
                children: [
                  for (final st in record.stages)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: WSpace.xs,
                      children: [
                        CheckStatusIcon(
                          stageResultStatus(st.result),
                          size: WSize.statusIconSmall,
                        ),
                        Text(
                          stageLabel(context.l10n, st.stage),
                          style: WText.caption,
                        ),
                      ],
                    ),
                ],
              ),
              ToolTlsHint(encrypted: toolsEncrypted),
              PrimaryButton(
                context.l10n.attLogScreenRecheckAttest,
                key: ValueKey('reattest-${record.profileId}'),
                onPressed: onReattest,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of the verification log: result symbol, title and summary.
class AttestationLogRow extends StatelessWidget {
  /// Creates a row.
  const AttestationLogRow({
    super.key,
    required this.title,
    required this.detail,
    required this.status,
    required this.onTap,
  });

  final String title;
  final String detail;
  final CheckStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: WSize.listRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.l,
          vertical: WSpace.m,
        ),
        child: Row(
          spacing: WSpace.m,
          children: [
            CheckStatusIcon(status),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xxs,
                children: [
                  Text(title, style: WText.label),
                  Text(detail, style: WText.mono.copyWith(color: status.color)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The stage rows of a record, shared by the detail page and tests.
List<Widget> stageRows(AppLocalizations l, AttestationRecord r) => [
  for (final s in r.stages)
    StageLine(
      label: stageLabel(l, s.stage),
      result: stageResultLabel(l, s.result),
      detail: _stageDetail(l, s),
      status: stageResultStatus(s.result),
    ),
];

String? _stageDetail(AppLocalizations l, StageRecord s) {
  final parts = [?s.detail, ?stageExplanation(l, s.stage)];
  return parts.isEmpty ? null : parts.join('\n');
}
