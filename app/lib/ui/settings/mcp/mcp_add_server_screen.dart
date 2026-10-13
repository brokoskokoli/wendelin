import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/mcp/mcp_source.dart';
import '../../../di/mcp/mcp_templates.dart';
import '../../../di/providers.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'mcp_labels.dart';
import 'mcp_server_detail_screen.dart';

/// „+ Server“: first a template (Home Assistant, Obsidian, CalDAV, own
/// server), then name, address and login. „Prüfen“ probes the server
/// before it is saved; plain `http` is only allowed into the home network.
/// Secrets go straight into the `SecretStore` and are never shown again.
class McpAddServerScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const McpAddServerScreen({super.key});

  @override
  ConsumerState<McpAddServerScreen> createState() => _AddState();
}

class _AddState extends ConsumerState<McpAddServerScreen> {
  McpTemplate? _template;
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _headerName = TextEditingController();
  final _headerValue = TextEditingController();
  final _clientId = TextEditingController();
  McpAuthKind _auth = McpAuthKind.none;
  bool _confirmAll = false;
  bool _sensitive = false;
  bool _busy = false;
  String? _probe;
  bool _probeOk = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _url,
      _token,
      _headerName,
      _headerValue,
      _clientId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(McpTemplate template) => setState(() {
    _template = template;
    _name.text = template.name;
    _url.text = template.urlPattern;
    _auth = template.auth;
    _probe = null;
    _error = null;
  });

  /// The draft, or `null` with [_error] set.
  McpDraft? _draft() {
    final name = _name.text.trim();
    final text = _url.text.trim();
    final url = Uri.tryParse(text);
    String? error;
    if (name.isEmpty) {
      error = 'Bitte einen Namen angeben.';
    } else if (McpTemplate.hasPlaceholder(text)) {
      error = 'Bitte die Platzhalter in <…> in der Adresse ersetzen.';
    } else if (url == null || !url.hasScheme || url.host.isEmpty) {
      error = 'Bitte eine vollständige Adresse angeben (https://…).';
    } else {
      try {
        checkServerUrl(url);
      } on McpException catch (e) {
        error = e.message;
      }
    }
    if (error == null &&
        _auth == McpAuthKind.headers &&
        _headerName.text.trim().isEmpty) {
      error = 'Bitte den Namen des Headers angeben.';
    }
    setState(() => _error = error);
    if (error != null) return null;
    return McpDraft(
      name: name,
      url: url!,
      auth: _auth,
      token: _token.text,
      headers: [
        if (_auth == McpAuthKind.headers)
          (_headerName.text.trim(), _headerValue.text),
      ],
      clientId: _clientId.text,
      confirmAll: _confirmAll,
      sensitive: _sensitive,
    );
  }

