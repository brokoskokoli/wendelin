/// Replacement for redacted values.
const redactedValue = '***';

/// Returns a deep copy of the JSON-like [value] with secrets replaced by
/// [redactedValue].
///
/// By key (see [shouldRedactField]): a field whose key names a credential
/// (`apiKey`, `Authorization`, `password`, `client_secret`, `privateKey`,
/// `auth`, `key`, …) is always replaced, whatever its type; a field whose key
/// merely contains the word `token`/`tokens` is replaced unless its value is
/// a number or boolean, so counters like `inputTokens: 12` stay readable.
///
/// Name/value pairs (`{name: 'Authorization', value: '…'}`, also with
/// `header`/`key` instead of `name`) have their `value` replaced when the
/// name names a secret.
///
/// By value: in every string, `Bearer <token>`, `sk-…` keys and secret
/// query parameters (`?api_key=…`, `&key=…`, `token=…`) are masked.
///
/// `null` stays `null`. Maps and lists are processed recursively.
Object? redactSecrets(Object? value) {
  if (value is Map<Object?, Object?>) {
    final pairName = _pairName(value);
    return <String, Object?>{
      for (final e in value.entries)
        '${e.key}':
            shouldRedactField('${e.key}', e.value) ||
                (pairName != null &&
                    e.key == 'value' &&
                    e.value != null &&
                    looksLikeSecretKey(pairName))
            ? redactedValue
            : redactSecrets(e.value),
    };
  }
  if (value is List<Object?>) return value.map(redactSecrets).toList();
  if (value is String) return redactSecretValues(value);
  return value;
}

/// Whether the field [key] with [value] must be redacted (see
/// [redactSecrets]). `null` values are never redacted.
bool shouldRedactField(String key, Object? value) {
  if (value == null) return false;
  return switch (_classify(key)) {
    _KeyClass.credential => true,
    _KeyClass.token => value is! num && value is! bool,
    _KeyClass.none => false,
  };
}

/// Whether [key] looks like it names a secret (credential or token key).
bool looksLikeSecretKey(String key) => _classify(key) != _KeyClass.none;

/// Masks secrets inside a free-text [value]: `Bearer …`, `sk-…` keys and
/// secret URL query parameters.
String redactSecretValues(String value) => value
    .replaceAllMapped(_bearer, (m) => '${m.group(1)} $redactedValue')
    .replaceAll(_skKey, redactedValue)
    .replaceAllMapped(_queryParam, (m) => '${m.group(1)}=$redactedValue');

enum _KeyClass { none, token, credential }

const _credentialFragments = [
  'apikey',
  'authorization',
  'password',
  'passwort',
  'passwd',
  'secret',
  'cookie',
  'credential',
  'privatekey',
  'bearer',
];

const _exactCredentialKeys = {'auth', 'key'};

final _separators = RegExp(r'[_\-.\s]');
final _wordBoundary = RegExp(r'[_\-.\s]+|(?<=[a-z0-9])(?=[A-Z])');

_KeyClass _classify(String key) {
  final joined = key.toLowerCase().replaceAll(_separators, '');
  if (_exactCredentialKeys.contains(joined) ||
      _credentialFragments.any(joined.contains)) {
    return _KeyClass.credential;
  }
  final words = key.split(_wordBoundary).map((w) => w.toLowerCase());
  if (words.any((w) => w == 'token' || w == 'tokens')) return _KeyClass.token;
  return _KeyClass.none;
}

String? _pairName(Map<Object?, Object?> map) {
  if (!map.containsKey('value')) return null;
  for (final k in const ['name', 'header', 'key']) {
    final n = map[k];
    if (n is String) return n;
  }
  return null;
}

final _bearer = RegExp(r'\b(Bearer|Basic)\s+[^\s"]+', caseSensitive: false);
final _skKey = RegExp(r'\bsk-[A-Za-z0-9_-]{16,}');
final _queryParam = RegExp(
  r'(?<=[?&])((?:api[_-]?key|key|access[_-]?token|token|auth|password|'
  r'secret|client[_-]?secret|sig|signature))=[^&\s#"]+',
  caseSensitive: false,
);
