import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'mcp_add_check.dart';
import 'mcp_add_parts.dart';
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
    final error = mcpAddError(
      context.l10n,
      name: name,
      urlText: text,
      auth: _auth,
      headerName: _headerName.text,
    );
    setState(() => _error = error);
    if (error != null) return null;
    return McpDraft(
      name: name,
      url: Uri.parse(text),
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
      _probe = mcpProbeText(
        context.l10n,
        probe,
        oauth: _auth == McpAuthKind.oauth,
      );
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
    // Commit while the fields still hold the values, then clear them.
    SecretField.finishAutofill();
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
        title: context.l10n.mcpAddServerTitle,
        intro: context.l10n.mcpAddServerIntro,
        children: [McpTemplateList(onChoose: _choose)],
      );
    }
    final url = Uri.tryParse(_url.text.trim());
    final plain =
        url != null && url.isScheme('http') && isHomeNetworkHost(url.host);
    return SettingsPage(
      title: template == McpTemplate.custom
          ? context.l10n.mcpAddCustom
          : template.name,
      intro: template.description,
      children: [
        TextField(
          key: const ValueKey('mcpName'),
          controller: _name,
          style: WText.body,
          decoration: InputDecoration(labelText: context.l10n.name),
        ),
        TextField(
          key: const ValueKey('mcpUrl'),
          controller: _url,
          style: WText.body,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() => _probe = null),
          decoration: InputDecoration(
            labelText: context.l10n.mcpAddServerAddress,
            helperText: plain ? context.l10n.mcpAddServerInsecure : null,
            helperMaxLines: 2,
          ),
        ),
        McpAuthChoice(
          auth: _auth,
          onPick: (kind) => setState(() {
            _auth = kind;
            _probe = null;
          }),
        ),
        ...mcpAuthFields(
          l: context.l10n,
          auth: _auth,
          template: template,
          token: _token,
          headerName: _headerName,
          headerValue: _headerValue,
          clientId: _clientId,
        ),
        McpAddOptions(
          confirmAll: _confirmAll,
          sensitive: _sensitive,
          onConfirmAll: (on) => setState(() => _confirmAll = on),
          onSensitive: (on) => setState(() => _sensitive = on),
        ),
        if (_error != null) Text(_error!, style: WText.caption),
        if (_probe != null) McpProbeRow(text: _probe!, ok: _probeOk),
        WideButton(
          context.l10n.mcpAddServerTestConnection,
          onPressed: _busy ? null : () => unawaited(_check()),
        ),
        PrimaryButton(
          context.l10n.save,
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
