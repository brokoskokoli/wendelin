import 'dart:convert';

import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// A provider profile for an eval run, read from a JSON file.
///
/// The file is a `ProviderProfile` JSON (as in the app) plus optional
/// eval keys:
/// - `catalog`: price overrides in the `ModelCatalog.mergeJson` format
///   (`{"models": {"<id>": {"input": 0.1, "output": 0.4}}}`),
/// - `escalationModels`: no longer used (Wendelin does not switch models
///   on its own, K28); the key is accepted and ignored,
/// - `modelOptions`: provider options per model id (e.g. `reasoningEffort`,
///   `extraBody` with `chat_template_kwargs` to switch thinking off); merged
///   over `options` for the model in use, `extraBody` key by key, so one
///   profile can run several models that need different request fields,
/// - `script`: for `type: fake` the path of the fake script (relative to
///   the profile file).
///
/// It never contains a key: the API key comes from an environment variable
/// (see [apiKeyVariable]).
final class EvalProfile {
  EvalProfile._(
    this.profile,
    this.catalog,
    this.script, [
    this._base,
    this._modelOptions = const {},
  ]);

  /// Parses [json]; throws [FormatException].
  factory EvalProfile.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('Profil ist kein gültiges JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Profil: JSON-Objekt erwartet');
    }
    _rejectSecrets(decoded);
    final options = decoded['options'];
    if (options is Map<String, Object?> &&
        options['enableServerWebSearch'] == true) {
      throw const FormatException(
        'enableServerWebSearch ist für Evals nicht erlaubt: die Gebühren je '
        'Suche erfasst der CostCalculator nicht, und die Fälle prüfen '
        'web__search',
      );
    }
    final map = Map.of(decoded);
    final catalogJson = map.remove('catalog');
    map.remove('escalationModels');
    final script = map.remove('script');
    if (script != null && script is! String) {
      throw const FormatException('script: Pfad erwartet');
    }
    final modelOptions = _modelOptionsOf(map.remove('modelOptions'));
    var catalog = ModelCatalog.builtIn();
    if (catalogJson != null) {
      catalog = catalog.mergeJson(jsonEncode(catalogJson));
    }
    final base = ProviderProfile.fromJson(map);
    return EvalProfile._(
      _withModelOptions(base, base.defaultModel, modelOptions),
      catalog,
      script as String?,
      base,
      modelOptions,
    );
  }

  static Map<String, Map<String, Object?>> _modelOptionsOf(Object? v) {
    if (v == null) return const {};
    if (v is! Map<String, Object?>) {
      throw const FormatException('modelOptions: Objekt je Modell erwartet');
    }
    return {
      for (final e in v.entries)
        e.key: switch (e.value) {
          final Map<String, Object?> m => m,
          _ => throw FormatException('modelOptions.${e.key}: Objekt erwartet'),
        },
    };
  }

  /// [base] with the options of [model] merged over `options`
  /// (`extraBody` merged key by key).
  static ProviderProfile _withModelOptions(
    ProviderProfile base,
    String model,
    Map<String, Map<String, Object?>> modelOptions,
  ) {
    final own = modelOptions[model];
    if (own == null) return base.copyWith(defaultModel: model);
    final baseBody = base.options['extraBody'];
    final ownBody = own['extraBody'];
    return base.copyWith(
      defaultModel: model,
      options: {
        ...base.options,
        ...own,
        if (baseBody is Map<String, Object?> || ownBody is Map<String, Object?>)
          'extraBody': {
            if (baseBody is Map<String, Object?>) ...baseBody,
            if (ownBody is Map<String, Object?>) ...ownBody,
          },
      },
    );
  }

  /// The provider profile.
  final ProviderProfile profile;

  /// Prices (built-in plus overrides).
  final ModelCatalog catalog;

  /// Fake script path (only for `type: fake`).
  final String? script;

  /// Environment variable holding the API key, or `null` if the profile
  /// needs none (fake, no auth).
  ///
  /// An `apiKey` auth whose `secretRef` looks like an environment variable
  /// name (`ANTHROPIC_API_KEY`) names it directly; otherwise the type
  /// decides: Anthropic → `ANTHROPIC_API_KEY`, Phala/RedPill →
  /// `PHALA_API_KEY`, other OpenAI-compatible → `OPENAI_API_KEY`.
  String? get apiKeyVariable {
    final auth = profile.authMethod;
    if (profile.type == ProviderType.fake || auth is NoAuth) return null;
    if (auth is ApiKeyAuth && _envName.hasMatch(auth.secretRef)) {
      return auth.secretRef;
    }
    if (profile.type == ProviderType.anthropic) return 'ANTHROPIC_API_KEY';
    final host = Uri.tryParse(profile.baseUrl ?? '')?.host ?? '';
    if (host.contains('redpill') || host.contains('phala')) {
      return 'PHALA_API_KEY';
    }
    return 'OPENAI_API_KEY';
  }

  /// The profile with [model] as default model.
  EvalProfile withModel(String model) => EvalProfile._(
    _withModelOptions(_base ?? profile, model, _modelOptions),
    catalog,
    script,
    _base,
    _modelOptions,
  );

  final ProviderProfile? _base;
  final Map<String, Map<String, Object?>> _modelOptions;

  /// Cost estimator from [catalog].
  CostEstimator get costEstimator =>
      CatalogCostEstimator(CostCalculator(catalog));

  static final _envName = RegExp(r'^[A-Z][A-Z0-9_]*$');

  /// Refuses anything that looks like a secret, so a key pasted into the
  /// profile is never used or copied into a report: fields named like
  /// secrets (`key`, `apiKey`, `token`, `secret`, `password` …, except the
  /// `…Ref(s)` references), values containing a key pattern anywhere,
  /// and secret-looking `extraHeaders` (auth header names, `Bearer …`,
  /// long random-looking values).
  static void _rejectSecrets(Object? v, [String path = '']) {
    switch (v) {
      case final Map<String, Object?> m:
        for (final e in m.entries) {
          final key = e.key.toLowerCase();
          final where = '$path${e.key}';
          if (e.value is String && _isSecretField(e.key)) {
            throw FormatException(
              'Profil darf keinen Schlüssel enthalten ($where); '
              'der Key kommt aus der Umgebungsvariable',
            );
          }
          if (path == '' && key == 'extraheaders') {
            _rejectSecretHeaders(e.value);
          }
          _rejectSecrets(e.value, '$where.');
        }
      case final List<Object?> l:
        for (final x in l) {
          _rejectSecrets(x, path);
        }
      case final String s when _keyLike.hasMatch(s):
        throw FormatException(
          'Profil enthält etwas, das wie ein API-Key aussieht ($path)',
        );
      case _:
        break;
    }
  }

  /// Whether a field name is a secret: one of its words (camelCase,
  /// `_`, `-`) is `key`, `token`, `secret`, `password` …; references
  /// (`secretRef`, `tokenSecretRef`, `secretRefs`) are fine.
  static bool _isSecretField(String name) {
    final words = name
        .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]}')
        .toLowerCase()
        .split(RegExp(r'[\s_\-]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isNotEmpty && (words.last == 'ref' || words.last == 'refs')) {
      return false;
    }
    return words.any(_secretWords.contains);
  }

  static const _secretWords = {
    'key',
    'apikey',
    'token',
    'secret',
    'password',
    'passwd',
    'credential',
    'credentials',
  };

  static void _rejectSecretHeaders(Object? headers) {
    if (headers is! Map<String, Object?>) return;
    for (final e in headers.entries) {
      final name = e.key.toLowerCase();
      final value = '${e.value}';
      final authName =
          name == 'authorization' ||
          name.contains('api-key') ||
          name.contains('apikey') ||
          name.contains('token') ||
          name.contains('secret');
      if (authName ||
          value.toLowerCase().startsWith('bearer ') ||
          (!_harmlessHeaders.contains(name) &&
              !_wordList.hasMatch(value) &&
              _randomLooking.hasMatch(value))) {
        throw FormatException(
          'extraHeaders.${e.key} sieht nach einem Geheimnis aus; Keys nur '
          'über die Umgebungsvariable',
        );
      }
    }
  }

  static final _keyLike = RegExp(
    r'(sk-|sk_|phala-|rp-|xai-|gsk_)[A-Za-z0-9_-]{16,}',
  );

  /// Known headers without secrets (beta flags, versions, attribution).
  static const _harmlessHeaders = {
    'anthropic-beta',
    'anthropic-version',
    'x-title',
    'http-referer',
    'referer',
    'openai-beta',
  };

  /// Values made of hyphen- or comma-separated words such as
  /// `interleaved-thinking-2025-05-14` or `a-b,c-d`: flags, not tokens
  /// (every part at most 12 characters).
  static final _wordList = RegExp(
    r'^[A-Za-z0-9]{1,12}([-,][A-Za-z0-9]{1,12})+$',
  );

  /// 24+ characters of letters/digits (with `_-.`) mixing letters and
  /// digits: typical for tokens.
  static final _randomLooking = RegExp(
    r'^(?=.*[0-9])(?=.*[A-Za-z])[A-Za-z0-9_\-.]{24,}$',
  );
}

/// [CostEstimator] backed by a [CostCalculator].
final class CatalogCostEstimator implements CostEstimator {
  /// Creates the estimator.
  const CatalogCostEstimator(this.calculator);

  /// Price source.
  final CostCalculator calculator;

  @override
  int? estimateMicros({
    required String profileId,
    required String modelId,
    required Usage usage,
  }) => calculator.costMicros(modelId, usage);
}
