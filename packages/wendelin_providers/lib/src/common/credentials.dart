import 'package:wendelin_core/wendelin_core.dart';

import 'redactor.dart';

/// Reads a secret from the `SecretStore` by its reference; `null` if absent.
typedef SecretReader = Future<String?> Function(String ref);

/// How an adapter sends an API key when [ApiKeyAuth.headerName] is unset.
enum ApiKeyStyle {
  /// `x-api-key: <key>` (Anthropic).
  xApiKey,

  /// `Authorization: Bearer <key>` (OpenAI-compatible).
  bearer,
}

/// Turns an [AuthMethod] into request headers, reading secrets lazily on
/// every request (so a changed key is picked up) and registering them with
/// a [Redactor].
final class Credentials {
  /// Credentials for [method], resolving secrets through [secrets].
  Credentials(this.method, this.secrets, {required this.style});

  /// Fixed API key (tests, live tests, CLI tools).
  factory Credentials.apiKey(String key, {required ApiKeyStyle style}) =>
      Credentials(const ApiKeyAuth('key'), (_) async => key, style: style);

  /// No authentication.
  factory Credentials.none() =>
      Credentials(const NoAuth(), (_) async => null, style: ApiKeyStyle.bearer);

  /// The configured method (contains only references).
  final AuthMethod method;

  /// Secret lookup.
  final SecretReader secrets;

  /// Default header style for [ApiKeyAuth].
  final ApiKeyStyle style;

  /// Resolves the auth headers and registers every secret with [redactor].
  /// Throws [AuthException] if a secret is missing or the method is not
  /// supported.
  Future<Map<String, String>> headers(Redactor redactor) async {
    switch (method) {
      case NoAuth():
        return const {};
      case ApiKeyAuth(:final secretRef, :final headerName):
        final key = await _read(secretRef, redactor);
        final header =
            headerName ??
            (style == ApiKeyStyle.xApiKey ? 'x-api-key' : 'Authorization');
        final value = header.toLowerCase() == 'authorization'
            ? 'Bearer $key'
            : key;
        return {header: value};
      case CustomHeadersAuth(:final secretRefsByHeader):
        return {
          for (final e in secretRefsByHeader.entries)
            e.key: await _read(e.value, redactor),
        };
      case OAuthPkceAuth():
        throw const AuthException('OAuth/PKCE wird noch nicht unterstützt');
    }
  }

  Future<String> _read(String ref, Redactor redactor) async {
    final value = await secrets(ref);
    if (value == null || value.trim().isEmpty) {
      throw AuthException('API-Key fehlt (Schlüssel "$ref")');
    }
    final trimmed = value.trim();
    redactor.addSecret(trimmed);
    return trimmed;
  }

  @override
  String toString() => 'Credentials($method)';
}
