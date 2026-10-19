import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/google_tasks.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'reconnect_text.dart';
import 'settings_page.dart';

/// Settings → Google Tasks: short guide for the user's own Cloud project,
/// client ID and secret (never shown again), login in the browser, state with
/// „Erneut versuchen“ in the error state and sign-out (revokes and deletes
/// everything).
class GoogleTasksScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const GoogleTasksScreen({super.key});

  @override
  ConsumerState<GoogleTasksScreen> createState() => _GoogleTasksScreenState();
}

class _GoogleTasksScreenState extends ConsumerState<GoogleTasksScreen> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  bool _loaded = false;
  bool _signedIn = false;
  bool _busy = false;
  String? _error;
  late final GoogleTasksLogin _login;

  @override
  void initState() {
    super.initState();
    _login = ref.read(googleTasksLoginProvider);
    unawaited(_load());
  }

  @override
  void dispose() {
    // Leaving the screen ends a running login and closes its local server.
    unawaited(_login.cancel());
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = await ref.read(googleTasksSecretsProvider).refreshToken();
    if (!mounted) return;
    setState(() {
      _signedIn = token != null && token.isNotEmpty;
      _loaded = true;
    });
  }

  GoogleTasksIntegration? get _integration =>
      googleTasksIntegrationOf(ref.read(integrationsProvider));

  Future<void> _signIn() async {
    final id = _clientId.text.trim();
    final secret = _clientSecret.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      setState(() => _error = context.l10n.googleTasksNeedClient);
      return;
    }
    final registry = ref.read(toolRegistryProvider);
    final integration = _integration;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await _login.signIn(id, secret);
    if (failure == null) {
      integration?.session.reset();
      await _refresh(registry);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure == null ? null : _words(failure);
      if (failure == null) {
        _signedIn = true;
        _clientId.clear();
        _clientSecret.clear();
      }
    });
  }

  String _words(GoogleLoginError e) {
    final l = context.l10n;
    return switch (e) {
      GoogleLoginError.invalidClientId => l.googleTasksErrInvalidClientId,
      GoogleLoginError.missingSecret => l.googleTasksErrMissingSecret,
      GoogleLoginError.noBrowser => l.googleTasksErrNoBrowser,
      GoogleLoginError.timeout => l.googleTasksErrTimeout,
      GoogleLoginError.cancelled => l.googleTasksErrCancelled,
      GoogleLoginError.accessDenied => l.googleTasksErrAccessDenied,
      GoogleLoginError.denied => l.googleTasksErrDenied,
      GoogleLoginError.noCode => l.googleTasksErrNoCode,
      GoogleLoginError.receiverUnavailable => l.googleTasksErrReceiver,
      GoogleLoginError.clientRejected => l.googleTasksErrClientRejected,
      GoogleLoginError.noRefreshToken => l.googleTasksErrNoRefreshToken,
      GoogleLoginError.unavailable => l.googleTasksErrUnavailable,
      GoogleLoginError.failed => l.googleTasksErrFailed,
    };
  }

  Future<void> _signOut() async {
    final registry = ref.read(toolRegistryProvider);
    final login = ref.read(googleTasksLoginProvider);
    final integration = _integration;
    final ok = await confirm(
      context,
      title: context.l10n.googleTasksSignOutTitle,
      message: context.l10n.googleTasksSignOutBody,
      yes: context.l10n.mcpDetailSignOut,
    );
    if (!ok) return;
    await login.signOut();
    integration?.session.reset();
    await _refresh(registry);
    if (mounted) setState(() => _signedIn = false);
  }

  Future<void> _retry() async {
    final integration = _integration;
    if (integration == null) return;
    setState(() => _busy = true);
    final error = await integration.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    // The refresh token is gone after a rejected renewal: back to the form.
    final token = await ref.read(googleTasksSecretsProvider).refreshToken();
    if (!mounted) return;
    setState(() => _signedIn = token != null && token.isNotEmpty);
    showHint(
      context,
      reconnectHint(context.l10n, error, context.l10n.googleTasksReachable),
    );
  }

  /// New login or none: the old error is void, the setup state changed.
  Future<void> _refresh(ToolRegistry registry) async {
    if (_info(registry) == null) return;
    registry.clearError('gtasks');
    await registry.refresh('gtasks');
  }

  static IntegrationInfo? _info(ToolRegistry registry) =>
      registry.integrations.where((i) => i.id == 'gtasks').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: 'Google Tasks',
      intro: context.l10n.googleTasksIntro,
      children: [
        if (!_loaded)
          const SizedBox.shrink()
        else if (!_signedIn) ...[
          _guide(),
          ..._loginForm(),
        ] else
          StreamBuilder<void>(
            stream: registry.changes,
            builder: (context, _) => _accountCard(registry),
          ),
      ],
    );
  }

  Widget _guide() => SettingsSection(
    title: context.l10n.googleTasksGuideTitle,
    children: [
      SettingsRow(title: context.l10n.googleTasksGuideStep1),
      SettingsRow(title: context.l10n.googleTasksGuideStep2),
      SettingsRow(title: context.l10n.googleTasksGuideStep3),
      SettingsRow(title: context.l10n.googleTasksGuideStep4),
      SettingsRow(title: context.l10n.googleTasksGuideNote),
    ],
  );

  List<Widget> _loginForm() => [
    TextField(
      key: const ValueKey('googleTasksClientId'),
      controller: _clientId,
      style: WText.body,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: context.l10n.googleTasksClientId),
    ),
    SecretField(
      key: const ValueKey('googleTasksClientSecret'),
      controller: _clientSecret,
      label: context.l10n.googleTasksClientSecret,
      autofillHints: const [],
      mono: true,
    ),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('googleTasksError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy
          ? context.l10n.googleTasksSignInWaiting
          : context.l10n.googleTasksSignIn,
      onPressed: _busy ? null : () => unawaited(_signIn()),
    ),
    if (_busy)
      WideButton(
        context.l10n.googleTasksCancel,
        onPressed: () => unawaited(ref.read(googleTasksLoginProvider).cancel()),
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
                  ? context.l10n.googleTasksApiError
                  : googleTasksStateText(context.l10n, info?.status),
              detail: failed
                  ? integrationErrorText(context.l10n, 'gtasks', info?.error)
                  : null,
              trailing: CheckStatusIcon(
                failed ? CheckStatus.failed : CheckStatus.ok,
                size: WSize.statusIconSmall,
                semanticLabel: failed
                    ? context.l10n.error
                    : context.l10n.googleTasksFine,
              ),
            ),
          ],
        ),
        if (failed)
          PrimaryButton(
            _busy ? context.l10n.googleTasksChecking : context.l10n.retry,
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton(
          context.l10n.mcpDetailSignOut,
          onPressed: () => unawaited(_signOut()),
        ),
      ],
    );
  }
}

/// Text of the Google Tasks state when it is not failed.
String googleTasksStateText(AppLocalizations l, IntegrationStatus? status) =>
    switch (status) {
      IntegrationStatus.active => l.ruleEditorActive,
      IntegrationStatus.available => l.googleTasksStatusAvailable,
      IntegrationStatus.setupRequired => l.googleTasksStatusSetup,
      IntegrationStatus.unavailable => l.googleTasksStatusUnavailable,
      IntegrationStatus.error || null => l.googleTasksStatusUnknown,
    };