  Future<void> _check() async {
    final draft = _draft();
    if (draft == null) return;
    final source = ref.read(mcpServerSourceProvider);
    setState(() => _busy = true);
    final probe = await source.probeDraft(draft);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _probeOk = probe.status == McpReachability.reachable;
      _probe = mcpProbeText(probe, oauth: _auth == McpAuthKind.oauth);
    });
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;
    final source = ref.read(mcpServerSourceProvider);
    final sync = ref.read(userIntegrationSyncProvider);
    final activator = ref.read(integrationActivatorProvider);
    setState(() => _busy = true);
    final McpServerView server;
    try {
      server = await source.add(draft);
    } on McpException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    _token.clear();
    _headerValue.clear();
    // Set up explicitly by the user: switch it on (connects the server).
    await sync.settled();
    await activator.setEnabled(server.integrationId, enabled: true);
    if (!mounted) return;
    if (draft.auth == McpAuthKind.oauth) {
      await signInMcp(context, ref, server);
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => McpServerDetailScreen(server.config.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;
    if (template == null) {
      return SettingsPage(
        title: 'Server hinzufügen',
        intro:
            'Wähle eine Vorlage oder trage einen eigenen Server ein. '
            'Erreichbar über https oder im Heimnetz (Tailscale, WireGuard).',
        children: [
          SectionCard(
            children: [
              for (final t in McpTemplate.all)
                SettingsRow(
                  title: t == McpTemplate.custom ? 'Eigener Server' : t.name,
                  detail: t.description,
                  onTap: () => _choose(t),
                ),
            ],
          ),
        ],
      );
    }
    final url = Uri.tryParse(_url.text.trim());
    final plain =
        url != null && url.isScheme('http') && isHomeNetworkHost(url.host);
    return SettingsPage(
      title: template == McpTemplate.custom ? 'Eigener Server' : template.name,
      intro: template.description,
      children: [
        TextField(
          key: const ValueKey('mcpName'),
          controller: _name,
          style: WText.body,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          key: const ValueKey('mcpUrl'),
          controller: _url,
          style: WText.body,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() => _probe = null),
          decoration: InputDecoration(
            labelText: 'Adresse',
            helperText: plain
                ? 'Unverschlüsselt (http): nur im Heimnetz oder über '
                      'Tailscale erlaubt'
                : null,
            helperMaxLines: 2,
          ),
        ),
        SettingsSection(
          title: 'Anmeldung',
          children: [
            for (final kind in McpAuthKind.values)
              SettingsRow(
                title: kind.label,
                onTap: () => setState(() {
                  _auth = kind;
                  _probe = null;
                }),
                trailing: _auth == kind
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: 'gewählt',
                      )
                    : null,
              ),
          ],
        ),
        ..._authFields(template),
        SectionCard(
          children: [
            SettingsRow(
              title: 'Alle Tools bestätigen',
              detail: 'Jeder Aufruf fragt nach',
              trailing: WSwitch(
                value: _confirmAll,
                semanticLabel: 'Alle Tools bestätigen',
                onChanged: (on) => setState(() => _confirmAll = on),
              ),
            ),
            SettingsRow(
              title: 'Sensibel',
              detail: 'Tools nur an Provider ab der eingestellten Stufe',
              trailing: WSwitch(
                value: _sensitive,
                semanticLabel: 'Sensibel',
                onChanged: (on) => setState(() => _sensitive = on),
              ),
            ),
          ],
        ),
        if (_error != null) Text(_error!, style: WText.caption),
        if (_probe != null)
          Row(
            spacing: WSpace.s,
            children: [
              CheckStatusIcon(
                _probeOk ? CheckStatus.ok : CheckStatus.failed,
                semanticLabel: _probeOk ? 'erreichbar' : 'Problem',
              ),
              Expanded(child: Text(_probe!, style: WText.detail)),
            ],
          ),
        WideButton(
          'Verbindung prüfen',
          onPressed: _busy ? null : () => unawaited(_check()),
        ),
        PrimaryButton(
          'Speichern',
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }

  List<Widget> _authFields(McpTemplate template) => switch (_auth) {
    McpAuthKind.none => const [],
    McpAuthKind.bearer => [
      TextField(
        key: const ValueKey('mcpToken'),
        controller: _token,
        style: WText.body,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Token',
          helperText: template.authHint ?? 'Wird nie wieder angezeigt',
          helperMaxLines: 2,
        ),
      ),
    ],
    McpAuthKind.headers => [
      TextField(
        key: const ValueKey('mcpHeaderName'),
        controller: _headerName,
        style: WText.body,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Header, z. B. X-Api-Key'),
      ),
      TextField(
        key: const ValueKey('mcpHeaderValue'),
        controller: _headerValue,
        style: WText.body,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Wert',
          helperText: 'Wird nie wieder angezeigt',
        ),
      ),
    ],
    McpAuthKind.oauth => [
      TextField(
        key: const ValueKey('mcpClientId'),
        controller: _clientId,
        style: WText.body,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Client-ID (optional)',
          helperText:
              'Leer lassen: Wendelin registriert sich selbst beim Server',
          helperMaxLines: 2,
        ),
      ),
    ],
  };
}
