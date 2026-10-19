import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/providers.dart';
import '../../di/todoist.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Settings → Todoist: personal API token (checked against the API before
/// it is stored, never shown again), state with „Erneut versuchen“ in the
/// error state, and disconnecting (deletes the token).
class TodoistScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TodoistScreen({super.key});

  @override
  ConsumerState<TodoistScreen> createState() => _TodoistScreenState();
}

class _TodoistScreenState extends ConsumerState<TodoistScreen> {
  final _token = TextEditingController();
  bool _connected = false;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = await ref.read(todoistSecretsProvider).token();
    if (!mounted) return;
    setState(() {
      _connected = token != null && token.isNotEmpty;
      _loaded = true;
    });
  }

  TodoistIntegration? get _integration =>
      todoistIntegrationOf(ref.read(integrationsProvider));

  Future<void> _connect() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() => _error = context.l10n.todoistNeedToken);
      return;
    }
    final registry = ref.read(toolRegistryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await todoistConnect(
      api: ref.read(todoistApiProvider),
      secrets: ref.read(todoistSecretsProvider),
      token: token,
    );
    final error = failure == null ? null : _words(failure);
    if (failure == null) await _refresh(registry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (failure == null) {
        _connected = true;
        _token.clear();
      }
    });
  }

  String _words(PortErrorKind kind) => switch (kind) {
    PortErrorKind.permissionDenied => context.l10n.todoistErrDenied,
    PortErrorKind.unavailable => context.l10n.todoistErrUnavailable,
    _ => context.l10n.todoistErrFailed,
  };

  Future<void> _disconnect() async {
    final registry = ref.read(toolRegistryProvider);
    final secrets = ref.read(todoistSecretsProvider);
    final ok = await confirm(
      context,
      title: context.l10n.todoistSignOutTitle,
      message: context.l10n.todoistSignOutBody,
      yes: context.l10n.mcpDetailSignOut,
    );
    if (!ok) return;
    await secrets.clear();
    await _refresh(registry);
    if (mounted) setState(() => _connected = false);
  }

  Future<void> _retry() async {
    final integration = _integration;
    if (integration == null) return;
    setState(() => _busy = true);
    final error = await integration.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    showHint(context, error ?? context.l10n.todoistReachable);
  }

  /// New token or none: the old error is void, the setup state changed.
  Future<void> _refresh(ToolRegistry registry) async {
    if (_info(registry) == null) return;
    registry.clearError('todoist');
    await registry.refresh('todoist');
  }

  static IntegrationInfo? _info(ToolRegistry registry) =>
      registry.integrations.where((i) => i.id == 'todoist').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: 'Todoist',
      intro: context.l10n.todoistIntro,
      children: [
        if (!_loaded)
          const SizedBox.shrink()
        else if (!_connected)
          ..._tokenForm()
        else
          StreamBuilder<void>(
            stream: registry.changes,
            builder: (context, _) => _accountCard(registry),
          ),
      ],
    );
  }

  List<Widget> _tokenForm() => [
    SecretField(
      key: const ValueKey('todoistToken'),
      controller: _token,
      label: context.l10n.todoistToken,
      autofillHints: const [],
      mono: true,
    ),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('todoistError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy ? context.l10n.todoistConnecting : context.l10n.todoistConnect,
      onPressed: _busy ? null : () => unawaited(_connect()),
    ),
  ];

  Widget _accountCard(ToolRegistry registry) {
    final info = _info(registry);
    final failed = info?.status == IntegrationStatus.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: failed
                  ? context.l10n.todoistApiError
                  : todoistStateText(context.l10n, info?.status),
              detail: failed ? info?.error : null,
              trailing: CheckStatusIcon(
                failed ? CheckStatus.failed : CheckStatus.ok,
                size: WSize.statusIconSmall,
                semanticLabel: failed
                    ? context.l10n.error
                    : context.l10n.todoistFine,
              ),
            ),
          ],
        ),
        if (failed)
          PrimaryButton(
            _busy ? context.l10n.todoistChecking : context.l10n.retry,
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton(
          context.l10n.mcpDetailSignOut,
          onPressed: () => unawaited(_disconnect()),
        ),
      ],
    );
  }
}

/// Text of the Todoist state when it is not failed.
String todoistStateText(AppLocalizations l, IntegrationStatus? status) =>
    switch (status) {
      IntegrationStatus.active => l.ruleEditorActive,
      IntegrationStatus.available => l.todoistStatusAvailable,
      IntegrationStatus.setupRequired => l.todoistStatusSetup,
      IntegrationStatus.unavailable => l.todoistStatusUnavailable,
      IntegrationStatus.error || null => l.todoistStatusUnknown,
    };
