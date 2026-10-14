import 'package:flutter/foundation.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Result of a step of the connection test in the setup dialog.
@immutable
final class SetupTestResult {
  /// Creates a result.
  SetupTestResult({
    required this.ok,
    required this.message,
    List<ModelInfo> models = const [],
    this.detected,
    bool? verified,
    List<StageResult> stages = const [],
  }) : models = List.unmodifiable(models),
       stages = List.unmodifiable(stages),
       verified = verified ?? ok;

  /// Whether the step worked.
  final bool ok;

  /// Whether the provider answered (the connection is confirmed); `false`
  /// when the setup continues without a model list and the probe decides.
  final bool verified;

  /// Secret-free text for the user.
  final String message;

  /// Models offered by the provider.
  final List<ModelInfo> models;

  /// Capabilities verified by the probe with the chosen model.
  final ProviderCapabilities? detected;

  /// Result per stage of the first attestation (TEE profiles).
  final List<StageResult> stages;
}

/// One run of the provider setup dialog (concept: „Einrichtung (Dialog pro
/// Provider)“): template → credentials → models → probe with the chosen
/// model → budget/privacy. Also used to edit an existing profile.
///
/// The API key goes straight into the [SecretStore] ([storeKey]); this
/// object only remembers *that* a key is stored. A new key of an edited
/// profile is stored under a fresh reference, so leaving without saving
/// keeps the old key working; [discard] removes the unsaved key, [commit]
/// removes the replaced one.
final class ProviderSetupSession {
  /// Starts a session for [template]: a new profile with id [profileId], or
  /// editing [existing] (same id).
  ProviderSetupSession({
    required this.template,
    required this.profileId,
    required this.secrets,
    required this.create,
    required this._ids,
    this.existing,
  }) : _existingRef = switch (existing?.authMethod) {
         ApiKeyAuth(:final secretRef) => secretRef,
         _ => null,
       };

  /// Preset.
  final ProviderTemplate template;

  /// Id of the profile being created or edited.
  final String profileId;

  /// Profile being edited, if any.
  final ProviderProfile? existing;

  /// Where the key is stored.
  final SecretStore secrets;

  /// Builds the adapter for a draft profile.
  final LlmProvider Function(ProviderProfile profile, SecretReader secrets)
  create;

  final IdGenerator _ids;
  final String? _existingRef;
  String? _newRef;
  bool _saved = false;

  /// Reference of the key the profile will use (new key, else the old one).
  String? get secretRef => _newRef ?? _existingRef;

  /// Whether a key is available (stored now or kept from [existing]).
  bool get keyStored => secretRef != null;

  /// Whether the profile is a TEE provider whose answers are attested (the
  /// first attestation then runs with the connection test).
  bool get attested => needsAttestation(
    existing ??
        ProviderProfile(
          id: profileId,
          name: template.name,
          type: template.type,
          baseUrl: template.baseUrl,
          defaultModel: '-',
          privacy: template.privacy,
          authMethod: const NoAuth(),
          options: template.options,
        ),
  );

  /// Whether the template needs a base URL from the user.
  bool get needsBaseUrl =>
      template.type == ProviderType.openaiCompatible &&
      template.baseUrl == null;

