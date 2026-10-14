import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/attestation_log_view.dart';
import '../../di/providers.dart';
import '../attestation/attestation_texts.dart';
import '../attestation/stage_line.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'attestation_log_detail.dart';
import 'export.dart';
import 'gpu_check_section.dart';
import 'settings_page.dart';

/// Short line of a log entry: time, result and receipt id.
String recordSummary(AttestationRecord r, DateTime now) {
  final parts = [
    sessionLabel(r.at, now),
    switch (r.status) {
      AttestationStatus.green => 'geprüft',
      AttestationStatus.yellow => 'ausstehend',
      AttestationStatus.red => 'fehlgeschlagen',
    },
    ?r.receiptId,
  ];
  return parts.join(' · ');
}

/// Title of a log entry: what was checked.
String recordTitle(AttestationRecord r, String providerName) =>
    switch (r.kind) {
      AttestationRecordKind.session => 'Sitzung · $providerName',
      AttestationRecordKind.receipt =>
        '${r.model ?? 'Antwort'} · $providerName',
      AttestationRecordKind.gpu => 'GPU · ${r.model ?? providerName}',
    };

/// Symbol of an entry's overall result.
CheckStatus recordStatus(AttestationRecord r) => switch (r.status) {
  AttestationStatus.green => CheckStatus.ok,
  AttestationStatus.yellow => CheckStatus.pending,
  AttestationStatus.red => CheckStatus.failed,
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

  static String _filterLabel(AttestationStatus? s) => switch (s) {
    null => 'Alle',
    AttestationStatus.green => 'Geprüft',
    AttestationStatus.yellow => 'Wird geprüft',
    AttestationStatus.red => 'Fehlgeschlagen',
  };

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(attestationRecordsProvider).value ?? const [];
    final shown = [
      for (final r in records)
        if (_filter == null || r.status == _filter) r,
    ];
    final now = ref.watch(clockProvider).now();
    final config = ref.watch(providerConfigProvider).value;
    return SettingsPage(
      title: 'Prüfprotokoll',
      intro:
          'Wendelin prüft Anbieter mit geschützter Umgebung (TEE) und jede '
          'Antwort. Hier steht, was geprüft wurde. Nie Inhalte, nur Ids, '
          'Prüfsummen und Ergebnisse.',
      children: [
        const GpuCheckSection(),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final s in <AttestationStatus?>[
              null,
              ...AttestationStatus.values,
            ])
              ChoiceChip(
                label: Text(_filterLabel(s)),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
              ),
          ],
        ),
        if (shown.isEmpty)
          Text('Keine Einträge.', style: WText.caption)
        else
          SectionCard(
            children: [
              for (final r in shown)
                _LogRow(
                  key: ValueKey(r.logId),
                  title: recordTitle(
                    r,
                    config?.nameOf(r.profileId) ?? r.profileId,
                  ),
                  detail: recordSummary(r, now),
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
          'Als JSON exportieren',
          onPressed: () async => ref.read(exporterProvider)(
            'wendelin-tee-pruefprotokoll.json',
            'application/json',
            await ref.read(storageProvider).attestations.exportJson(),
          ),
        ),
        WideButton(
          'Prüfprotokoll löschen',
          onPressed: () => unawaited(_delete()),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Prüfprotokoll löschen?',
      message:
          'Alle Einträge des Prüfprotokolls werden gelöscht. Das lässt sich '
          'nicht rückgängig machen.',
      yes: 'Löschen',
    );
    if (!ok) return;
    await ref.read(storageProvider).attestations.deleteAll();
    ref.invalidate(attestationRecordsProvider);
    if (mounted) showHint(context, 'Gelöscht.');
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
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
List<Widget> stageRows(AttestationRecord r) => [
  for (final s in r.stages)
    StageLine(
      label: stageLabel(s.stage),
      result: stageResultLabel(s.result),
      detail: s.detail,
      status: stageResultStatus(s.result),
    ),
];
