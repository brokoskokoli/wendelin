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
import '../../di/tee_restrictions.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'provider_setup/attestation_stages_card.dart';
import 'provider_setup/credentials_step.dart';
import 'provider_setup/finish_step.dart';
import 'provider_setup/model_step.dart';
import 'provider_setup/template_step.dart';
import 'settings_page.dart';
import 'switch_topic.dart';

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

  /// GPU check of this (TEE) profile (WP82).
  GpuCheckMode _gpuMode = GpuCheckMode.off;

  /// Mode stored in the edited profile (WP159: keeps the choice visible).
  /// A hidden choice (no GPU evidence) always saves „off“: [_gpuMode] only
  /// differs from „off“ if the choice was visible, and the finish step has
  /// no way back to the model step.
  GpuCheckMode _savedGpuMode = GpuCheckMode.off;

  /// Models the probe found without GPU evidence.
  final Set<String> _noGpu = {};

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
    _privacy = effectivePrivacy(p);
    _budget.text = budgetText(p.budgetMonthly);
    _warn = p.warnThreshold ?? 0.8;
    _gpuMode = _savedGpuMode = gpuModeOf(p) ?? GpuCheckMode.off;
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
    _gpuMode = GpuCheckMode.off;
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
    final l = context.l10n;
    setState(() => _busy = true);
    await _loadCheckModule();
    await session.storeKey(_key.text);
    _key.clear();
    final result = await session.loadModels(l, baseUrl: _baseUrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (!result.ok) return;
      SecretField.finishAutofill();
      _connection = result;
      _models = result.models;
      final pick = preselectModel(
        _model.text,
        _models,
        _session!.template.recommendations,
      );
      if (pick != null) _model.text = pick;
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
      switch (result.gpuEvidence) {
        case false:
          _noGpu.add(model);
        case true:
          _noGpu.remove(model);
        case null:
      }
      _detected = result.detected;
      _step = _Step.finish;
    });
  }

  /// Saving accepts the restrictions the setup note showed (WP78).
  Future<void> _acceptRestrictions(String profileId, String model) async {
    final result = _result;
    if (!_attested || result == null) return;
    final shown = restrictionStages(stageViews(result.stages));
    await acceptRestrictions(
      ref.read(storageProvider).settings,
      profileId,
      model,
      shown,
    );
  }

  Future<void> _save() async {
    final session = _session!;
    final int? budget;
    try {
      budget = parseBudgetMicros(context.l10n, _budget.text);
    } on FormatException catch (e) {
      setState(() => _budgetError = e.message);
      return;
    }
    if (_attested && _gpuMode == GpuCheckMode.after) {
      // The warning of „Nachher“ is a system notification.
      final notifier = ref.read(attestationNotifierProvider);
      if (!await notifier.hasPermission()) await notifier.requestPermission();
      if (!mounted) return;
    }
    final profile = session.draft(
      gpuMode: _attested ? _gpuMode : null,
      name: _name.text,
      baseUrl: _baseUrl.text,
      model: _model.text,
      privacy: _privacy,
      budgetMicros: budget,
      warnThreshold: _warn,
    );
    // Another model for the active default profile: new conversation (WP78).
    final before = widget.existing;
    if (before != null &&
        before.defaultModel != profile.defaultModel &&
        before.id == ref.read(profilesProvider).value?.defaultId) {
      if (!await confirmManualModelSwitch(context, ref)) return;
      if (!mounted) return;
    }
    await ref.read(profilesProvider.notifier).save(profile);
    await _acceptRestrictions(profile.id, profile.defaultModel);
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
    title: _editing
        ? context.l10n.providerSetupEditTitle
        : context.l10n.mainSetUpProvider,
    showBack: widget.showBack,
    intro: switch (_step) {
      _Step.template => context.l10n.providerSetupIntroTemplate,
      _Step.credentials => context.l10n.providerSetupIntroCredentials,
      _Step.model => context.l10n.providerSetupIntroModel,
      _Step.finish => context.l10n.providerSetupIntroFinish,
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
    l: context.l10n,
    session: _session!,
    name: _name,
    baseUrl: _baseUrl,
    apiKey: _key,
    busy: _busy,
    editing: _editing,
    failure: _failure(context.l10n.providerSetupConnectionFailed),
    onConnect: () => unawaited(_connect()),
    onOtherTemplate: () => setState(() => _step = _Step.template),
    onOpenUrl: (url) => unawaited(_openUrl(url)),
  );

  List<Widget> _modelStep() => modelStep(
    l: context.l10n,
    connection: _connection,
    models: _models,
    recommendations: _session!.template.recommendations,
    model: _model,
    noGpuEvidence: _noGpu,
    failure: _failure(context.l10n.providerSetupModelUnusable),
    busy: _busy,
    onChanged: () => setState(() {}),
    onPick: (id) => setState(() => _model.text = id),
    onProbe: () => unawaited(_probe()),
  );

  List<Widget> _finish() => finishStep(
    l: context.l10n,
    result: _result,
    detected: _detected,
    privacy: _privacy,
    onPrivacy: (level) => setState(() => _privacy = level),
    budget: _budget,
    budgetError: _budgetError,
    warn: _warn,
    onWarn: (w) => setState(() => _warn = w),
    attested: _attested,
    gpuMode: _gpuMode,
    onGpuMode: (m) => setState(() => _gpuMode = m),
    gpuEvidence: _result?.gpuEvidence,
    savedGpuMode: _savedGpuMode,
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
            title: context.l10n.providerSetupConnected,
            detail: n == 0
                ? context.l10n.providerSetupNoModelList
                : context.l10n.providerSetupModelsFound(n),
          )
        : StatusCard(
            key: const ValueKey('connectionStatus'),
            status: CheckStatus.pending,
            title: context.l10n.providerSetupModelListUnavailable,
            detail: result.message,
          );
  }
}
