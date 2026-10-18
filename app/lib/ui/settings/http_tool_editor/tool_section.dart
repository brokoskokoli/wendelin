import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Tool“: name (rule checked live) and description for the model.
class ToolSection extends StatelessWidget {
  /// Creates the section.
  const ToolSection({
    super.key,
    required this.draft,
    required this.otherNames,
    required this.onEdit,
  });

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Names of the other tools (for the uniqueness check).
  final List<String> otherNames;

  /// Edit callback.
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SettingsSection(
      title: context.l10n.privacyScreenKindTool,
      children: [
        EditorField(
          child: TextFormField(
            key: const ValueKey('name'),
            initialValue: d.name,
            style: WText.mono,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.name,
              prefixText: 'http__',
              errorText: d.name.isEmpty ? null : d.nameError(otherNames),
            ),
            onChanged: (v) => onEdit(() => d.name = v),
          ),
        ),
        EditorField(
          child: TextFormField(
            key: const ValueKey('description'),
            initialValue: d.description,
            style: WText.body,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: context.l10n.httpToolSecModelDescription,
              helperText: context.l10n.httpToolSecModelDescriptionHelp,
            ),
            onChanged: (v) => onEdit(() => d.description = v),
          ),
        ),
      ],
    );
  }
}
