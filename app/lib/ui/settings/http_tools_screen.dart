import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/http_tools.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'export.dart';
import 'http_tool_editor_screen.dart';
import 'settings_page.dart';

/// Settings → HTTP-Tools (concept: „Erweiterungswege 1“): the user's own
/// tools with method, target and level; add, edit, import and export
/// (without secrets).
class HttpToolsScreen extends ConsumerWidget {
  /// Creates the screen.
  const HttpToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(httpToolRepositoryProvider);
    return StreamBuilder<void>(
      stream: repository.changes,
      builder: (context, _) => FutureBuilder<List<HttpToolDefinition>>(
        future: repository.definitions(),
        builder: (context, snapshot) {
          final tools = snapshot.data ?? const <HttpToolDefinition>[];
          return SettingsPage(
            title: context.l10n.areaHttpTools,
            intro: context.l10n.httpToolsIntro,
            children: [
              if (tools.isNotEmpty)
                SectionCard(
                  children: [
                    for (final d in tools)
                      SettingsRow(
                        title: d.toolName,
                        mono: true,
                        detail: httpToolSummary(context.l10n, d),
                        onTap: () => unawaited(_open(context, d)),
                      ),
                  ],
                ),
              WideButton(
                context.l10n.integrationsAddHttp,
                onPressed: () => unawaited(_open(context, null)),
              ),
              Row(
                spacing: WSpace.m,
                children: [
                  Expanded(
                    child: WideButton(
                      context.l10n.import,
                      onPressed: () => unawaited(_import(context, ref)),
                    ),
                  ),
                  Expanded(
                    child: WideButton(
                      context.l10n.export,
                      onPressed: tools.isEmpty
                          ? null
                          : () => unawaited(_export(context, ref)),
                    ),
                  ),
                ],
              ),
              InfoBox(context.l10n.httpToolsExportNote),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, HttpToolDefinition? d) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HttpToolEditorScreen(definition: d),
        ),
      );

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final export = ref.read(exporterProvider);
    final json = await ref.read(httpToolRepositoryProvider).exportJson();
    await export('wendelin-http-tools.json', 'application/json', json);
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(httpToolRepositoryProvider);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final imported = await repository.importJson(text);
      if (context.mounted) {
        showHint(context, context.l10n.httpToolsImported(imported.length));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        showHint(context, context.l10n.httpToolsImportFailed(e.message));
      }
    }
  }
}

/// Second line of an HTTP tool in the list: method, host, level.
String httpToolSummary(AppLocalizations l, HttpToolDefinition d) {
  String host;
  try {
    host = d.url.origin.host;
  } on FormatException {
    host = '?';
  }
  return [
    d.method.verb,
    host,
    httpRiskText(l, d),
    if (d.sensitive) l.httpToolsSensitiveShort,
    if (!d.enabled) l.httpToolsOffShort,
  ].join(' · ');
}

/// German text of the effective level of [d] (HTTP tools have no undo).
String httpRiskText(AppLocalizations l, HttpToolDefinition d) =>
    switch (d.effectiveRisk) {
      RiskLevel.read => l.httpToolsRiskRead,
      RiskLevel.write => l.httpToolsRiskWrite,
      RiskLevel.external => l.mcpLabelsAlwaysAsks,
    };

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: WColors.surface,
    title: Text(context.l10n.httpToolsImportTitle, style: WText.label),
    content: TextField(
      key: const ValueKey('importJson'),
      controller: _text,
      style: WText.mono,
      minLines: 4,
      maxLines: 10,
      decoration: InputDecoration(labelText: context.l10n.httpToolsExportPaste),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_text.text),
        child: Text(context.l10n.import),
      ),
    ],
  );
}
