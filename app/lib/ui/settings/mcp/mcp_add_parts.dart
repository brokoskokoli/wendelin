import 'package:flutter/material.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';

/// Fields of the chosen login type (nothing, token, header, client id).
List<Widget> mcpAuthFields({
  required McpAuthKind auth,
  required McpTemplate template,
  required TextEditingController token,
  required TextEditingController headerName,
  required TextEditingController headerValue,
  required TextEditingController clientId,
  required AppLocalizations l,
}) => switch (auth) {
  McpAuthKind.none => const [],
  McpAuthKind.bearer => [
    AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: SecretField(
        key: const ValueKey('mcpToken'),
        controller: token,
        label: 'Token',
        helperText: template.authHint ?? l.mcpAddTokenHint,
      ),
    ),
  ],
  McpAuthKind.headers => [
    TextField(
      key: const ValueKey('mcpHeaderName'),
      controller: headerName,
      style: WText.body,
      autocorrect: false,
      decoration: InputDecoration(labelText: l.mcpAddHeaderLabel),
    ),
    AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: SecretField(
        key: const ValueKey('mcpHeaderValue'),
        controller: headerValue,
        label: l.mcpAddValue,
        helperText: l.mcpAddValueHint,
      ),
    ),
  ],
  McpAuthKind.oauth => [
    TextField(
      key: ValueKey('mcpClientId'),
      controller: clientId,
      style: WText.body,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: l.mcpAddClientId,
        helperText: l.mcpAddClientIdHint,
        helperMaxLines: 2,
      ),
    ),
  ],
};

/// Step 1: the templates (Home Assistant, Obsidian, CalDAV, own server).
class McpTemplateList extends StatelessWidget {
  /// Creates the list.
  const McpTemplateList({super.key, required this.onChoose});

  /// A template was chosen.
  final void Function(McpTemplate template) onChoose;

  @override
  Widget build(BuildContext context) => SectionCard(
    children: [
      for (final t in McpTemplate.all)
        SettingsRow(
          title: t == McpTemplate.custom ? context.l10n.mcpAddCustom : t.name,
          detail: t.description,
          onTap: () => onChoose(t),
        ),
    ],
  );
}

/// „Anmeldung“: the login types, the chosen one is ticked.
class McpAuthChoice extends StatelessWidget {
  /// Creates the section.
  const McpAuthChoice({super.key, required this.auth, required this.onPick});

  /// The chosen login type.
  final McpAuthKind auth;

  /// A login type was chosen.
  final void Function(McpAuthKind kind) onPick;

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: context.l10n.mcpAddSignIn,
    children: [
      for (final kind in McpAuthKind.values)
        SettingsRow(
          title: kind.label,
          onTap: () => onPick(kind),
          trailing: auth == kind
              ? CheckStatusIcon(
                  CheckStatus.ok,
                  semanticLabel: context.l10n.selected,
                )
              : null,
        ),
    ],
  );
}

/// „Alle Tools bestätigen“ and „Sensibel“ of a new server.
class McpAddOptions extends StatelessWidget {
  /// Creates the card.
  const McpAddOptions({
    super.key,
    required this.confirmAll,
    required this.sensitive,
    required this.onConfirmAll,
    required this.onSensitive,
  });

  /// Every call asks first.
  final bool confirmAll;

  /// Tools only to providers of the set level.
  final bool sensitive;

  /// Switch callbacks.
  final ValueChanged<bool> onConfirmAll, onSensitive;

  @override
  Widget build(BuildContext context) => SectionCard(
    children: [
      SettingsRow(
        title: context.l10n.mcpAddConfirmAll,
        detail: context.l10n.mcpAddConfirmAllHint,
        trailing: WSwitch(
          value: confirmAll,
          semanticLabel: context.l10n.mcpAddConfirmAll,
          onChanged: onConfirmAll,
        ),
      ),
      SettingsRow(
        title: context.l10n.mcpAddSensitive,
        detail: context.l10n.mcpAddSensitiveHint,
        trailing: WSwitch(
          value: sensitive,
          semanticLabel: context.l10n.mcpAddSensitive,
          onChanged: onSensitive,
        ),
      ),
    ],
  );
}

/// Result of „Verbindung prüfen“.
class McpProbeRow extends StatelessWidget {
  /// Creates the row.
  const McpProbeRow({super.key, required this.text, required this.ok});

  /// What the probe found.
  final String text;

  /// The server is reachable.
  final bool ok;

  @override
  Widget build(BuildContext context) => Row(
    spacing: WSpace.s,
    children: [
      CheckStatusIcon(
        ok ? CheckStatus.ok : CheckStatus.failed,
        semanticLabel: ok
            ? context.l10n.mcpLabelsReachable
            : context.l10n.mcpAddProblem,
      ),
      Expanded(child: Text(text, style: WText.detail)),
    ],
  );
}
