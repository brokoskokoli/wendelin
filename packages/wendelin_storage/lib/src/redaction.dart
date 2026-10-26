/// Replacement for redacted values.
const redactedValue = '***';

/// Returns a deep copy of the JSON-like [value] with secrets replaced by
/// [redactedValue].
///
/// By key (see [shouldRedactField]): a field whose key names a credential
/// (`apiKey`, `Authorization`, `password`, `client_secret`, `privateKey`,
/// `auth`, `key`, `basicAuth`, …) is always replaced, whatever its type; a
/// field whose key merely contains the word `token`/`tokens` is replaced
/// unless its value is a number or boolean, so counters like
/// `inputTokens: 12` stay readable.
///
/// Name/value pairs (`{name: 'Authorization', value: '…'}`, also with
/// `header`/`key` instead of `name`) have their `value` replaced when the
/// name names a secret.
///
/// WP155: the keys `pin` and `otp` (also as a word of a key, such as
/// `user_pin`) are always replaced; `code` for a string or a number of 4 or
/// more digits (a 3-digit HTTP status stays); `state` only for a string of 8 or more
/// characters (OAuth state), a device state such as `on` stays.
///
/// By value: in every string, `Bearer <token>`, `sk-…` keys and secret
/// query parameters (`?api_key=…`, `&key=…`, `token=…`, and `pin`/`otp`/`code`/`state`,
/// as in an OAuth callback `?code=…&state=…`) are masked.
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
    // WP155: an OAuth `state` is a long random string; a device state such as
    // `on`/`heat` is not a secret.
    _KeyClass.state => value is String ? value.length >= 8 : value is! bool,
    // WP155: `code` is a one-time code as a string or a number of 4+ digits;
    // a 3-digit number is an HTTP status and stays readable.
    _KeyClass.code => switch (value) {
      String() => true,
      num() => value.isFinite && value.abs().truncate().toString().length >= 4,
      _ => false,
    },
    _KeyClass.token => value is! num && value is! bool,
    _KeyClass.none => false,
  };
}

/// Whether [key] looks like it names a secret (credential or token key).
bool looksLikeSecretKey(String key) => switch (_classify(key)) {
  _KeyClass.credential || _KeyClass.token || _KeyClass.code => true,
  _KeyClass.state || _KeyClass.none => false,
};

/// Masks secrets inside a free-text [value]: `Bearer …`, `sk-…` keys and
/// secret URL query parameters.
String redactSecretValues(String value) => value
    .replaceAllMapped(_bearer, (m) => '${m.group(1)} $redactedValue')
    .replaceAll(_skKey, redactedValue)
    .replaceAllMapped(_queryParam, (m) => '${m.group(1)}=$redactedValue')
    .replaceAllMapped(
      _encodedQueryParam,
      (m) => '${m.group(1)}%3D$redactedValue',
    );

enum _KeyClass { none, token, credential, state, code }

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

// WP155: one-time codes and PINs (`pin`, `otp`, `code`, `user_pin`, `otpCode`)
// are credentials, whatever their type (`{"pin": 1234}`).
// `tan` (transaction number) is one as well.
const _exactCredentialKeys = {'auth', 'key', 'pin', 'otp'};
const _credentialWords = {'pin', 'otp', 'tan'};

// What makes a `…code` a one-time code (`verification_code`, `smsCode`,
// `auth-code`); `status_code`, `country_code`, `error_code`, `zip_code`
// stay readable.
const _codeQualifiers = [
  'verification',
  'verify',
  'auth',
  'authorization',
  'sms',
  'security',
  'confirm',
  'confirmation',
  'login',
  'access',
  'reset',
  'pairing',
  'activation',
  'recovery',
  'backup',
  'mfa',
  '2fa',
  'otp',
  'onetime',
  'twofactor',
  'pass',
];

bool _isOneTimeCode(String joined) =>
    _codeQualifiers.any((q) => joined.endsWith('${q}code'));

final _separators = RegExp(r'[_\-.\s]');
final _wordBoundary = RegExp(r'[_\-.\s]+|(?<=[a-z0-9])(?=[A-Z])');

_KeyClass _classify(String key) {
  final joined = key.toLowerCase().replaceAll(_separators, '');
  if (joined == 'code' || _isOneTimeCode(joined)) return _KeyClass.code;
  if (_exactCredentialKeys.contains(joined) ||
      _credentialFragments.any(joined.contains)) {
    return _KeyClass.credential;
  }
  final words = key
      .split(_wordBoundary)
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  // `basicAuth`, `proxy_auth`, `x-auth`: "auth" as the last word.
  if (words.isNotEmpty && words.last == 'auth') return _KeyClass.credential;
  if (words.any(_credentialWords.contains)) return _KeyClass.credential;
  if (words.isNotEmpty && words.last == 'state') {
    return _KeyClass.state;
  }
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
// Names of a secret in a query or fragment; the `…code` forms as in
// [_codeQualifiers] (`verification_code=…`).
const _queryKeys =
    r'api[_-]?key|key|access[_-]?token|token|auth|password|secret|'
    r'client[_-]?secret|sig|signature|pin|otp|tan|code|state|'
    r'(?:verification|verify|auth|authorization|sms|security|confirm|'
    r'confirmation|login|access|reset|pairing|activation|recovery|backup|'
    r'mfa|2fa|otp|one[_-]?time|two[_-]?factor|pass)[_-]?code';

// After `?`, `&` or `#` (fragment of an OAuth redirect).
final _queryParam = RegExp(
  '(?<=[?&#])($_queryKeys)=[^&\\s#"]+',
  caseSensitive: false,
);

// The same inside a URL-encoded value (`redirect_uri=https%3A%2F%2F…%3Fcode%3D…`):
// `%3F`, `%26` or `%23` in front, `%3D` as the equals sign.
final _encodedQueryParam = RegExp(
  '(?<=%3F|%26|%23)($_queryKeys)%3D(?:(?!%26|%23)[^&\\s"])+',
  caseSensitive: false,
);
