import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Anfrage“: method, URL template, headers and body template.
class RequestSection extends StatelessWidget {
  /// Creates the section.
  const RequestSection({
    super.key,
    required this.draft,
    required this.url,
    required this.onEdit,
  });

  /// The tool being edited.
  final HttpToolDraft draft;

  /// Controller of the URL field (highlights placeholders).
  final TextEditingController url;

  /// Edit callback.
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SettingsSection(
      title: context.l10n.privacyScreenKindRequest,
      children: [
        EditorField(
          child: Wrap(
            spacing: WSpace.s,
            runSpacing: WSpace.s,
            children: [
              for (final m in HttpMethod.values)
                ChoiceChip(
                  label: Text(m.verb),
                  selected: d.method == m,
                  onSelected: (_) => onEdit(() => d.setMethod(m)),
                ),
            ],
          ),
        ),
        EditorField(
          child: TextField(
            key: const ValueKey('url'),
            controller: url,
            style: WText.mono,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.httpSrcUrlTemplate,
              helperText: context.l10n.httpSrcUrlHelp('{entity}'),
              helperMaxLines: 2,
            ),
            onChanged: (v) => onEdit(() => d.url = v),
          ),
        ),
        for (final (i, h) in d.headers.indexed)
          _HeaderRow(draft: d, header: h, index: i, onEdit: onEdit),
        SettingsRow(
          title: context.l10n.httpSrcAddHeader,
          detail: context.l10n.httpSrcHeaderDetail,
          onTap: () => onEdit(() => d.headers.add(HttpHeaderDraft())),
        ),
        if (d.method.allowsBody) ..._body(context, d),
      ],
    );
  }

  List<Widget> _body(BuildContext context, HttpToolDraft d) => [
    EditorField(
      child: Wrap(
        spacing: WSpace.s,
        children: [
          for (final (f, label) in [
            (HttpBodyFormat.json, context.l10n.httpSrcJson),
            (HttpBodyFormat.form, context.l10n.httpSrcForm),
          ])
            ChoiceChip(
              label: Text(label),
              selected: d.bodyFormat == f,
              onSelected: (_) => onEdit(() => d.bodyFormat = f),
            ),
        ],
      ),
    ),
    EditorField(
      child: TextFormField(
        key: const ValueKey('body'),
        initialValue: d.body,
        style: WText.mono,
        minLines: 2,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: context.l10n.httpSrcBodyTemplate,
          helperText: context.l10n.httpSrcBodyHelp('"{name}"'),
        ),
        onChanged: (v) => onEdit(() => d.body = v),
      ),
    ),
  ];
}

class _HeaderRow extends StatelessWidget {
  _HeaderRow({
    required this.draft,
    required this.header,
    required this.index,
    required this.onEdit,
  }) : super(key: ObjectKey(header));

  final HttpToolDraft draft;
  final HttpHeaderDraft header;
  final int index;
  final DraftEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final h = header;
    return EditorField(
      child: Row(
        spacing: WSpace.s,
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('headerName$index'),
              initialValue: h.name,
              style: WText.mono,
              decoration: InputDecoration(
                labelText: context.l10n.httpSrcHeader,
              ),
              onChanged: (v) => onEdit(() => h.name = v),
            ),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('headerValue$index'),
              initialValue: h.value,
              style: WText.mono,
              decoration: InputDecoration(labelText: context.l10n.mcpAddValue),
              onChanged: (v) => onEdit(() => h.value = v),
            ),
          ),
          WIconButton(
            icon: WIcons.close,
            tooltip: context.l10n.httpSrcRemoveHeader,
            iconSize: WSize.iconSmall,
            onPressed: () => onEdit(() => draft.headers.remove(h)),
          ),
        ],
      ),
    );
  }
}
