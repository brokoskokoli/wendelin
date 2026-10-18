import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/audit_export.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'audit_entry_screen.dart';
import 'export.dart';
import 'privacy_screen.dart';
import 'settings_page.dart';

/// Settings → Datenschutz und Logs → Prüfprotokoll: the audit log with
/// export as JSON (above the list, without contents) and filter by kind;
/// a tap opens the entry.
class AuditLogScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogState();
}

class _AuditLogState extends ConsumerState<AuditLogScreen> {
  AuditKind? _filter;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(auditViewProvider(_filter)).value ?? const [];
    final now = ref.watch(clockProvider).now();
    return SettingsPage(
      title: context.l10n.auditLogTitle,
      intro: context.l10n.auditLogIntro,
      children: [
        WideButton(
          context.l10n.attLogScreenExportJson,
          onPressed: () async => ref.read(exporterProvider)(
            'wendelin-pruefprotokoll.json',
            'application/json',
            auditExportWithoutContent(
              await ref.read(storageProvider).audit.exportJson(),
            ),
          ),
        ),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final k in <AuditKind?>[null, ...AuditKind.values])
              ChoiceChip(
                label: Text(
                  k == null
                      ? context.l10n.attLogScreenFilterAll
                      : auditKindLabel(context.l10n, k),
                ),
                selected: _filter == k,
                onSelected: (_) => setState(() => _filter = k),
              ),
          ],
        ),
        if (entries.isEmpty)
          Text(context.l10n.attLogScreenNoEntries, style: WText.caption)
        else
          SectionCard(
            children: [
              for (final e in entries.take(100))
                SettingsRow(
                  title:
                      '${auditKindLabel(context.l10n, e.kind)} · '
                      '${sessionLabel(context.l10n, e.at, now)}',
                  detail: auditSummary(context.l10n, e),
                  onTap: () => unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => AuditEntryScreen(entry: e),
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
