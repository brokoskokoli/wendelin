import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Ausführung“: level (with suggestion by method), auto-run, sensitive,
/// home network, enabled and time limit.
class RunSection extends StatelessWidget {
  /// Creates the section.
  const RunSection({
    super.key,
    required this.draft,
    required this.onEdit,
    this.levelField,
  });

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Edit callback.
  final DraftEdit onEdit;

  /// The security level A–D of the tool (WP160); `null` while it has no
  /// valid name yet.
  final Widget? levelField;

  Widget _levelChoice(BuildContext context) {
    final d = draft;
    return EditorField(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.s,
        children: [
          Text(
            context.l10n.httpRunLevel(
              d.method.verb,
              d.method.suggestedRisk.name,
            ),
            style: WText.detail,
          ),
          Wrap(
            spacing: WSpace.s,
            children: [
              for (final r in d.riskChoices)
                ChoiceChip(
                  label: Text(r.name),
                  selected: d.risk == r,
                  onSelected: (_) => onEdit(() => d.risk = r),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SettingsSection(
      title: context.l10n.httpRunExecution,
      children: [
        _levelChoice(context),
        ?levelField,
        SettingsRow(
          title: context.l10n.httpRunNoAsk,
          detail: d.autoRunAvailable
              ? context.l10n.httpRunAskElse
              : context.l10n.httpRunOnlyWrite,
          trailing: WSwitch(
            value: d.autoRun && d.autoRunAvailable,
            semanticLabel: context.l10n.httpRunNoAskSem,
            onChanged: d.autoRunAvailable
                ? (on) => onEdit(() => d.autoRun = on)
                : null,
          ),
        ),
        SettingsRow(
          title: context.l10n.httpRunUntrusted,
          detail: context.l10n.httpRunUntrustedDetail,
          trailing: WSwitch(
            value: d.mayContainUntrustedContent,
            semanticLabel: context.l10n.httpRunUntrusted,
            onChanged: (on) => onEdit(() => d.mayContainUntrustedContent = on),
          ),
        ),
        SettingsRow(
          title: context.l10n.mcpAddSensitive,
          detail: context.l10n.httpRunSensitiveDetail,
          trailing: WSwitch(
            value: d.sensitive,
            semanticLabel: context.l10n.mcpAddSensitive,
            onChanged: (on) => onEdit(() => d.sensitive = on),
          ),
        ),
        SettingsRow(
          title: context.l10n.httpRunHomeTarget,
          detail: context.l10n.httpRunHomeTargetDetail,
          trailing: WSwitch(
            value: d.homeNetwork,
            semanticLabel: context.l10n.httpRunHomeTargetSem,
            onChanged: (on) => onEdit(() => d.homeNetwork = on),
          ),
        ),
        SettingsRow(
          title: context.l10n.ruleEditorActive,
          trailing: WSwitch(
            value: d.enabled,
            semanticLabel: context.l10n.ruleEditorActive,
            onChanged: (on) => onEdit(() => d.enabled = on),
          ),
        ),
        EditorField(
          child: TextFormField(
            key: const ValueKey('timeout'),
            initialValue: d.timeoutSeconds,
            style: WText.body,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.httpRunTimeout,
              helperText: '1–${httpToolMaxTimeout.inSeconds}',
            ),
            onChanged: (v) => onEdit(() => d.timeoutSeconds = v),
          ),
        ),
      ],
    );
  }
}
