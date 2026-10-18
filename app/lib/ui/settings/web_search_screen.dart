import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Settings → Web-Suche: choose Brave, Tavily or an own SearXNG. The key
/// goes straight into the `SecretStore`. Without a service only
/// `web__fetch` (reading pages) is available.
class WebSearchScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WebSearchScreen({super.key});

  @override
  ConsumerState<WebSearchScreen> createState() => _WebSearchState();
}

class _WebSearchState extends ConsumerState<WebSearchScreen> {
  WebSearchKind? _kind;
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _hasKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = ref.read(webSearchConfigProvider);
    _kind = config?.kind;
    _url.text = config?.baseUrl ?? '';
    unawaited(_checkKey());
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    final kind = _kind;
    final has =
        kind != null &&
        await ref.read(webSearchConfigProvider.notifier).hasKey(kind);
    if (mounted) setState(() => _hasKey = has);
  }

  Future<void> _save() async {
    final kind = _kind;
    final notifier = ref.read(webSearchConfigProvider.notifier);
    if (kind == null) {
      await notifier.set(null);
    } else if (kind == WebSearchKind.searxng &&
        !(Uri.tryParse(_url.text.trim())?.hasScheme ?? false)) {
      setState(() => _error = context.l10n.webSearchAddressMissing);
      return;
    } else if (kind.needsKey && !_hasKey && _key.text.trim().isEmpty) {
      setState(() => _error = context.l10n.webSearchKeyMissing);
      return;
    } else {
      await notifier.set(
        WebSearchConfig(
          kind,
          baseUrl: kind == WebSearchKind.searxng ? _url.text.trim() : null,
        ),
        apiKey: _key.text,
      );
    }
    // Commit while the field still holds the value, then clear it.
    SecretField.finishAutofill();
    _key.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return SettingsPage(
      title: context.l10n.webSearchTitle,
      intro: context.l10n.webSearchIntro,
      children: [
        SectionCard(
          children: [
            for (final (k, label) in <(WebSearchKind?, String)>[
              (null, context.l10n.webSearchNone),
              for (final k in WebSearchKind.values)
                (k, k.labelOf(context.l10n)),
            ])
              SettingsRow(
                title: label,
                onTap: () {
                  setState(() {
                    _kind = k;
                    _error = null;
                  });
                  unawaited(_checkKey());
                },
                trailing: _kind == k
                    ? CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: context.l10n.selected,
                      )
                    : null,
              ),
          ],
        ),
        if (kind == WebSearchKind.searxng)
          TextField(
            controller: _url,
            style: WText.body,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.l10n.webSearchAddress,
            ),
          ),
        if (kind != null && kind.needsKey)
          AutofillGroup(
            child: SecretField(
              key: const ValueKey('searchKey'),
              controller: _key,
              label: context.l10n.webSearchApiKey,
              helperText: _hasKey ? context.l10n.webSearchKeySaved : null,
            ),
          ),
        if (_error != null) Text(_error!, style: WText.caption),
        PrimaryButton(context.l10n.save, onPressed: () => unawaited(_save())),
      ],
    );
  }
}
