import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/providers.dart';
import '../../di/spotify.dart';
import '../design/design.dart';
import 'settings_page.dart';
import 'spotify_texts.dart';

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
      setState(() => _error = SpotifyTexts.clientIdMissing);
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
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _signedIn = true;
        _clientId.clear();
      }
    });
  }

  Future<void> _signOut() async {
    final registry = ref.read(toolRegistryProvider);
    final login = ref.read(spotifyLoginProvider);
    final integration = _integration;
    final ok = await confirm(
      context,
      title: SpotifyTexts.signOutTitle,
      message: SpotifyTexts.signOutMessage,
      yes: SpotifyTexts.signOut,
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
    showHint(context, error ?? SpotifyTexts.reconnected);
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
      title: SpotifyTexts.title,
      intro: SpotifyTexts.intro,
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
          title: SpotifyTexts.appTitle,
          children: [
            SettingsRow(
              title: switch (_appInstalled) {
                true => 'Installiert',
                false => 'Nicht installiert',
                null => 'Unbekannt',
              },
              detail: SpotifyTexts.appNote,
            ),
          ],
        ),
      ],
    );
  }

  Widget _guide() {
    final redirect = spotifyRedirect.toString();
    return SettingsSection(
      title: SpotifyTexts.guideTitle,
      children: [
        for (final step in SpotifyTexts.guideSteps)
          SettingsRow(title: step.replaceAll('{redirect}', redirect)),
        WideButton(
          SpotifyTexts.copyRedirect,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: redirect));
            if (mounted) showHint(context, SpotifyTexts.copied);
          },
        ),
      ],
    );
  }

  List<Widget> _loginForm() => [
    TextField(
      key: const ValueKey('spotifyClientId'),
      controller: _clientId,
      style: WText.body,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(labelText: SpotifyTexts.clientIdLabel),
    ),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('spotifyError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy ? SpotifyTexts.signingIn : SpotifyTexts.signIn,
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
                  ? SpotifyTexts.failed
                  : spotifyStateText(info?.status),
              detail: failed ? info?.error : null,
              trailing: CheckStatusIcon(
                failed ? CheckStatus.failed : CheckStatus.ok,
                size: WSize.statusIconSmall,
                semanticLabel: failed ? 'Fehler' : 'in Ordnung',
              ),
            ),
          ],
        ),
        if (failed)
          PrimaryButton(
            _busy ? SpotifyTexts.retrying : SpotifyTexts.retry,
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton(
          SpotifyTexts.signOut,
          onPressed: () => unawaited(_signOut()),
        ),
      ],
    );
  }
}

/// Text of the Spotify state when it is not failed.
String spotifyStateText(IntegrationStatus? status) => switch (status) {
  IntegrationStatus.active => 'Angemeldet · Aktiv',
  IntegrationStatus.available => 'Angemeldet, Integration ausgeschaltet',
  IntegrationStatus.setupRequired => 'Login fehlt',
  IntegrationStatus.unavailable => 'Nicht verfügbar',
  IntegrationStatus.error || null => SpotifyTexts.signedIn,
};
