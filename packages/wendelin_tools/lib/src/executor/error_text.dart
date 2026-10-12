/// Turns an exception thrown by a tool into a short, safe text for the
/// model: first line only (no stack trace), URLs without user info, query
/// string and fragment, values of secret-like parameters masked, at most
/// [maxLength] characters.
String sanitizeErrorText(Object error, {int maxLength = 200}) {
  var line = error.toString().split('\n').first.trim();
  line = line.replaceAllMapped(_url, (m) => '${m[1]}${m[3]}');
  line = line.replaceAllMapped(_secretParam, (m) => '${m[1]}***');
  line = line.replaceAllMapped(_bearer, (m) => '${m[1]}***');
  return line.length > maxLength
      ? '${line.substring(0, maxLength - 1)}…'
      : line;
}

// scheme://[userinfo@]host/path?query#fragment → scheme://host/path
final _url = RegExp(
  r'([a-zA-Z][a-zA-Z0-9+.-]*://)([^\s/@]*@)?([^\s?#]*)[^\s]*',
);

final _secretParam = RegExp(
  r'((?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|'
  r'password|passwort|pwd|auth|authorization|key|sig|signature)'
  r'"?\s*[=:]\s*"?(?:(?:bearer|basic)\s+)?)[^\s&",;]+',
  caseSensitive: false,
);

final _bearer = RegExp(
  r'((?:bearer|basic)\s+)[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
