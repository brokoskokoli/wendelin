import 'package:flutter/material.dart';

import '../../../di/http_tool_draft.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Argumente“: simple list (name, type, description, required) or an own
/// JSON schema.
class ArgsSection extends StatelessWidget {
  /// Creates the section.
  const ArgsSection({super.key, required this.draft, required this.onEdit});

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Edit callback.
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SettingsSection(
      title: 'Argumente',
      children: [
        SettingsRow(
          title: 'Eigenes JSON-Schema',
          detail: 'Statt der einfachen Liste',
          trailing: WSwitch(
            value: d.rawSchema,
            semanticLabel: 'Eigenes JSON-Schema',
            onChanged: (on) => onEdit(() {
              if (on) {
                try {
                  d.schemaText = prettyJson(d.schema());
                } on FormatException {
                  // Die Liste ist noch unvollständig: Text bleibt.
                }
              }
              d.rawSchema = on;
            }),
          ),
        ),
        if (d.rawSchema)
          EditorField(
            child: TextFormField(
              key: const ValueKey('schema'),
              initialValue: d.schemaText,
              style: WText.mono,
              minLines: 4,
              maxLines: 14,
              decoration: const InputDecoration(labelText: 'JSON-Schema'),
              onChanged: (v) => onEdit(() => d.schemaText = v),
            ),
          )
        else ...[
          for (final (i, a) in d.args.indexed)
            _ArgEditor(draft: d, arg: a, index: i, onEdit: onEdit),
          SettingsRow(
            title: '+ Argument',
            onTap: () => onEdit(() => d.args.add(HttpArgDraft())),
          ),
        ],
      ],
    );
  }
}

class _ArgEditor extends StatelessWidget {
  _ArgEditor({
    required this.draft,
    required this.arg,
    required this.index,
    required this.onEdit,
  }) : super(key: ObjectKey(arg));

  final HttpToolDraft draft;
  final HttpArgDraft arg;
  final int index;
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final a = arg;
    final i = index;
    return EditorField(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: WSpace.s,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('argName$i'),
                  initialValue: a.name,
                  style: WText.mono,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (v) => onEdit(() => a.name = v),
                ),
              ),
              WIconButton(
                icon: WIcons.close,
                tooltip: 'Argument entfernen',
                iconSize: WSize.iconSmall,
                onPressed: () => onEdit(() => draft.args.remove(a)),
              ),
            ],
          ),
          Wrap(
            spacing: WSpace.s,
            children: [
              for (final t in httpArgTypes)
                ChoiceChip(
                  key: ValueKey('argType$i-$t'),
                  label: Text(t),
                  selected: a.type == t,
                  onSelected: (_) => onEdit(() => a.type = t),
                ),
            ],
          ),
          TextFormField(
            key: ValueKey('argDescription$i'),
            initialValue: a.description,
            style: WText.body,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
            onChanged: (v) => onEdit(() => a.description = v),
          ),
          Row(
            children: [
              Expanded(child: Text('Pflicht', style: WText.detail)),
              WSwitch(
                value: a.required,
                semanticLabel: 'Pflicht ${a.name}',
                onChanged: (on) => onEdit(() => a.required = on),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
