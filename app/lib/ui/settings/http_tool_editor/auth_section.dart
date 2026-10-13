import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../di/http_tool_draft.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Anmeldung“: none, bearer token or secret headers. Stored secrets are
/// masked and can only be replaced.
class AuthSection extends StatelessWidget {
  /// Creates the section.
  const AuthSection({
    super.key,
    required this.draft,
    required this.replacing,
    required this.onReplace,
    required this.onEdit,
  });

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Owners (draft or header) whose stored secret is being replaced.
  final Set<Object> replacing;

  /// The user chose „Ersetzen“ for [owner].
  final void Function(Object owner) onReplace;

  /// Edit callback.
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SettingsSection(
      title: 'Anmeldung',
      children: [
        EditorField(
          child: Wrap(
            spacing: WSpace.s,
            children: [
              for (final kind in HttpAuthKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: d.auth == kind,
                  onSelected: (_) => onEdit(() => d.auth = kind),
                ),
            ],
          ),
        ),
        if (d.auth == HttpAuthKind.bearer)
          _secretRow(
            owner: d,
            label: 'Bearer-Token',
            stored: d.bearerStored,
            onChanged: (v) => d.bearerNew = v,
          ),
        if (d.auth == HttpAuthKind.headers) ...[
          for (final (i, h) in d.secretHeaders.indexed) _secretHeader(d, h, i),
          SettingsRow(
            title: '+ Geheimer Header',
            onTap: () =>
                onEdit(() => d.secretHeaders.add(HttpSecretHeaderDraft())),
          ),
        ],
      ],
    );
  }

  Widget _secretHeader(HttpToolDraft d, HttpSecretHeaderDraft h, int i) {
    final remove = WIconButton(
      icon: WIcons.close,
      tooltip: 'Geheimen Header entfernen',
      iconSize: WSize.iconSmall,
      onPressed: () => onEdit(() => d.secretHeaders.remove(h)),
    );
    return Column(
      key: ObjectKey(h),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (h.stored)
          SettingsRow(title: h.name, mono: true, trailing: remove)
        else
          EditorField(
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('secretHeaderName$i'),
                    initialValue: h.name,
                    style: WText.mono,
                    decoration: const InputDecoration(
                      labelText: 'Geheimer Header, z. B. X-Api-Key',
                    ),
                    onChanged: (v) => onEdit(() => h.name = v),
                  ),
                ),
                remove,
              ],
            ),
          ),
        _secretRow(
          owner: h,
          label: 'Wert',
          stored: h.stored,
          onChanged: (v) => h.newValue = v,
          fieldKey: ValueKey('secretHeaderValue$i'),
        ),
      ],
    );
  }

  /// A secret value: stored ones are masked and can only be replaced.
  Widget _secretRow({
    required Object owner,
    required String label,
    required bool stored,
    required void Function(String value) onChanged,
    Key fieldKey = const ValueKey('secret'),
  }) {
    if (stored && !replacing.contains(owner)) {
      return SettingsRow(
        title: label,
        detail: '$redactedSecret gespeichert',
        trailing: TextButton(
          onPressed: () => onReplace(owner),
          child: const Text('Ersetzen'),
        ),
      );
    }
    return EditorField(
      child: AutofillGroup(
        child: SecretField(
          key: fieldKey,
          label: label,
          mono: true,
          helperText: stored ? 'Leer lassen behält den gespeicherten' : null,
          onChanged: (v) => onEdit(() => onChanged(v)),
        ),
      ),
    );
  }
}
