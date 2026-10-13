import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../di/http_tool_draft.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Ausführung“: level (with suggestion by method), auto-run, sensitive,
/// home network, enabled and time limit.
class RunSection extends StatelessWidget {
  /// Creates the section.
  const RunSection({super.key, required this.draft, required this.onEdit});

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Edit callback.
  final DraftEdit onEdit;

  Widget _levelChoice() {
    final d = draft;
    return EditorField(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.s,
        children: [
          Text(
            'Stufe (Vorschlag für ${d.method.verb}: '
            '${d.method.suggestedRisk.name})',
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
      title: 'Ausführung',
      children: [
        _levelChoice(),
        SettingsRow(
          title: 'Ohne Nachfrage ausführen (kein Rückgängig)',
          detail: d.autoRunAvailable
              ? 'Sonst fragt Wendelin vor jedem Aufruf nach'
              : 'Nur bei POST/PUT/PATCH mit Stufe write',
          trailing: WSwitch(
            value: d.autoRun && d.autoRunAvailable,
            semanticLabel: 'Ohne Nachfrage ausführen',
            onChanged: d.autoRunAvailable
                ? (on) => onEdit(() => d.autoRun = on)
                : null,
          ),
        ),
        SettingsRow(
          title: 'Sensibel',
          detail: 'Nur an Provider ab der Stufe für sensible Integrationen',
          trailing: WSwitch(
            value: d.sensitive,
            semanticLabel: 'Sensibel',
            onChanged: (on) => onEdit(() => d.sensitive = on),
          ),
        ),
        SettingsRow(
          title: 'Heimnetz-Ziel',
          detail: 'Darf auf private Adressen zeigen, dann auch http',
          trailing: WSwitch(
            value: d.homeNetwork,
            semanticLabel: 'Heimnetz-Ziel',
            onChanged: (on) => onEdit(() => d.homeNetwork = on),
          ),
        ),
        SettingsRow(
          title: 'Aktiv',
          trailing: WSwitch(
            value: d.enabled,
            semanticLabel: 'Aktiv',
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
              labelText: 'Zeitlimit in Sekunden',
              helperText: '1–${httpToolMaxTimeout.inSeconds}',
            ),
            onChanged: (v) => onEdit(() => d.timeoutSeconds = v),
          ),
        ),
      ],
    );
  }
}
