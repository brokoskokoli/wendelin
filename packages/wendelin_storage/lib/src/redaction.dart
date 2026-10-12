/// Replacement for redacted values.
const redactedValue = '***';

/// Returns a deep copy of the JSON-like [value] in which every map entry
/// whose key looks like a secret is replaced by [redactedValue].
///
/// A key looks like a secret if, ignoring case and the separators `_`, `-`
/// and `.`, it contains `apikey`, `authorization`, `password`, `passwort`,
/// `secret` or `cookie`, or if one of its words is `token`/`tokens`
/// (`access_token`, `refreshToken`, `x-auth-token`). Numbers and booleans
/// are kept, so usage counters like `inputTokens: 12` stay readable;
/// `null` stays `null`. Maps and lists are processed recursively; other
/// values are returned unchanged.
Object? redactSecrets(Object? value) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final e in value.entries)
        '${e.key}': _isSecretKey('${e.key}') && _isRedactable(e.value)
            ? redactedValue
            : redactSecrets(e.value),
    };
  }
  if (value is List<Object?>) return value.map(redactSecrets).toList();
  return value;
}

/// Whether [key] looks like it names a secret (see [redactSecrets]).
bool looksLikeSecretKey(String key) => _isSecretKey(key);

const _secretFragments = [
  'apikey',
  'authorization',
  'password',
  'passwort',
  'secret',
  'cookie',
];

final _wordBoundary = RegExp(r'[_\-.\s]+|(?<=[a-z0-9])(?=[A-Z])');

bool _isSecretKey(String key) {
  final joined = key.toLowerCase().replaceAll(RegExp(r'[_\-.\s]'), '');
  if (_secretFragments.any(joined.contains)) return true;
  final words = key.split(_wordBoundary).map((w) => w.toLowerCase());
  return words.any((w) => w == 'token' || w == 'tokens');
}

bool _isRedactable(Object? value) =>
    value != null && value is! num && value is! bool;
