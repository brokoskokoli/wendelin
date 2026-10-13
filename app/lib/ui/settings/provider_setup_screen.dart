import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../di/profiles.dart';
import '../../di/provider_setup.dart';
import '../../di/providers.dart';
import '../design/design.dart';
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
  ProviderCapabilities? _detected;
  bool _busy = false;
  PrivacyLevel _privacy = PrivacyLevel.standard;
  double _warn = 0.8;
  String? _budgetError;

  bool get _editing => widget.existing != null;

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

  /// Step 1: store the key, connect and load the models.
  Future<void> _connect() async {
    final session = _session!;
    setState(() => _busy = true);
    await session.storeKey(_key.text);
    _key.clear();
    final result = await session.loadModels(baseUrl: _baseUrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (!result.ok) return;
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
      _Step.model => 'Verbindung steht. Wähle das Standardmodell.',
      _Step.finish => 'Datenschutzstufe und optional ein Monatsbudget.',
    },
    children: switch (_step) {
      _Step.template => _templates(),
      _Step.credentials => _credentials(),
      _Step.model => _modelStep(),
      _Step.finish => _finish(),
    },
  );

  Widget? _failure() {
    final r = _result;
    return r != null && !r.ok ? _Status(ok: false, text: r.message) : null;
  }

  List<Widget> _templates() => [
    SectionCard(
      children: [
        for (final t in providerTemplates)
          SettingsRow(
            title: t.name,
            trailing: PrivacyChip(t.privacy),
            onTap: () => _choose(t),
          ),
      ],
    ),
  ];

  List<Widget> _credentials() {
    final session = _session!;
    final t = session.template;
    return [
      TextField(
        controller: _name,
        style: WText.body,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      if (t.type == ProviderType.openaiCompatible)
        TextField(
          controller: _baseUrl,
          style: WText.body,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Base-URL'),
        ),
      if (t.auth != TemplateAuth.none) ...[
        TextField(
          key: const ValueKey('apiKey'),
          controller: _key,
          style: WText.body,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: t.auth == TemplateAuth.apiKey
                ? 'API-Key'
                : 'API-Key (optional)',
            helperText: session.keyStored
                ? 'Key gespeichert – leer lassen behält ihn'
                : null,
          ),
        ),
        if (t.keyPageUrl case final url?)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => unawaited(_openUrl(url)),
              child: const Text('Key beim Anbieter erstellen'),
            ),
          ),
      ],
      ?_failure(),
      PrimaryButton(
        _busy ? 'Teste …' : 'Verbindung testen',
        onPressed: _busy ? null : () => unawaited(_connect()),
      ),
      if (!_editing)
        WideButton(
          'Andere Vorlage',
          onPressed: () => setState(() => _step = _Step.template),
        ),
    ];
  }

  List<Widget> _modelStep() => [
    if (_models.isNotEmpty)
      SettingsSection(
        title: 'Modelle',
        children: [
          for (final m in _models.take(50))
            SettingsRow(
              title: m.displayName,
              mono: true,
              onTap: () => setState(() => _model.text = m.id),
              trailing: _model.text == m.id
                  ? const CheckStatusIcon(
                      CheckStatus.ok,
                      semanticLabel: 'gewählt',
                    )
                  : null,
            ),
        ],
      ),
    TextField(
      controller: _model,
      style: WText.body,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Modell-ID'),
    ),
    ?_failure(),
    PrimaryButton(
      _busy ? 'Prüfe …' : 'Modell prüfen',
      onPressed: _busy || _model.text.trim().isEmpty
          ? null
          : () => unawaited(_probe()),
    ),
  ];

  List<Widget> _finish() {
    final detected = _detected;
    return [
      _Status(ok: true, text: _result?.message ?? ''),
      if (detected != null)
        Text(
          [
            detected.tools ? '✓ Tools' : '✕ Tools',
            detected.vision ? '✓ Bilder' : '✕ Bilder',
            if (detected.tee) '✓ TEE',
          ].join(' · '),
          style: WText.mono,
        ),
      SettingsSection(
        title: 'Datenschutzstufe',
        children: [
          for (final level in PrivacyLevel.values)
            SettingsRow(
              title: level.label,
              trailing: _privacy == level
                  ? const CheckStatusIcon(
                      CheckStatus.ok,
                      semanticLabel: 'gewählt',
                    )
                  : PrivacyChip(level),
              onTap: () => setState(() => _privacy = level),
            ),
        ],
      ),
      TextField(
        controller: _budget,
        style: WText.body,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: r'Budget pro Monat in $ (optional)',
          errorText: _budgetError,
        ),
      ),
      SettingsSection(
        title: 'Warnen ab',
        children: [
          for (final w in const [0.5, 0.8, 0.9])
            SettingsRow(
              title: '${(w * 100).round()} % des Budgets',
              onTap: () => setState(() => _warn = w),
              trailing: _warn == w
                  ? const CheckStatusIcon(
                      CheckStatus.ok,
                      semanticLabel: 'gewählt',
                    )
                  : null,
            ),
        ],
      ),
      PrimaryButton('Speichern', onPressed: () => unawaited(_save())),
    ];
  }

  Future<void> _openUrl(String url) async {
    try {
      await AndroidIntent(action: 'action_view', data: url).launch();
    } on Object catch (e) {
      if (e is! PlatformException && e is! UnsupportedError) rethrow;
      if (mounted) showHint(context, url);
    }
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    spacing: WSpace.s,
    children: [
      CheckStatusIcon(ok ? CheckStatus.ok : CheckStatus.failed),
      Expanded(child: Text(text, style: WText.detail)),
    ],
  );
}
