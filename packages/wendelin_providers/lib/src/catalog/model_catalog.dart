import 'dart:convert';

import 'package:meta/meta.dart';

/// Prices of one model in **micro-USD per million tokens** (`$1.00 / MTok`
/// is `1000000`). Integers avoid rounding drift.
@immutable
final class ModelPrice {
  /// Creates a price from micro-USD per million tokens.
  const ModelPrice({
    required this.input,
    required this.output,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  /// Creates a price from USD per million tokens (as published).
  factory ModelPrice.usd({
    required num input,
    required num output,
    num cacheRead = 0,
    num cacheWrite = 0,
  }) => ModelPrice(
    input: _micros(input),
    output: _micros(output),
    cacheRead: _micros(cacheRead),
    cacheWrite: _micros(cacheWrite),
  );

  static int _micros(num usd) => (usd * 1000000).round();

  /// Uncached input.
  final int input;

  /// Output.
  final int output;

  /// Prompt-cache read.
  final int cacheRead;

  /// Prompt-cache write.
  final int cacheWrite;

  /// JSON in USD per million tokens.
  Map<String, Object?> toJson() => {
    'input': input / 1000000,
    'output': output / 1000000,
    'cacheRead': cacheRead / 1000000,
    'cacheWrite': cacheWrite / 1000000,
  };

  @override
  bool operator ==(Object other) =>
      other is ModelPrice &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite;

  @override
  int get hashCode => Object.hash(input, output, cacheRead, cacheWrite);

  @override
  String toString() =>
      'ModelPrice(in: $input, out: $output, cacheRead: $cacheRead, '
      'cacheWrite: $cacheWrite µUSD/MTok)';
}

/// A model with prices and known properties.
@immutable
final class ModelEntry {
  /// Creates an entry.
  const ModelEntry({
    required this.id,
    required this.price,
    this.name,
    this.contextWindow,
    this.supportsVision,
    this.longContextThreshold,
    this.longContextPrice,
  });

  /// Model id as used in requests.
  final String id;

  /// Display name, if different from [id].
  final String? name;

  /// Name for the UI (defaults to [id]).
  String get displayName => name ?? id;

  /// Standard price.
  final ModelPrice price;

  /// Context window in tokens, if known.
  final int? contextWindow;

  /// Whether image input works, if known.
  final bool? supportsVision;

  /// Prompt size (all input tokens incl. cache) above which
  /// [longContextPrice] applies, if the model has such a tier.
  final int? longContextThreshold;

  /// Price above [longContextThreshold].
  final ModelPrice? longContextPrice;

  /// Price for a request with [promptTokens] input tokens.
  ModelPrice priceFor(int promptTokens) {
    final threshold = longContextThreshold;
    final long = longContextPrice;
    return threshold != null && long != null && promptTokens > threshold
        ? long
        : price;
  }

  /// Applies the fields present in [json] (user override, USD per MTok).
  ModelEntry merge(Map<String, Object?> json) {
    num? n(String key) => json[key] is num ? json[key]! as num : null;
    ModelPrice priceFrom(ModelPrice base, String prefix) {
      int pick(String key, int current) {
        final v = n('$prefix$key');
        return v == null ? current : (v * 1000000).round();
      }

      String k(String s) =>
          prefix.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
      return ModelPrice(
        input: pick(k('input'), base.input),
        output: pick(k('output'), base.output),
        cacheRead: pick(k('cacheRead'), base.cacheRead),
        cacheWrite: pick(k('cacheWrite'), base.cacheWrite),
      );
    }

    final threshold = n('longContextThreshold')?.toInt();
    final hasLong = json.keys.any((key) => key.startsWith('longContext'));
    return ModelEntry(
      id: id,
      name: json['displayName'] is String
          ? json['displayName']! as String
          : name,
      price: priceFrom(price, ''),
      contextWindow: n('contextWindow')?.toInt() ?? contextWindow,
      supportsVision: json['supportsVision'] is bool
          ? json['supportsVision']! as bool
          : supportsVision,
      longContextThreshold: threshold ?? longContextThreshold,
      longContextPrice: hasLong
          ? priceFrom(longContextPrice ?? price, 'longContext')
          : longContextPrice,
    );
  }

  /// JSON for export (USD per MTok).
  Map<String, Object?> toJson() => {
    if (name != null) 'displayName': name,
    ...price.toJson(),
    if (contextWindow != null) 'contextWindow': contextWindow,
    if (supportsVision != null) 'supportsVision': supportsVision,
    if (longContextThreshold != null)
      'longContextThreshold': longContextThreshold,
    if (longContextPrice != null) ...{
      for (final e in longContextPrice!.toJson().entries)
        'longContext${e.key[0].toUpperCase()}${e.key.substring(1)}': e.value,
    },
  };

  @override
  String toString() => 'ModelEntry($id)';
}

/// Known models with prices. The user can override or add entries by
/// merging JSON ([mergeJson]).
///
/// JSON format (prices in USD per million tokens, every field optional for
/// existing models; new models need `input` and `output`):
///
/// ```json
/// {"models": {"gpt-4.1": {"input": 2.0, "output": 8.0, "cacheRead": 0.5,
///   "cacheWrite": 0, "displayName": "GPT-4.1", "contextWindow": 1000000,
///   "supportsVision": true, "longContextThreshold": 100000,
///   "longContextInput": 4.0}}}
/// ```
@immutable
final class ModelCatalog {
  /// Creates a catalog from [entries] (later ids win).
  ModelCatalog(Iterable<ModelEntry> entries)
    : _entries = Map.unmodifiable({for (final e in entries) e.id: e});

  /// The built-in catalog (prices as of 2026-10, see `builtInModels`).
  factory ModelCatalog.builtIn() => ModelCatalog(builtInModels);

  final Map<String, ModelEntry> _entries;

  /// All entries.
  Iterable<ModelEntry> get entries => _entries.values;

  /// Finds the entry for [modelId]: exact match, then without a vendor
  /// prefix (`openai/gpt-4.1` → `gpt-4.1`), then the longest catalog id
  /// followed by `-` (dated snapshots such as `claude-haiku-4-5-20251001`).
  ModelEntry? lookup(String modelId) {
    final exact = _entries[modelId];
    if (exact != null) return exact;
    final slash = modelId.lastIndexOf('/');
    if (slash >= 0) {
      final bare = _entries[modelId.substring(slash + 1)];
      if (bare != null) return bare;
    }
    final name = slash >= 0 ? modelId.substring(slash + 1) : modelId;
    ModelEntry? best;
    for (final e in _entries.values) {
      if (name.startsWith('${e.id}-') &&
          (best == null || e.id.length > best.id.length)) {
        best = e;
      }
    }
    return best;
  }

  /// Returns a catalog with the entries of [json] merged in (see class
  /// docs). Throws [FormatException] for malformed input.
  ModelCatalog mergeJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?> ||
        decoded['models'] is! Map<String, Object?>) {
      throw const FormatException('ModelCatalog: Objekt "models" erwartet');
    }
    final updated = Map.of(_entries);
    (decoded['models']! as Map<String, Object?>).forEach((id, value) {
      if (value is! Map<String, Object?>) {
        throw FormatException('ModelCatalog: "$id" ist kein Objekt');
      }
      final base = updated[id];
      if (base == null && (value['input'] is! num || value['output'] is! num)) {
        throw FormatException(
          'ModelCatalog: neues Modell "$id" braucht input und output',
        );
      }
      updated[id] =
          (base ??
                  ModelEntry(
                    id: id,
                    price: const ModelPrice(input: 0, output: 0),
                  ))
              .merge(value);
    });
    return ModelCatalog(updated.values);
  }

