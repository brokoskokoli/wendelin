import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../di/attestation_providers.dart';
import '../../di/profiles.dart';
import '../../di/provider_setup.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import 'provider_setup/attestation_stages_card.dart';
import 'provider_setup/credentials_step.dart';
import 'provider_setup/finish_step.dart';
import 'provider_setup/model_step.dart';
import 'provider_setup/template_step.dart';
import 'settings_page.dart';

/// Settings → Provider: the setup dialog in steps (concept: „Einrichtung
/// (Dialog pro Provider)“): template, credentials, connection test with
/// the model list, model choice with a probe of that model, then privacy
/// level and budget. With [existing] the same dialog edits a profile.
///
/// The API key is typed into a field local to this widget and written
/// straight to the `SecretStore` when testing; it never enters app state,
/// logs or the database. Leaving without saving deletes it again.
class ProviderSetupScreen extends ConsumerStatefulWidget {
  /// Creates the dialog; [onSaved] replaces the default „pop“.
  const ProviderSetupScreen({
    super.key,
    this.existing,
    this.onSaved,
    this.showBack = true,
  });

  /// Profile to edit; `null` creates a new one.
  final ProviderProfile? existing;

  /// Called with the saved profile.
  final ValueChanged<ProviderProfile>? onSaved;

  /// Shows the back button.
  final bool showBack;

  @override
  ConsumerState<ProviderSetupScreen> createState() => _ProviderSetupState();
}

enum _Step { template, credentials, model, finish }

/// The template that fits [profile] best (same type and base URL, else the
/// generic one of its type).
ProviderTemplate templateFor(ProviderProfile profile) =>
    providerTemplates
        .where((t) => t.type == profile.type && t.baseUrl == profile.baseUrl)
        .firstOrNull ??
    providerTemplates.firstWhere(
      (t) => profile.type == ProviderType.anthropic
          ? t.type == ProviderType.anthropic
          : t.id == 'custom',
    );

class _ProviderSetupState extends ConsumerState<ProviderSetupScreen> {
  _Step _step = _Step.template;
  ProviderSetupSession? _session;
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _budget = TextEditingController();
  List<ModelInfo> _models = const [];
  SetupTestResult? _result;
  SetupTestResult? _connection;
  ProviderCapabilities? _detected;
  bool _busy = false;
  PrivacyLevel _privacy = PrivacyLevel.standard;
  double _warn = 0.8;
  String? _budgetError;

  bool get _editing => widget.existing != null;

