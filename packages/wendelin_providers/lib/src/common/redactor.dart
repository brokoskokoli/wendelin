import 'package:wendelin_core/wendelin_core.dart';

/// Removes secrets from texts before they end up in exceptions or logs.
///
/// Replaces every known secret value (the keys actually sent) and anything
/// that looks like an API key or bearer token with `***`.
final class Redactor {
  /// Creates a redactor that knows no secrets yet.
  Redactor();

  final Set<String> _secrets = {};

  static final _patterns = [
    RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
    RegExp(r'(Bearer\s+)[A-Za-z0-9_\-.~+/=]{8,}', caseSensitive: false),
    RegExp(
      r'((?:x-api-key|api[_-]?key|authorization|token)"?\s*[:=]\s*"?)'
      r'[A-Za-z0-9_\-.~+/=]{8,}',
      caseSensitive: false,
    ),
  ];

  /// Registers [secret] (ignored when shorter than 4 characters, which
  /// would mangle ordinary text).
  void addSecret(String secret) {
    if (secret.length >= 4) _secrets.add(secret);
  }

  /// Returns [text] without secrets.
  String apply(String text) {
    var result = text;
    for (final s in _secrets) {
      result = result.replaceAll(s, '***');
    }
    for (final p in _patterns) {
      result = result.replaceAllMapped(
        p,
        (m) => m.groupCount >= 1 && m.group(1) != null
            ? '${m.group(1)}***'
            : '***',
      );
    }
    return result;
  }

  /// Returns [e] with a redacted message (same type and extra fields).
  ProviderException redact(ProviderException e) {
    final m = apply(e.message);
    if (m == e.message) return e;
    return switch (e) {
      AuthException() => AuthException(m),
      RateLimitException(:final retryAfter) => RateLimitException(
        m,
        retryAfter: retryAfter,
      ),
      ProviderTimeoutException() => ProviderTimeoutException(m),
      NetworkException() => NetworkException(m),
      ServerException(:final statusCode) => ServerException(
        m,
        statusCode: statusCode,
      ),
      InvalidRequestException() => InvalidRequestException(m),
      CancelledException() => CancelledException(m),
      MalformedResponseException() => MalformedResponseException(m),
      AttestationFailedException(:final stage, :final unavailable) =>
        AttestationFailedException(m, stage: stage, unavailable: unavailable),
    };
  }
}