  /// Exports all entries in the [mergeJson] format.
  String toJson() => jsonEncode({
    'models': {for (final e in _entries.values) e.id: e.toJson()},
  });
}

/// Built-in prices in USD per million tokens. Claude prices from the
/// Anthropic model overview (2026-10); cache write = 5-minute TTL (1.25 ×
/// input). OpenAI and Mistral prices are published list prices and may
/// change – users can override them.
final builtInModels = <ModelEntry>[
  // Anthropic
  _claude('claude-fable-5-1', 'Claude Fable 5.1', 10, 50, 0.25),
  _claude('claude-fable-5', 'Claude Fable 5', 10, 50, 1),
  _claude('claude-opus-5-5', 'Claude Opus 5.5', 4, 20, 0.20),
  _claude('claude-opus-5', 'Claude Opus 5', 5, 25, 0.5),
  _claude('claude-opus-4-8', 'Claude Opus 4.8', 5, 25, 0.5),
  _claude('claude-opus-4-7', 'Claude Opus 4.7', 5, 25, 0.5),
  _claude('claude-opus-4-6', 'Claude Opus 4.6', 5, 25, 0.5),
  _claude('claude-sonnet-5-5', 'Claude Sonnet 5.5', 2, 10, 0.20),
  _claude('claude-sonnet-5', 'Claude Sonnet 5', 2, 10, 0.20),
  _claude('claude-sonnet-4-6', 'Claude Sonnet 4.6', 3, 15, 0.30),
  ModelEntry(
    id: 'claude-haiku-5-5',
    name: 'Claude Haiku 5.5',
    price: ModelPrice.usd(
      input: 0.10,
      output: 0.50,
      cacheRead: 0.01,
      cacheWrite: 0.125,
    ),
    contextWindow: 1000000,
    supportsVision: true,
    longContextThreshold: 100000,
    longContextPrice: ModelPrice.usd(
      input: 0.50,
      output: 2.50,
      cacheRead: 0.05,
      cacheWrite: 0.625,
    ),
  ),
  _claude('claude-haiku-4-5', 'Claude Haiku 4.5', 1, 5, 0.10, context: 200000),
  // OpenAI
  _openAi('gpt-5', 1.25, 10, 0.125),
  _openAi('gpt-5-mini', 0.25, 2, 0.025),
  _openAi('gpt-5-nano', 0.05, 0.40, 0.005),
  _openAi('gpt-4.1', 2, 8, 0.50),
  _openAi('gpt-4.1-mini', 0.40, 1.60, 0.10),
  _openAi('gpt-4.1-nano', 0.10, 0.40, 0.025),
  _openAi('gpt-4o', 2.50, 10, 1.25),
  _openAi('gpt-4o-mini', 0.15, 0.60, 0.075),
  // Mistral
  ModelEntry(
    id: 'mistral-small-latest',
    name: 'Mistral Small',
    price: ModelPrice.usd(input: 0.10, output: 0.30),
  ),
  ModelEntry(
    id: 'mistral-medium-latest',
    name: 'Mistral Medium',
    price: ModelPrice.usd(input: 0.40, output: 2),
  ),
  ModelEntry(
    id: 'mistral-large-latest',
    name: 'Mistral Large',
    price: ModelPrice.usd(input: 2, output: 6),
  ),
];

ModelEntry _claude(
  String id,
  String name,
  num input,
  num output,
  num cacheRead, {
  int context = 1000000,
}) => ModelEntry(
  id: id,
  name: name,
  price: ModelPrice.usd(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: input * 1.25,
  ),
  contextWindow: context,
  supportsVision: true,
);

ModelEntry _openAi(String id, num input, num output, num cacheRead) =>
    ModelEntry(
      id: id,
      price: ModelPrice.usd(input: input, output: output, cacheRead: cacheRead),
      supportsVision: true,
    );
