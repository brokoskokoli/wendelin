import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/providers.dart';
import '../../di/spotify.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'reconnect_text.dart';
import 'settings_page.dart';

/// Settings → Spotify: short guide for the developer app, the redirect
/// address, Client-ID field, login (Custom Tab), state with „Erneut
/// versuchen“ in the error state and sign-out (deletes Client-ID and
/// tokens).
class SpotifyScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SpotifyScreen({super.key});

  @override
  ConsumerState<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends ConsumerState<SpotifyScreen> {
  final _clientId = TextEditingController();
  bool _loaded = false;
  bool _signedIn = false;
  bool _busy = false;
  String? _error;
  bool? _appInstalled;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final secrets = ref.read(spotifySecretsProvider);
    final apps = ref.read(installedAppsProvider);
    final auth = await secrets.auth();
    bool? installed;
    try {
      installed = await apps.check(spotifyAndroidPackage);
    } on PortException {
      installed = null;
    }
    if (!mounted) return;
    setState(() {
      _signedIn = auth != null;
      _loaded = true;
      _appInstalled = installed;
    });
  }

  SpotifyIntegration? get _integration =>
      spotifyIntegrationOf(ref.read(integrationsProvider));

  Future<void> _signIn() async {
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = context.l10n.spotifyClientIdMissing);
      return;
    }
    final registry = ref.read(toolRegistryProvider);
    final login = ref.read(spotifyLoginProvider);
    final integration = _integration;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await login.signIn(id);
    if (error == null) {
      await integration?.signOut();
      await _refresh(registry);
    }
    if (!mounted) return;
    if (error == null) {
      // Commit while the field still holds the value, then clear it.
      SecretField.finishAutofill();
      _clientId.clear();
    }
    setState(() {
      _busy = false;
      _error = error == null ? null : _words(error);
      if (error == null) _signedIn = true;
    });
  }

  String _words(SpotifyLoginError e) {
    final l = context.l10n;
    return switch (e) {
      SpotifyLoginError.invalidClientId => l.spotifyErrInvalidClientId,
      SpotifyLoginError.noBrowser => l.spotifyErrNoBrowser,
      SpotifyLoginError.cancelled => l.spotifyErrCancelled,
      SpotifyLoginError.stateMismatch => l.spotifyErrStateMismatch,
      SpotifyLoginError.accessDenied => l.spotifyErrAccessDenied,
      SpotifyLoginError.denied => l.spotifyErrDenied,
      SpotifyLoginError.noCode => l.spotifyErrNoCode,
      SpotifyLoginError.rejected => l.spotifyErrRejected,
      SpotifyLoginError.unavailable => l.spotifyErrUnavailable,
      SpotifyLoginError.failed => l.spotifyErrFailed,
    };
  }

  Future<void> _signOut() async {
    final registry = ref.read(toolRegistryProvider);
    final login = ref.read(spotifyLoginProvider);
    final integration = _integration;
    final ok = await confirm(
      context,
      title: context.l10n.spotifySignOutTitle,
      message: context.l10n.spotifySignOutMessage,
      yes: context.l10n.spotifySignOut,
    );
    if (!ok) return;
    await login.signOut();
    await integration?.signOut();
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
    showHint(
      context,
      reconnectHint(context.l10n, error, context.l10n.spotifyReconnected),
    );
  }

  /// New login or none: the old error is void, the setup state changed.
  Future<void> _refresh(ToolRegistry registry) async {
    if (_info(registry) == null) return;
    registry.clearError('spotify');
    await registry.refresh('spotify');
  }

  static IntegrationInfo? _info(ToolRegistry registry) =>
      registry.integrations.where((i) => i.id == 'spotify').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: context.l10n.spotifyTitle,
      intro: context.l10n.spotifyIntro,
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
        SettingsSection(
          title: context.l10n.spotifyAppTitle,
          children: [
            SettingsRow(
              title: switch (_appInstalled) {
                true => context.l10n.bringInstalled,
                false => context.l10n.bringNotInstalled,
                null => context.l10n.bringUnknown,
              },
              detail: context.l10n.spotifyAppNote,
            ),
          ],
        ),
      ],
    );
  }

  Widget _guide() {
    final redirect = spotifyRedirect.toString();
    return SettingsSection(
      title: context.l10n.spotifyGuideTitle,
      children: [
        SettingsRow(title: context.l10n.spotifyGuideStep1),
        SettingsRow(title: context.l10n.spotifyGuideStep2(redirect)),
        SettingsRow(title: context.l10n.spotifyGuideStep3),
        SettingsRow(title: context.l10n.spotifyGuideStep4),
        WideButton(
          context.l10n.spotifyCopyRedirect,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: redirect));
            if (mounted) showHint(context, context.l10n.spotifyCopied);
          },
        ),
      ],
    );
  }

  List<Widget> _loginForm() => [
    AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: SecretField(
        key: const ValueKey('spotifyClientId'),
        controller: _clientId,
        label: context.l10n.spotifyClientIdLabel,
      ),
    ),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('spotifyError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy ? context.l10n.spotifySigningIn : context.l10n.spotifySignIn,
      onPressed: _busy ? null : () => unawaited(_signIn()),
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
                  ? context.l10n.spotifyFailed
                  : spotifyStateText(context.l10n, info?.status),
              detail: failed
                  ? integrationErrorText(
                      context.l10n,
                      'spotify',
                      info?.error,
                      info?.errorKind,
                    )
                  : null,
              trailing: CheckStatusIcon(
                failed ? CheckStatus.failed : CheckStatus.ok,
                size: WSize.statusIconSmall,
                semanticLabel: failed
                    ? context.l10n.error
                    : context.l10n.bringFine,
              ),
            ),
          ],
        ),
        if (failed)
          PrimaryButton(
            _busy ? context.l10n.spotifyRetrying : context.l10n.retry,
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton(
          context.l10n.spotifySignOut,
          onPressed: () => unawaited(_signOut()),
        ),
      ],
    );
  }
}

/// Text of the Spotify state when it is not failed.
String spotifyStateText(AppLocalizations l, IntegrationStatus? status) =>
    switch (status) {
      IntegrationStatus.active => l.spotifyStateActive,
      IntegrationStatus.available => l.spotifyStateOff,
      IntegrationStatus.setupRequired => l.spotifyStateLoginMissing,
      IntegrationStatus.unavailable => l.spotifyStateUnavailable,
      IntegrationStatus.error || null => l.spotifySignedIn,
    };
