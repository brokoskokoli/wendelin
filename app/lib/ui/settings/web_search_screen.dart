import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
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
      setState(() => _error = 'Bitte die Adresse der Instanz angeben.');
      return;
    } else if (kind.needsKey && !_hasKey && _key.text.trim().isEmpty) {
      setState(() => _error = 'Bitte den API-Key eingeben.');
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
    _key.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return SettingsPage(
      title: 'Web-Suche',
      intro:
          'Ohne Suchdienst kann Wendelin nur Seiten lesen, deren Adresse du '
          'nennst.',
      children: [
        SectionCard(
          children: [
            for (final (k, label) in <(WebSearchKind?, String)>[
              (null, 'Kein Suchdienst'),
              for (final k in WebSearchKind.values) (k, k.label),
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
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: 'gewählt',
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
            decoration: const InputDecoration(
              labelText: 'Adresse, z. B. https://search.example.org',
            ),
          ),
        if (kind != null && kind.needsKey)
          AutofillGroup(
            child: SecretField(
              key: const ValueKey('searchKey'),
              controller: _key,
              label: 'API-Key',
              helperText: _hasKey
                  ? 'Key gespeichert – leer lassen behält ihn'
                  : null,
            ),
          ),
        if (_error != null) Text(_error!, style: WText.caption),
        PrimaryButton('Speichern', onPressed: () => unawaited(_save())),
      ],
    );
  }
}