  /// Stores [key] in the [SecretStore] (blank keys are ignored).
  Future<void> storeKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    final ref =
        _newRef ??
        (_existingRef == null
            ? 'provider.$profileId.apiKey'
            : 'provider.$profileId.apiKey.${_ids.next()}');
    await secrets.write(ref, trimmed);
    _newRef = ref;
  }

  /// The profile as configured so far.
  ProviderProfile draft({
    String? name,
    String? baseUrl,
    String? model,
    PrivacyLevel? privacy,
    int? budgetMicros,
    double? warnThreshold,
    bool? attestationFallback,
  }) {
    final base = template.toProfile(
      id: profileId,
      name: name == null || name.trim().isEmpty ? null : name.trim(),
      secretRef: secretRef,
      // Listing models needs no model; the probe uses the chosen one.
      model: model == null || model.trim().isEmpty
          ? (template.suggestedModel ?? '-')
          : model.trim(),
      baseUrl: baseUrl == null || baseUrl.trim().isEmpty
          ? null
          : baseUrl.trim(),
    );
    return ProviderProfile(
      id: base.id,
      name: base.name,
      type: base.type,
      baseUrl: base.baseUrl,
      defaultModel: base.defaultModel,
      privacy: privacy ?? base.privacy,
      authMethod: base.authMethod,
      budgetMonthly: budgetMicros,
      warnThreshold: budgetMicros == null ? null : warnThreshold,
      extraHeaders: existing?.extraHeaders ?? const {},
      options: {
        ...existing?.options ?? base.options,
        'attestationFallback': ?attestationFallback,
      },
    );
  }

  /// Step 1: connects with the stored key and loads the models (no model
  /// is needed yet). Only a rejected key ([AuthException]) fails; any other
  /// problem with the model list continues with an empty list, and the user
  /// types the model id (the probe then decides). Never throws.
  Future<SetupTestResult> loadModels({String? baseUrl}) async {
    final LlmProvider provider;
    try {
      provider = create(draft(baseUrl: baseUrl), secrets.read);
    } on ArgumentError catch (e) {
      return SetupTestResult(ok: false, message: '${e.message}');
    }
    try {
      final models = await provider.listModels();
      return SetupTestResult(
        ok: true,
        message: models.isEmpty
            ? 'Verbindung steht. Bitte die Modell-ID eingeben.'
            : 'Verbindung steht, ${models.length} Modelle gefunden.',
        models: models,
      );
    } on AuthException catch (e) {
      return SetupTestResult(ok: false, message: e.message);
    } on ProviderException catch (e) {
      // Many servers have no (working) model list; the probe of the typed
      // model decides whether the connection works.
      return SetupTestResult(
        ok: true,
        verified: false,
        message:
            'Modellliste nicht verfügbar (${e.message}). Bitte die '
            'Modell-ID eingeben.',
      );
    }
  }

  /// Step 2: probes [model] (connection, tool call) and reports the
  /// verified capabilities. Never throws.
  Future<SetupTestResult> probe({
    String? baseUrl,
    required String model,
  }) async {
    final LlmProvider provider;
    try {
      provider = create(draft(baseUrl: baseUrl, model: model), secrets.read);
    } on ArgumentError catch (e) {
      return SetupTestResult(ok: false, message: '${e.message}');
    }
    final health = await provider.test();
    return SetupTestResult(
      ok: health.ok,
      message: health.message,
      models: health.models ?? const [],
      detected: health.detected,
      // The probe attested a TEE profile first: show the result per stage.
      stages: provider is AttestedProvider
          ? provider.lastSessionStages
          : const [],
    );
  }

  /// The profile was saved: a replaced key is deleted.
  Future<void> commit() async {
    _saved = true;
    final old = _existingRef;
    if (_newRef != null && old != null && old != _newRef) {
      await secrets.delete(old);
    }
  }

  /// Removes a key stored in this session if the profile was not saved.
  Future<void> discard() async {
    final ref = _newRef;
    if (ref != null && !_saved) await secrets.delete(ref);
  }
}

/// Parses a monthly budget in dollars („5“, „2,50“) into micro-USD;
/// `null` for blank input, [FormatException] for anything else.
int? parseBudgetMicros(String text) {
  final t = text.trim().replaceAll(',', '.').replaceAll(r'$', '').trim();
  if (t.isEmpty) return null;
  final value = double.tryParse(t);
  if (value == null || value < 0) {
    throw const FormatException('Budget: Betrag in Dollar, z. B. 5 oder 2,50');
  }
  return (value * 1000000).round();
}

/// Text field value of a budget in micro-USD („2,50“).
String budgetText(int? micros) {
  if (micros == null) return '';
  final cents = (micros / 10000).round();
  final rest = cents % 100;
  return rest == 0
      ? '${cents ~/ 100}'
      : '${cents ~/ 100},${'$rest'.padLeft(2, '0')}';
}
