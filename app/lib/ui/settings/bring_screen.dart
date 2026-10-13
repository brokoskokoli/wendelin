import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/bring.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Hint shown before the Bring! login.
const bringUnofficialHint =
    'Inoffizielle Schnittstelle: Bring! hat sie nicht für andere Apps '
    'freigegeben, sie kann jederzeit brechen. E-Mail und Passwort bleiben '
    'im sicheren Speicher des Geräts.';

/// Settings → Bring!: login (e-mail, password, hint on the unofficial
/// API), state with „Erneut versuchen“ in the error state, sign-out
/// (deletes login and tokens) and the share fallback to the Bring! app.
class BringScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BringScreen({super.key});

  @override
  ConsumerState<BringScreen> createState() => _BringScreenState();
}

class _BringScreenState extends ConsumerState<BringScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _account;
  bool _loaded = false;
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
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final secrets = ref.read(bringSecretsProvider);
    final apps = ref.read(installedAppsProvider);
    final login = await secrets.credentials();
    bool? installed;
    try {
      installed = await apps.check(BringAppFallback.androidPackage);
    } on PortException {
      installed = null;
    }
    if (!mounted) return;
    setState(() {
      _account = login?.email;
      _loaded = true;
      _appInstalled = installed;
    });
  }

  BringIntegration? get _integration =>
      bringIntegrationOf(ref.read(integrationsProvider));

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }
    final registry = ref.read(toolRegistryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await bringSignIn(
      api: ref.read(bringApiProvider),
      secrets: ref.read(bringSecretsProvider),
      integration: _integration,
      login: BringCredentials(email: email, password: password),
    );
    if (error == null) await _refresh(registry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _account = email;
        _password.clear();
      }
    });
  }

  Future<void> _signOut() async {
    final registry = ref.read(toolRegistryProvider);
    final secrets = ref.read(bringSecretsProvider);
    final integration = _integration;
    final ok = await confirm(
      context,
      title: 'Bei Bring! abmelden?',
      message: 'E-Mail, Passwort und Sitzung werden vom Gerät gelöscht.',
      yes: 'Abmelden',
    );
    if (!ok) return;
    await bringSignOut(secrets: secrets, integration: integration);
    await _refresh(registry);
    if (mounted) setState(() => _account = null);
  }

  Future<void> _retry() async {
    final integration = _integration;
    if (integration == null) return;
    setState(() => _busy = true);
    final error = await integration.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    showHint(context, error ?? 'Bring! ist wieder erreichbar.');
  }

  /// New login or none: the old error is void, the setup state changed.
  Future<void> _refresh(ToolRegistry registry) async {
    if (_info(registry) == null) return;
    registry.clearError('bring');
    await registry.refresh('bring');
  }

  static IntegrationInfo? _info(ToolRegistry registry) =>
      registry.integrations.where((i) => i.id == 'bring').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: 'Bring!',
      intro: bringUnofficialHint,
      children: [
        if (!_loaded)
          const SizedBox.shrink()
        else if (_account == null)
          ..._loginForm()
        else
          StreamBuilder<void>(
            stream: registry.changes,
            builder: (context, _) => _accountCard(registry),
          ),
        SettingsSection(
          title: 'Bring!-App',
          children: [
            SettingsRow(
              title: switch (_appInstalled) {
                true => 'Installiert',
                false => 'Nicht installiert',
                null => 'Unbekannt',
              },
              detail: BringAppFallback.note,
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _loginForm() => [
    // One group: the password manager fills e-mail and password together.
    AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WSpace.l18,
        children: [
          TextField(
            key: const ValueKey('bringEmail'),
            controller: _email,
            style: WText.body,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-Mail'),
          ),
          SecretField(
            key: const ValueKey('bringPassword'),
            controller: _password,
            label: 'Passwort',
          ),
        ],
      ),
    ),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('bringError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy ? 'Anmelden …' : 'Anmelden',
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
            SettingsRow(title: 'Angemeldet', detail: _account),
            SettingsRow(
              title: failed
                  ? 'Fehler – Schnittstelle nicht erreichbar'
                  : bringStateText(info?.status),
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
            _busy ? 'Prüfe …' : 'Erneut versuchen',
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton('Abmelden', onPressed: () => unawaited(_signOut())),
      ],
    );
  }
}

/// Text of the Bring! state when it is not failed.
String bringStateText(IntegrationStatus? status) => switch (status) {
  IntegrationStatus.active => 'Aktiv',
  IntegrationStatus.available => 'Angemeldet, Integration ausgeschaltet',
  IntegrationStatus.setupRequired => 'Login fehlt',
  IntegrationStatus.unavailable => 'Nicht verfügbar',
  IntegrationStatus.error || null => 'Unbekannt',
};
