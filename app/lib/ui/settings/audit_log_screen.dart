import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../../di/providers.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'export.dart';
import 'privacy_screen.dart';
import 'settings_page.dart';

/// Settings → Datenschutz und Logs → Prüfprotokoll ansehen: the audit log
/// with filter by kind and export as JSON (WP65: own page instead of inline).
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
      title: 'Prüfprotokoll',
      intro: 'Was Wendelin getan hat. Nie Schlüssel, nur Ids und Ergebnisse.',
      children: [
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final k in <AuditKind?>[null, ...AuditKind.values])
              ChoiceChip(
                label: Text(k == null ? 'Alle' : auditKindLabel(k)),
                selected: _filter == k,
                onSelected: (_) => setState(() => _filter = k),
              ),
          ],
        ),
        if (entries.isEmpty)
          Text('Keine Einträge.', style: WText.caption)
        else
          SectionCard(
            children: [
              for (final e in entries.take(100))
                SettingsRow(
                  title:
                      '${auditKindLabel(e.kind)} · '
                      '${sessionLabel(e.at, now)}',
                  detail: auditSummary(e),
                ),
            ],
          ),
        WideButton(
          'Als JSON exportieren',
          onPressed: () async => ref.read(exporterProvider)(
            'wendelin-pruefprotokoll.json',
            'application/json',
            await ref.read(storageProvider).audit.exportJson(),
          ),
        ),
      ],
    );
  }
}