  /// Whether the profile is a TEE provider whose answers are attested.
  bool get _attested => _session?.attested ?? false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p == null) return;
    _start(templateFor(p), existing: p);
    _name.text = p.name;
    _baseUrl.text = p.baseUrl ?? '';
    _model.text = p.defaultModel;
    _privacy = p.privacy;
    _budget.text = budgetText(p.budgetMonthly);
    _warn = p.warnThreshold ?? 0.8;
  }

  @override
  void dispose() {
    unawaited(_session?.discard());
    for (final c in [_name, _baseUrl, _key, _model, _budget]) {
      c.dispose();
    }
    super.dispose();
  }

  void _start(ProviderTemplate t, {ProviderProfile? existing}) {
    unawaited(_session?.discard());
    _session = ProviderSetupSession(
      template: t,
      profileId:
          existing?.id ??
          '${t.id}-${ref.read(idGeneratorProvider).next().substring(0, 8)}',
      secrets: ref.read(secretStoreProvider),
      create: ref.read(llmProviderFactoryProvider),
      ids: ref.read(idGeneratorProvider),
      existing: existing,
    );
    _step = _Step.credentials;
    _result = null;
  }

  void _choose(ProviderTemplate t) => setState(() {
    _start(t);
    _name.text = t.name;
    _baseUrl.text = t.baseUrl ?? '';
    _model.text = t.suggestedModel ?? '';
    _privacy = t.privacy;
  });

  /// TEE profiles need the Rust check module before the adapter is built.
  Future<void> _loadCheckModule() async {
    if (!_attested) return;
    try {
      await ref.read(attestationCryptoProvider.future);
    } on Object {
      // The factory reports the missing module with a clear message.
    }
  }

  /// Step 1: store the key, connect and load the models.
  Future<void> _connect() async {
    final session = _session!;
    setState(() => _busy = true);
    await _loadCheckModule();
    await session.storeKey(_key.text);
    _key.clear();
    final result = await session.loadModels(baseUrl: _baseUrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (!result.ok) return;
      _connection = result;
      _models = result.models;
      final ids = [for (final m in _models) m.id];
      if (ids.isNotEmpty && !ids.contains(_model.text)) {
        _model.text = ids.first;
      }
      _step = _Step.model;
    });
  }

  /// Step 2: probe the chosen model.
  Future<void> _probe() async {
    final model = _model.text.trim();
    if (model.isEmpty) return;
    setState(() => _busy = true);
    await _loadCheckModule();
    final result = await _session!.probe(baseUrl: _baseUrl.text, model: model);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (!result.ok) return;
      _detected = result.detected;
      _step = _Step.finish;
    });
  }

  Future<void> _save() async {
    final session = _session!;
    final int? budget;
    try {
      budget = parseBudgetMicros(_budget.text);
    } on FormatException catch (e) {
      setState(() => _budgetError = e.message);
      return;
    }
    final profile = session.draft(
      name: _name.text,
      baseUrl: _baseUrl.text,
      model: _model.text,
      privacy: _privacy,
      budgetMicros: budget,
      warnThreshold: _warn,
    );
    await ref.read(profilesProvider.notifier).save(profile);
    await session.commit();
    if (!mounted) return;
    if (widget.onSaved != null) {
      widget.onSaved!(profile);
    } else {
      Navigator.of(context).pop(profile);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: _editing ? 'Provider bearbeiten' : 'Provider einrichten',
    showBack: widget.showBack,
    intro: switch (_step) {
      _Step.template => 'Wähle, mit wem Wendelin sprechen soll.',
      _Step.credentials =>
        'Der Key wird nur im sicheren Speicher des Geräts abgelegt.',
      _Step.model => 'Wähle das Standardmodell.',
      _Step.finish => 'Datenschutzstufe und optional ein Monatsbudget.',
    },
    children: switch (_step) {
      _Step.template => templateStep(onChoose: _choose),
      _Step.credentials => _credentials(),
      _Step.model => _modelStep(),
      _Step.finish => _finish(),
    },
  );

  Widget? _failure(String title) {
    final r = _result;
    if (r == null || r.ok) return null;
    final card = StatusCard(
      key: const ValueKey('setupFailure'),
      status: CheckStatus.failed,
      title: title,
      detail: r.message,
    );
    if (r.stages.isEmpty) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [card, AttestationStagesCard(r.stages)],
    );
  }

  List<Widget> _credentials() => credentialsStep(
    session: _session!,
    name: _name,
    baseUrl: _baseUrl,
    apiKey: _key,
    busy: _busy,
    editing: _editing,
    failure: _failure('Verbindung fehlgeschlagen'),
    onConnect: () => unawaited(_connect()),
    onOtherTemplate: () => setState(() => _step = _Step.template),
    onOpenUrl: (url) => unawaited(_openUrl(url)),
  );

  List<Widget> _modelStep() => modelStep(
    connection: _connection,
    models: _models,
    model: _model,
    failure: _failure('Modell nicht nutzbar'),
    busy: _busy,
    onChanged: () => setState(() {}),
    onPick: (id) => setState(() => _model.text = id),
    onProbe: () => unawaited(_probe()),
  );

  List<Widget> _finish() => finishStep(
    result: _result,
    detected: _detected,
    privacy: _privacy,
    onPrivacy: (level) => setState(() => _privacy = level),
    budget: _budget,
    budgetError: _budgetError,
    warn: _warn,
    onWarn: (w) => setState(() => _warn = w),
    attested: _attested,
    onSave: () => unawaited(_save()),
  );

  Future<void> _openUrl(String url) async {
    try {
      await AndroidIntent(action: 'action_view', data: url).launch();
    } on Object catch (e) {
      if (e is! PlatformException && e is! UnsupportedError) rethrow;
      if (mounted) showHint(context, url);
    }
  }
}

/// Result of the connection test above the model list: „Verbindung
/// steht“ (circle) when the provider answered, a triangle when the setup
/// continues without a model list and the probe decides.
class ConnectionStatus extends StatelessWidget {
  /// Creates the status of [result].
  const ConnectionStatus(this.result, {super.key});

  /// Result of the connection test.
  final SetupTestResult result;

  @override
  Widget build(BuildContext context) {
    final n = result.models.length;
    return result.verified
        ? StatusCard(
            key: const ValueKey('connectionStatus'),
            status: CheckStatus.ok,
            title: 'Verbindung steht',
            detail: n == 0
                ? 'Keine Modellliste. Bitte die Modell-ID eingeben.'
                : n == 1
                ? '1 Modell gefunden'
                : '$n Modelle gefunden',
          )
        : StatusCard(
            key: const ValueKey('connectionStatus'),
            status: CheckStatus.pending,
            title: 'Modellliste nicht verfügbar',
            detail: result.message,
          );
  }
}
